//
//  MacOSUSBWriter.swift
//  Wist
//

import Combine
import Foundation

enum MacOSUSBWriterError: LocalizedError {
    case usbVolumeMissing(String)
    case createInstallMediaMissing(String)

    var errorDescription: String? {
        switch self {
        case .usbVolumeMissing(let detail):
            return String(localized: "USB volume not found after formatting:") + "\n" + detail
        case .createInstallMediaMissing(let appPath):
            return String(format: String(localized: "createinstallmedia not found in installer app: %@"), appPath)
        }
    }
}

@MainActor
final class MacOSUSBWriter: ObservableObject {
    enum Phase: Equatable {
        case idle
        case erasingDisk
        case waitingForMount
        case runningCreateInstallMedia
        case completed
        case failed(String)
    }

    @Published private(set) var logLines: [String] = []
    @Published private(set) var isWriting: Bool = false
    @Published var lastError: String?
    @Published private(set) var phase: Phase = .idle

    /// 0...1 inside the current `erasingDisk` subphase. Driven by stage tokens parsed from
    /// `diskutil eraseDisk` streamed output, with a slow time-based fallback so the bar
    /// keeps moving even when the tool is silent for a few seconds.
    @Published private(set) var erasingProgress: Double = 0

    /// 0...1 inside the current `waitingForMount` subphase. Time-based ramp toward 0.95,
    /// then snaps to 1.0 once the volume actually mounts.
    @Published private(set) var mountingProgress: Double = 0

    /// 0...1 inside the current `runningCreateInstallMedia` subphase. Combines the
    /// percentage parsed from `createinstallmedia` stdout with a bytes-written estimate
    /// based on the target volume's free-space delta. Monotonically non-decreasing.
    @Published private(set) var createInstallMediaProgress: Double?

    func clearLog() {
        logLines = []
        lastError = nil
        phase = .idle
        erasingProgress = 0
        mountingProgress = 0
        createInstallMediaProgress = nil
    }

    var fullLogText: String {
        var s = logLines.joined(separator: "\n")
        if let e = lastError, !e.isEmpty {
            s += "\n\n--- lastError ---\n\(e)"
        }
        return s
    }

    private func log(_ line: String) {
        logLines.append(line)
        if logLines.count > 50_000 {
            logLines.removeFirst(logLines.count - 50_000)
        }
    }

    /// v1: HFS+ GUID + `createinstallmedia --nointeraction`.
    ///
    /// - Parameters:
    ///   - installerAppURL: path to `Install macOS ... .app`
    ///   - drive: whole disk identifier, e.g. `disk7`
    ///   - volumeName: desired target volume name (Disk Utility label)
    /// - Returns: `nil` on success, otherwise user-facing error string.
    @discardableResult
    func createBootableInstallerUSB(
        installerAppURL: URL,
        drive: RemovableDriveInfo,
        volumeName: String = "Untitled"
    ) async -> String? {
        isWriting = true
        lastError = nil
        phase = .idle
        defer { isWriting = false }

        let devPath = "/dev/\(drive.deviceIdentifier)"
        let cim = installerAppURL
            .appendingPathComponent("Contents/Resources/createinstallmedia")

        guard FileManager.default.isExecutableFile(atPath: cim.path) else {
            let msg = MacOSUSBWriterError.createInstallMediaMissing(installerAppURL.path).localizedDescription
            lastError = msg
            log("Error: \(msg)")
            return msg
        }

        do {
            log("— macOS USB write —")
            log("Device: \(devPath) — \(drive.mediaName)")
            log("Installer: \(installerAppURL.path)")

            log("Preparing privileged helper…")
            try await PrivilegedHelperClient.prepareSession()

            log("[1/3] Erasing as Mac OS Extended (Journaled), GUID…")
            phase = .erasingDisk
            erasingProgress = 0
            try await runEraseDisk(devPath: devPath, volumeName: volumeName)
            erasingProgress = 1.0

            try await Task.sleep(nanoseconds: 1_500_000_000)

            log("[2/3] Waiting for USB to mount…")
            phase = .waitingForMount
            mountingProgress = 0
            let mount = try await waitForUSBMountPointWithProgress(wholeDisk: drive.deviceIdentifier)
            mountingProgress = 1.0

            log("[3/3] Running createinstallmedia…")
            phase = .runningCreateInstallMedia
            try await runCreateInstallMediaPrivileged(cim, mountPath: mount.path, installerAppURL: installerAppURL)

            if let volURL = Self.findMountedVolumeURL(forWholeDisk: drive.deviceIdentifier) {
                do {
                    let meta = try FluffyMacOSUSBMetadata.makeAfterWrite(
                        volumeRoot: volURL,
                        fallbackInstallerAppURL: installerAppURL
                    )
                    try meta.write(to: volURL)
                    log(String(format: String(localized: "Metadata written: %@"), FluffyMacOSUSBMetadata.fileName))
                    if UserDefaults.standard.bool(forKey: "fluffy.applyVolumeIconsToFluffyDrives") {
                        let globalRaw = UserDefaults.standard.string(forKey: FluffyUSBIconStyle.appStorageKey)
                        let overrideRaw = FluffyDriveIconOverrides.overrideStyleRawValue(for: drive.deviceIdentifier)
                        let raw = overrideRaw ?? globalRaw ?? FluffyUSBIconStyle.defaultStyle.rawValue
                        let style = FluffyUSBIconStyle.resolve(rawValue: raw)
                        try? FluffyVolumeIconManager.setVolumeIcon(style: style, mountPoint: volURL)
                    }
                } catch {
                    log(
                        String(
                            format: String(localized: "Warning: could not write %@ — %@"),
                            FluffyMacOSUSBMetadata.fileName,
                            error.localizedDescription
                        )
                    )
                }
            } else {
                log(String(localized: "Warning: could not locate mounted installer volume to write metadata."))
            }

            log("Done. You can reboot holding Option/Alt to select the installer.")
            phase = .completed
            return nil
        } catch is CancellationError {
            let msg = String(localized: "Operation canceled.")
            lastError = msg
            log("Canceled.")
            phase = .idle
            return msg
        } catch {
            let msg = error.localizedDescription
            lastError = msg
            log("Error: \(msg)")
            phase = .failed(msg)
            return msg
        }
    }

