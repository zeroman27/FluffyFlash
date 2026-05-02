//
//  MacOSEndToEndPipeline.swift
//  Wist
//

import Combine
import Foundation

@MainActor
final class MacOSEndToEndPipeline: ObservableObject {
    /// `mist` completed normally vs we detected a cache hit from its `existingFile` error (no `--force`).
    private enum MistDownloadCacheOutcome: Sendable {
        case fetchedFresh
        case reusedExistingApp(URL)
    }

    enum Phase: Equatable {
        case idle
        case downloading
        case writingUSB(current: Int, total: Int)
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// User-facing status line. We deliberately keep this **silent during the download phase** so
    /// the UI never echoes raw `mist` stdout into both step cards. During download the dedicated
    /// `downloadActivityLine` is used; `statusLine` carries write-phase / final messages only.
    @Published private(set) var statusLine: String = ""
    @Published private(set) var lastFailureLog: String?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var downloadEtaFormatted: String?
    /// Short bytes/speed summary derived from filesystem polling (e.g. "1.2 GB · 12.0 MB/s").
    @Published private(set) var downloadStatusLine: String?
    /// Most recent meaningful line from `mist` stdout, with ANSI escapes and shell prefixes
    /// stripped. Lives only on the Download card; never leaks into the Write card.
    @Published private(set) var downloadActivityLine: String?
    /// Wall-clock when the download phase started; drives the Elapsed display in the UI.
    @Published private(set) var downloadStartedAt: Date?
    /// Wall-clock when we transitioned to writing the first USB drive.
    @Published private(set) var writeStartedAt: Date?

    var isActive: Bool {
        switch phase {
        case .idle, .completed, .failed:
            return false
        case .downloading, .writingUSB:
            return true
        }
    }

    private func makeMistProgressOutputSink(logSink: (@Sendable (String) -> Void)?) -> @Sendable (String) -> Void {
        { [weak self] line in
            logSink?(line)
            let cleaned = Self.stripMistDecoration(line)
            let parsed = Self.parseMistProgress(cleaned)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !cleaned.isEmpty {
                    self.downloadActivityLine = cleaned
                }
                if let percent = parsed.percent {
                    let next = max(self.downloadProgress ?? 0, percent)
                    self.downloadProgress = min(1.0, next)
                }
            }
        }
    }

    /// `mist` exits `1` immediately when an output artefact already exists and `--force` is off.
    /// If the `.app` already on disk is runnable, skip re-download; otherwise retry once with `--force`.
    private func runMistDownloadResolvingCachedInstaller(
        buildOrNameSearch: String,
        outputTypes: [MistCLITool.InstallerOutputType],
        outputDirectory: URL,
        exportURL: URL,
        catalog: MistCLITool.Catalog?,
        includeBetas: Bool,
        forceOverwrite: Bool,
        onOutputLine: @escaping @Sendable (String) -> Void
    ) async throws -> MistDownloadCacheOutcome {
        func download(_ force: Bool) async throws {
            _ = try await MistCLITool.downloadInstaller(
                search: buildOrNameSearch,
                outputTypes: outputTypes,
                outputDirectory: outputDirectory,
                exportURL: exportURL,
                catalog: catalog,
                includeBetas: includeBetas,
                forceOverwrite: force,
                onOutputLine: onOutputLine
            )
        }

        do {
            try await download(forceOverwrite)
            return .fetchedFresh
        } catch {
            guard !forceOverwrite,
                  case ProcessRunnerError.failed(let code, let stderr) = error,
                  code == 1
            else {
                throw error
            }

            if let quoted = Self.mistQuotedExistingInstallerPath(from: stderr) {
                let url = URL(fileURLWithPath: quoted)
                let cim = url.appendingPathComponent("Contents/Resources/createinstallmedia")
                if url.pathExtension.lowercased() == "app",
                   FileManager.default.isExecutableFile(atPath: cim.path)
                {
                    try await PrivilegedHelperClient.prepareSession()
                    try await MistCLITool.chownOutputDirectoryToInvoker(outputDirectory, onOutputLine: onOutputLine)
                    downloadActivityLine = String(localized: "Using cached installer from disk.")
                    downloadProgress = 1.0
                    return .reusedExistingApp(url)
                }
            }

            if Self.stderrIndicatesMistRefusedExistingOutput(stderr) {
                try await download(true)
                return .fetchedFresh
            }

            throw error
        }
    }

    func reset() {
        phase = .idle
        statusLine = ""
        lastFailureLog = nil
        downloadProgress = nil
        downloadEtaFormatted = nil
        downloadStatusLine = nil
        downloadActivityLine = nil
        downloadStartedAt = nil
        writeStartedAt = nil
    }

