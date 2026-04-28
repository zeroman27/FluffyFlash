//
//  MacOSEndToEndPipeline.swift
//  Wist
//

import Combine
import Foundation

@MainActor
final class MacOSEndToEndPipeline: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading
        case writingUSB(current: Int, total: Int)
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusLine: String = ""
    @Published private(set) var lastFailureLog: String?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var downloadEtaFormatted: String?
    @Published private(set) var downloadStatusLine: String?

    var isActive: Bool {
        switch phase {
        case .idle, .completed, .failed:
            return false
        case .downloading, .writingUSB:
            return true
        }
    }

    func reset() {
        phase = .idle
        statusLine = ""
        lastFailureLog = nil
        downloadProgress = nil
        downloadEtaFormatted = nil
        downloadStatusLine = nil
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
        statusLine = String(localized: "Downloading macOS installer…")

        let exportURL = outputDirectory.appendingPathComponent("mist-download-installer.json")
        let tempDownloadDirectory = outputDirectory.appendingPathComponent("mist-tmp", isDirectory: true)
        let pidFile = outputDirectory.appendingPathComponent("mist-download.pid")

        let startedAt = Date()
        var shouldTreatCancellationAsSuccess = false

        let downloadTask = Task {
            _ = try await MistCLITool.downloadInstaller(
                search: buildOrNameSearch,
                outputTypes: outputTypes,
                outputDirectory: outputDirectory,
                exportURL: exportURL,
                catalog: catalog,
                includeBetas: includeBetas,
                forceOverwrite: forceOverwrite,
                onOutputLine: { line in
                    logSink?(line)
                    Task { @MainActor in
                        self.statusLine = line
                    }
                }
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
                        if let total = expectedDownloadBytes, total > 0 {
                            self.downloadProgress = min(1.0, Double(downloaded) / Double(total))
                            self.downloadEtaFormatted = Self.formatETA(
                                downloaded: downloaded,
                                total: total,
                                bytesPerSecond: bps,
                                startedAt: startedAt,
                                now: now
                            )
                        } else {
                            self.downloadProgress = nil
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
                        await MainActor.run { self.statusLine = String(localized: "Finalizing…") }
                        await self.terminatePrivilegedMistIfRunning(pidFile: pidFile)
                        downloadTask.cancel()
                        break
                    }
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        do {
            try await downloadTask.value
        } catch is CancellationError {
            if !shouldTreatCancellationAsSuccess {
                pollTask.cancel()
                phase = .idle
                statusLine = ""
                downloadProgress = nil
                downloadEtaFormatted = nil
                downloadStatusLine = nil
                return
            }
        } catch {
            pollTask.cancel()
            lastFailureLog = "mist download failed:\n\(error.localizedDescription)"
            phase = .failed(error.localizedDescription)
            return
        }
        pollTask.cancel()

        guard let installerApp = Self.findNewestInstallerApp(in: outputDirectory) else {
            let msg = String(localized: "Download finished but no installer .app bundle was found in the output folder.")
            lastFailureLog = msg
            phase = .failed(msg)
            return
        }

        phase = .writingUSB(current: 0, total: drives.count)
        statusLine = String(localized: "Writing installer to USB…")
        downloadProgress = nil
        downloadEtaFormatted = nil
        downloadStatusLine = nil

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
        guard let data = try? Data(contentsOf: pidFile),
              let s = String(data: data, encoding: .utf8),
              let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 1
        else { return }
        _ = kill(pid, SIGTERM)
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