    /// Runs `diskutil eraseDisk` via the privileged helper and translates streamed output into a 0...1
    /// `erasingProgress`. `diskutil` does not emit explicit percentages, so we synthesize a
    /// monotonically increasing fraction from well-known stage tokens, with a slow time-based
    /// fallback to keep the UI alive between tokens.
    private func runEraseDisk(devPath: String, volumeName: String) async throws {
        let started = Date()
        let timer = Task { [weak self] in
            // Slow fallback ramp: aim for ~0.85 over 30s if the tool is quiet. Stage parsing below
            // can advance ahead of the timer; we only ever increase the value.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                await MainActor.run {
                    let elapsed = Date().timeIntervalSince(started)
                    let target = min(0.85, elapsed / 30.0)
                    if target > self.erasingProgress { self.erasingProgress = target }
                }
            }
        }
        defer { timer.cancel() }

        let code = try await PrivilegedHelperClient.runCommandStreaming(
            executablePath: BundledToolLocator.diskutil.path,
            arguments: ["eraseDisk", "JHFS+", volumeName, "GPT", devPath],
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onLine: { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.log(line)
                    self.advanceErasingProgress(forLine: line)
                }
            }
        )
        if code != 0 {
            throw ProcessRunnerError.failed(
                exitCode: code,
                stderr: "diskutil eraseDisk failed (\(code)) on \(devPath)"
            )
        }
    }

    /// Maps recognizable `diskutil eraseDisk` stage tokens to monotonic fractions.
    private func advanceErasingProgress(forLine line: String) {
        let s = line.lowercased()
        let target: Double?
        if s.contains("started erase") {
            target = 0.10
        } else if s.contains("unmounting") {
            target = 0.25
        } else if s.contains("creating the partition map") || s.contains("creating partition map") {
            target = 0.45
        } else if s.contains("waiting for partitions") {
            target = 0.55
        } else if s.contains("formatting") || s.contains("initialized") {
            target = 0.70
        } else if s.contains("mounting disk") {
            target = 0.85
        } else if s.contains("finished erase") {
            target = 1.00
        } else {
            target = nil
        }
        if let t = target, t > erasingProgress {
            erasingProgress = t
        }
    }

    private func runCreateInstallMediaPrivileged(_ executable: URL, mountPath: String, installerAppURL: URL) async throws {
        // `createinstallmedia` must be run as root. Use SMJobBless privileged helper to avoid TCC issues with `osascript`.
        let installerAppPath = executable
            .deletingLastPathComponent() // Resources
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // *.app
            .path

        createInstallMediaProgress = nil

        final class TailBuffer: @unchecked Sendable {
            private let lock = NSLock()
            private var lines: [String] = []

            func append(_ line: String) {
                lock.lock()
                lines.append(line)
                if lines.count > 250 { lines.removeFirst(lines.count - 250) }
                lock.unlock()
            }

            func snapshotLast(_ n: Int) -> [String] {
                lock.lock()
                let slice = Array(lines.suffix(n))
                lock.unlock()
                return slice
            }
        }

        let tail = TailBuffer()

        // Best-effort denominator for the bytes-written estimate: the on-disk size of the installer
        // .app bundle. Used as a fallback when `createinstallmedia` does not emit explicit
        // percentages for a given stage.
        let installerSize = await Self.directoryAllocatedSize(at: installerAppURL)

        // Volume-free-space baseline at the moment createinstallmedia takes ownership of the volume.
        // After this point, free space monotonically decreases as content lands on the USB stick.
        let baselineFreeBytes = Self.volumeAvailableBytes(atMount: mountPath) ?? 0

        let pollTask = Task { [weak self, installerSize, baselineFreeBytes, mountPath] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self else { return }
                let now = Self.volumeAvailableBytes(atMount: mountPath) ?? baselineFreeBytes
                let written = max(0, baselineFreeBytes - now)
                let denom = max(installerSize, Int64(1))
                let rawBytesRatio = Double(written) / Double(denom)
                // Align with stderr parsing policy: filesystem growth can plateau near the end
                // before `createinstallmedia` exits; never advertise 100% until the helper returns ok.
                let bytesProgress = min(0.99, rawBytesRatio)
                await MainActor.run {
                    self.advanceCreateInstallMediaProgress(bytesProgress)
                }
            }
        }
        defer { pollTask.cancel() }

        let code = try await PrivilegedHelperClient.runCreateInstallMediaStreaming(
            installerAppPath: installerAppPath,
            volumeMountPath: mountPath,
            onLine: { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.log(line)
                    tail.append(line)
                    self?.updateCreateInstallMediaProgress(from: line)
                }
            }
        )

        if code != 0 {
            throw ProcessRunnerError.failed(exitCode: code, stderr: tail.snapshotLast(120).joined(separator: "\n"))
        }
        // Only now that the privileged helper exited with exit code zero do we advertise 100%.
        createInstallMediaProgress = 1.0
    }

    private func updateCreateInstallMediaProgress(from rawLine: String) {
        var line = rawLine
        if line.hasPrefix("stdout: ") { line.removeFirst("stdout: ".count) }
        else if line.hasPrefix("stderr: ") { line.removeFirst("stderr: ".count) }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        let lc = line.lowercased()
        let copyPhaseHints = ["copy", "installer files", "adding", "installing", "transferring"]
        let mentionsCopyPhase = copyPhaseHints.contains { lc.contains($0) }

        // `createinstallmedia` emits an early "Erasing Disk: … … 100%" pass on the installer
        // partition. Taking the LAST `%` on that line falsely drives the rope bar to 100% before
        // the heavyweight copy/install leg even starts (`createinstallmedia` can run for tens of minutes).
        if (lc.contains("eras") || lc.contains("reformat") || lc.contains("formatting")),
           !mentionsCopyPhase
        {
            return
        }

        guard let re = try? NSRegularExpression(pattern: #"(\d{1,3})%"#) else { return }
        let slice: String = {
            if mentionsCopyPhase, let rng = line.range(of: "copy", options: .caseInsensitive) {
                String(line[rng.lowerBound...])
            } else {
                line
            }
        }()
        let ns = slice as NSString
        let matches = re.matches(in: slice, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return }
        let percentStr = ns.substring(with: last.range(at: 1))
        guard let v = Double(percentStr), v >= 0, v <= 100 else { return }
        advanceCreateInstallMediaProgress(v / 100.0)
    }

    /// Drives the `createinstallmedia` bar monotonically — stdout percentages + polled bytes —
    /// capped at **99 % until the helper process exits cleanly** (`createInstallMediaProgress = 1.0`
    /// is assigned only afterward so the rope bar can't claim completion early).
    private func advanceCreateInstallMediaProgress(_ value: Double) {
        let clamped = max(0, min(0.99, value))
        if let current = createInstallMediaProgress {
            if clamped > current {
                createInstallMediaProgress = clamped
            }
        } else {
            createInstallMediaProgress = clamped
        }
    }

    /// Returns volume free space in bytes (the system-supplied "available capacity" key).
    nonisolated private static func volumeAvailableBytes(atMount path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let bytes = values?.volumeAvailableCapacity {
            return Int64(bytes)
        }
        return nil
    }

    /// Sums allocated sizes for every regular file under `directoryURL`. Approximates `du -sk`.
    nonisolated private static func directoryAllocatedSize(at directoryURL: URL) async -> Int64 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int64, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: directoryURL,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles],
                    errorHandler: nil
                ) else {
                    cont.resume(returning: 0)
                    return
                }
                var total: Int64 = 0
                for case let url as URL in enumerator {
                    let values = try? url.resourceValues(forKeys: keys)
                    guard values?.isRegularFile == true else { continue }
                    if let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                        total += Int64(size)
                    }
                }
                cont.resume(returning: total)
            }
        }
    }

    /// After `createinstallmedia`, resolve mounts for all slices and pick the **installer** volume (has `Install*.app` + `createinstallmedia`).
    /// GPT sticks often mount EFI (s1) before the HFS+ installer partition — taking only the first mount wrote JSON / icons to the wrong place.
    nonisolated private static func findMountedVolumeURL(forWholeDisk wholeDisk: String) -> URL? {
        var mounts: [URL] = []
        for si in 1 ... 4 {
            let slice = "\(wholeDisk)s\(si)"
            guard let path = mountPointFromDiskutil(sliceBSD: slice) else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path),
                  mountPoint(url, belongsToWholeDisk: wholeDisk)
            else {
                continue
            }
            mounts.append(url)
        }
        return FluffyMacOSUSBMetadata.preferredVolumeRootForInstaller(among: mounts)?.absoluteURL
    }

    /// After `eraseDisk`, locate a mounted volume belonging to the whole disk while exposing
    /// a 0...0.95 time-based `mountingProgress` so the UI bar fills as we wait.
    private func waitForUSBMountPointWithProgress(wholeDisk: String) async throws -> URL {
        let slices = ["\(wholeDisk)s1", "\(wholeDisk)s2", "\(wholeDisk)s3"]
        let started = Date()
        let totalIterations = 48
        for i in 0 ..< totalIterations {
            for slice in slices {
                if let path = Self.mountPointFromDiskutil(sliceBSD: slice) {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path),
                       Self.mountPoint(url, belongsToWholeDisk: wholeDisk) {
                        return url
                    }
                }
            }
            let elapsed = Date().timeIntervalSince(started)
            // Two complementary ramps: fraction by iteration and a soft time-based ceiling.
            // Cap at 0.95 so the bar never claims completion before the volume is real.
            let byIter = Double(i + 1) / Double(totalIterations) * 0.95
            let byTime = min(0.95, elapsed / 12.0)
            let target = min(0.95, max(byIter, byTime))
            if target > mountingProgress { mountingProgress = target }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw MacOSUSBWriterError.usbVolumeMissing(wholeDisk)
    }

    nonisolated private static func mountPointFromDiskutil(sliceBSD: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", "/dev/\(sliceBSD)"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any],
              let mp = dict["MountPoint"] as? String,
              !mp.isEmpty
        else { return nil }
        return mp
    }

    nonisolated private static func mountPoint(_ mount: URL, belongsToWholeDisk wholeDisk: String) -> Bool {
        guard let data = try? diskutilInfoPlist(pathOrDevice: mount.path) else { return false }
        guard let dict = try? plistDict(data) else { return false }
        if let parent = dict["ParentWholeDisk"] as? String, parent == wholeDisk {
            return true
        }
        if let dev = dict["DeviceIdentifier"] as? String {
            return wholeDiskFromSliceIdentifier(dev) == wholeDisk
        }
        if let node = dict["DeviceNode"] as? String {
            let id = node.hasPrefix("/dev/") ? String(node.dropFirst(5)) : node
            return wholeDiskFromSliceIdentifier(id) == wholeDisk
        }
        return false
    }

    nonisolated private static func diskutilInfoPlist(pathOrDevice: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", pathOrDevice]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MacOSUSBWriterError.usbVolumeMissing(pathOrDevice)
        }
        return out.fileHandleForReading.readDataToEndOfFile()
    }

    nonisolated private static func plistDict(_ data: Data) throws -> [String: Any] {
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (obj as? [String: Any]) ?? [:]
    }

    nonisolated private static func wholeDiskFromSliceIdentifier(_ deviceIdentifier: String) -> String? {
        if deviceIdentifier.range(of: #"^disk\\d+$"#, options: .regularExpression) != nil {
            return deviceIdentifier
        }
        guard let regex = try? NSRegularExpression(pattern: #"^(disk\\d+)s\\d+$"#) else { return nil }
        let ns = deviceIdentifier as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: deviceIdentifier, range: full), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