    func runInstallerToUSB(
        buildOrNameSearch: String,
        outputTypes: [MistCLITool.InstallerOutputType],
        outputDirectory: URL,
        expectedDownloadBytes: Int64?,
        drives: [RemovableDriveInfo],
        usbWriter: MacOSUSBWriter,
        catalog: MistCLITool.Catalog?,
        includeBetas: Bool,
        forceOverwrite: Bool,
        logSink: (@Sendable (String) -> Void)? = nil
    ) async {
        // Do not call reset() here: it sets `.idle` for one frame and makes the Home UI flicker
        // (running card flashes then disappears if download fails immediately).
        lastFailureLog = nil
        statusLine = ""
        downloadProgress = nil
        downloadEtaFormatted = nil
        downloadStatusLine = nil
        downloadActivityLine = nil
        downloadStartedAt = nil
        writeStartedAt = nil

        guard !drives.isEmpty else {
            phase = .failed(String(localized: "Select at least one USB drive."))
            return
        }
        guard !outputTypes.isEmpty else {
            phase = .failed(String(localized: "Select at least one output type (application/image/iso/package)."))
            return
        }

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        phase = .downloading
        downloadStartedAt = Date()
        downloadActivityLine = String(localized: "Starting download…")

        let exportURL = outputDirectory.appendingPathComponent("mist-download-installer.json")
        let tempDownloadDirectory = outputDirectory.appendingPathComponent("mist-tmp", isDirectory: true)
        let pidFile = outputDirectory.appendingPathComponent("mist-download.pid")

        // Snap the cache footprint **before** spawning `mist`. The UI used to compare raw `du`
        // of the entire output tree against `installer.sizeBytes`; if a previous run already
        // materialized ~18 GB in the cache folder, the fraction immediately hit 100% even when
        // the new download was only ~4% into the current package — see user report 2026-05-02.
        let baselineCacheBytes = max(
            await diskUsageBytes(url: outputDirectory),
            await diskUsageBytes(url: tempDownloadDirectory)
        )

        let startedAt = Date()
        var shouldTreatCancellationAsSuccess = false

        let mistProgressSink = makeMistProgressOutputSink(logSink: logSink)

        let downloadTask = Task<MistDownloadCacheOutcome, Error> {
            try await self.runMistDownloadResolvingCachedInstaller(
                buildOrNameSearch: buildOrNameSearch,
                outputTypes: outputTypes,
                outputDirectory: outputDirectory,
                exportURL: exportURL,
                catalog: catalog,
                includeBetas: includeBetas,
                forceOverwrite: forceOverwrite,
                onOutputLine: mistProgressSink
            )
        }

        let pollTask = Task {
            // Poll filesystem sizes to provide progress + ETA while privileged `mist` runs.
            var stableTicks = 0
            var lastDownloaded: Int64?
            var lastTime: Date?
            var emaBps: Double?

            func observeSpeed(bytes: Int64, now: Date) -> Double? {
                defer {
                    lastDownloaded = bytes
                    lastTime = now
                }
                guard let lb = lastDownloaded, let lt = lastTime else { return nil }
                let dt = now.timeIntervalSince(lt)
                guard dt > 0.2 else { return emaBps }
                let db = Double(max(0, bytes - lb))
                let instant = db / dt
                if let ema = emaBps {
                    let alpha = 0.25
                    emaBps = ema * (1 - alpha) + instant * alpha
                } else {
                    emaBps = instant
                }
                return emaBps
            }

            while !Task.isCancelled {
                if case .downloading = await self.phase {
                    let outBytes = await self.diskUsageBytes(url: outputDirectory)
                    let tmpBytes = await self.diskUsageBytes(url: tempDownloadDirectory)
                    let downloaded = max(outBytes, tmpBytes)

                    if let prev = lastDownloaded, prev == downloaded {
                        stableTicks += 1
                    } else {
                        stableTicks = 0
                    }

                    let now = Date()
                    let bps = observeSpeed(bytes: downloaded, now: now)

                    await MainActor.run {
                        self.downloadStatusLine = Self.formatDownloadStatus(bytes: downloaded, bps: bps)

                        let inc = max(0, downloaded - baselineCacheBytes)
                        let mistP = self.downloadProgress ?? 0

                        if let total = expectedDownloadBytes, total > 0 {
                            if inc <= total {
                                let fs = min(1.0, Double(inc) / Double(total))
                                self.downloadProgress = min(1.0, max(fs, mistP))
                            } else {
                                // Cached growth already exceeded catalog `sizeBytes` (bogus or stale).
                                // Never derive 100% from `inc/total` here — stick to stdout parsing instead.
                                if mistP > 0 {
                                    self.downloadProgress = min(1.0, mistP)
                                }
                                // Else: preserve whatever was already published (typically `nil` until
                                // the first `mist` percentage line arrives) rather than snapping to max.
                            }

                            self.downloadEtaFormatted = Self.formatETA(
                                downloaded: min(inc, total),
                                total: total,
                                bytesPerSecond: bps,
                                startedAt: startedAt,
                                now: now
                            )
                        } else {
                            // No catalog size: rely on mist-derived percentages populated in callbacks.
                            self.downloadEtaFormatted = nil
                        }
                    }

                    // If we already have a complete installer app and size is stable for a while,
                    // don't keep the UI stuck waiting for `mist` to exit.
                    if stableTicks >= 8,
                       let app = Self.findNewestInstallerApp(in: outputDirectory),
                       FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/Resources/createinstallmedia").path)
                    {
                        shouldTreatCancellationAsSuccess = true
                        await MainActor.run {
                            self.downloadActivityLine = String(localized: "Finalizing download…")
                        }
                        await self.terminatePrivilegedMistIfRunning(pidFile: pidFile)
                        downloadTask.cancel()
                        break
                    }
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        let cacheOutcome: MistDownloadCacheOutcome
        do {
            cacheOutcome = try await downloadTask.value
        } catch is CancellationError {
            if !shouldTreatCancellationAsSuccess {
                pollTask.cancel()
                phase = .idle
                statusLine = ""
                downloadProgress = nil
                downloadEtaFormatted = nil
                downloadStatusLine = nil
                downloadActivityLine = nil
                downloadStartedAt = nil
                return
            }
            // Poll layer cancelled `mist` early after detecting a complete cached `.app`; behave like
            // a normal fetch and resolve the bundle from disk below.
            cacheOutcome = .fetchedFresh
        } catch {
            pollTask.cancel()
            lastFailureLog = "mist download failed:\n\(error.localizedDescription)"
            phase = .failed(error.localizedDescription)
            return
        }
        pollTask.cancel()

        let installerApp: URL
        switch cacheOutcome {
        case .fetchedFresh:
            if let app = Self.findNewestInstallerApp(in: outputDirectory) {
                installerApp = app
            } else {
                let msg = String(localized: "Download finished but no installer .app bundle was found in the output folder.")
                lastFailureLog = msg
                phase = .failed(msg)
                return
            }
        case let .reusedExistingApp(appURL):
            installerApp = appURL
        }

        phase = .writingUSB(current: 0, total: drives.count)
        statusLine = String(localized: "Writing installer to USB…")
        writeStartedAt = Date()
        // Freeze the download bar at 100% (rather than nil → indeterminate) so the completed
        // step does not visually shimmer after we have moved on to writing.
        downloadProgress = 1.0
        downloadEtaFormatted = nil
        downloadStatusLine = nil
        downloadActivityLine = String(localized: "Cached and ready.")

        for (idx, drive) in drives.enumerated() {
            phase = .writingUSB(current: idx + 1, total: drives.count)
            statusLine = String(
                format: String(localized: "Write %lld of %lld: %@"),
                Int64(idx + 1), Int64(drives.count), drive.mediaName
            )
            if let err = await usbWriter.createBootableInstallerUSB(installerAppURL: installerApp, drive: drive) {
                lastFailureLog = usbWriter.fullLogText
                phase = .failed(err)
                return
            }
        }

        phase = .completed
        statusLine = String(localized: "Done.")
        Task { await FluffyFinderIconAutomation.reapplyAfterUSBWriteBestEffort() }
    }

    nonisolated private static func findNewestInstallerApp(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        let apps = items.filter { $0.pathExtension.lowercased() == "app" }
        return apps
            .sorted {
                let da = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .first
    }
}

// MARK: - Progress helpers

private extension MacOSEndToEndPipeline {
    func terminatePrivilegedMistIfRunning(pidFile: URL) async {
        // Legacy osascript path used to leave a pid file behind. Try that first for compatibility.
        if let data = try? Data(contentsOf: pidFile),
           let s = String(data: data, encoding: .utf8),
           let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 1
        {
            _ = kill(pid, SIGTERM)
            return
        }
        // Helper-driven path has no pid file; ask the helper to terminate whatever it is running.
        _ = await PrivilegedHelperClient.killCurrentTask()
    }

    func diskUsageBytes(url: URL) async -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        // `du -sk` is much faster than enumerating file sizes in Swift for large trees.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return 0
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return 0 }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8) else { return 0 }
        let kb = Int64(s.split(whereSeparator: \.isWhitespace).first ?? "") ?? 0
        return kb * 1024
    }

    static func formatDownloadStatus(bytes: Int64, bps: Double?) -> String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file
        let size = fmt.string(fromByteCount: bytes)
        if let bps, bps > 0 {
            let speed = fmt.string(fromByteCount: Int64(bps)) + "/s"
            return "\(size) · \(speed)"
        }
        return size
    }

    /// Removes ANSI escape sequences and the `stdout: ` / `stderr: ` line prefix that the
    /// privileged helper prepends when streaming output back to the host.
    nonisolated static func stripMistDecoration(_ raw: String) -> String {
        var s = raw
        // Helper-prepended channel labels: "stdout: …" / "stderr: …".
        if s.hasPrefix("stdout: ") { s.removeFirst("stdout: ".count) }
        else if s.hasPrefix("stderr: ") { s.removeFirst("stderr: ".count) }

        // Strip CSI escape sequences (colours, cursor moves, line clears).
        if let re = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]") {
            let range = NSRange(location: 0, length: (s as NSString).length)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        // Sometimes ANSI sequences arrive without their leading ESC (lost in pipe transport),
        // showing up as literal "[1A" / "[K" / "[0;32m". Strip those defensively too.
        if let re = try? NSRegularExpression(pattern: "\\[[0-9;?]*[ABCDFGHJKSTfmsu]") {
            let range = NSRange(location: 0, length: (s as NSString).length)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Matches `mist-cli` `MistError.existingFile`: `Existing file: '…'. Use [--force] to overwrite.`
    nonisolated static func mistQuotedExistingInstallerPath(from stderr: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"Existing file: '([^']+)'"#, options: []) else {
            return nil
        }
        let ns = stderr as NSString
        guard let m = re.firstMatch(in: stderr, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1
        else { return nil }
        let path = ns.substring(with: m.range(at: 1))
        return path.isEmpty ? nil : path
    }

    nonisolated static func stderrIndicatesMistRefusedExistingOutput(_ stderr: String) -> Bool {
        let lc = stderr.lowercased()
        return lc.contains("existing file") && (lc.contains("[--force]") || lc.contains("overwrite"))
    }

    struct MistProgressParse {
        var percent: Double?
        var bytesDone: Int64?
        var bytesTotal: Int64?
    }

    /// Best-effort parser for `mist` progress lines such as
    /// "[ 2 / 6 ] InstallAssistant.pkg ... [ 03.18 GB / 18.24 GB (17.42%) ]".
    nonisolated static func parseMistProgress(_ line: String) -> MistProgressParse {
        var out = MistProgressParse()

        if let re = try? NSRegularExpression(pattern: #"\(\s*(\d+(?:\.\d+)?)\s*%\s*\)"#) {
            let ns = line as NSString
            let r = NSRange(location: 0, length: ns.length)
            if let m = re.firstMatch(in: line, options: [], range: r), m.numberOfRanges > 1 {
                let s = ns.substring(with: m.range(at: 1))
                if let v = Double(s), v >= 0, v <= 100 {
                    out.percent = v / 100.0
                }
            }
        }

        if let re = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*([KMGT]?B)\s*/\s*(\d+(?:\.\d+)?)\s*([KMGT]?B)"#, options: [.caseInsensitive]) {
            let ns = line as NSString
            let r = NSRange(location: 0, length: ns.length)
            if let m = re.firstMatch(in: line, options: [], range: r), m.numberOfRanges > 4 {
                if let done = parseBytes(ns.substring(with: m.range(at: 1)), unit: ns.substring(with: m.range(at: 2))),
                   let total = parseBytes(ns.substring(with: m.range(at: 3)), unit: ns.substring(with: m.range(at: 4)))
                {
                    out.bytesDone = done
                    out.bytesTotal = total
                    if out.percent == nil, total > 0 {
                        out.percent = min(1.0, Double(done) / Double(total))
                    }
                }
            }
        }

        return out
    }

    private nonisolated static func parseBytes(_ value: String, unit: String) -> Int64? {
        guard let v = Double(value) else { return nil }
        let multiplier: Double
        switch unit.uppercased() {
        case "B": multiplier = 1
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default: return nil
        }
        return Int64(v * multiplier)
    }

    static func formatETA(downloaded: Int64, total: Int64, bytesPerSecond: Double?, startedAt: Date, now: Date) -> String? {
        guard let bps = bytesPerSecond, bps > 0 else { return nil }
        let remaining = max(0, total - downloaded)
        let seconds = Double(remaining) / bps
        if seconds.isNaN || seconds.isInfinite { return nil }
        // Avoid overflow when converting very large Double -> Int.
        if seconds > Double(Int.max) { return nil }
        let whole = Int(seconds)
        let minutes = whole / 60
        let secs = whole % 60
        if minutes > 99 { return nil }
        return String(format: String(localized: "ETA %02d:%02d"), minutes, secs)
    }
}

// (speed estimator implemented inline in the poll task; avoids actor isolation issues under Swift 6)

