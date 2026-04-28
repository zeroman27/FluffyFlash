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

    func clearLog() {
        logLines = []
        lastError = nil
        phase = .idle
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

            // Install/check privileged helper before any destructive operations (erase/write).
            log("Preparing privileged helper…")
            try PrivilegedHelperClient.installIfNeeded()

            log("[1/3] Erasing as Mac OS Extended (Journaled), GUID…")
            phase = .erasingDisk
            // JHFS+ == Mac OS Extended (Journaled)
            try await runProcess(
                BundledToolLocator.diskutil,
                arguments: ["eraseDisk", "JHFS+", volumeName, "GPT", devPath]
            )

            try await Task.sleep(nanoseconds: 1_500_000_000)

            log("[2/3] Waiting for USB to mount…")
            phase = .waitingForMount
            let mount = try await waitForUSBMountPoint(wholeDisk: drive.deviceIdentifier)

            log("[3/3] Running createinstallmedia…")
            phase = .runningCreateInstallMedia
            try await runCreateInstallMediaPrivileged(cim, mountPath: mount.path)

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

    private func runProcess(_ executable: URL, arguments: [String]) async throws {
        try await ProcessRunner.runCollectingOutput(
            executableURL: executable,
            arguments: arguments,
            currentDirectoryURL: nil,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onStdoutLine: { [weak self] line in Task { @MainActor [weak self] in self?.log(line) } },
            onStderrLine: { [weak self] line in Task { @MainActor [weak self] in self?.log(line) } }
        )
    }

    private func runCreateInstallMediaPrivileged(_ executable: URL, mountPath: String) async throws {
        // `createinstallmedia` must be run as root. Use SMJobBless privileged helper to avoid TCC issues with `osascript`.
        let installerAppPath = executable
            .deletingLastPathComponent() // Resources
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // *.app
            .path

        let (code, output) = try await PrivilegedHelperClient.runCreateInstallMedia(
            installerAppPath: installerAppPath,
            volumeMountPath: mountPath
        )

        if !output.isEmpty {
            for line in output.split(whereSeparator: \.isNewline) where !line.isEmpty {
                log(String(line))
            }
        }
        if code != 0 {
            throw ProcessRunnerError.failed(exitCode: code, stderr: output)
        }
    }

    /// After `eraseDisk`, locate a mounted volume belonging to the whole disk.
    private func waitForUSBMountPoint(wholeDisk: String) async throws -> URL {
        let slices = ["\(wholeDisk)s1", "\(wholeDisk)s2", "\(wholeDisk)s3"]
        for _ in 0 ..< 48 {
            for slice in slices {
                if let path = Self.mountPointFromDiskutil(sliceBSD: slice) {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path),
                       Self.mountPoint(url, belongsToWholeDisk: wholeDisk) {
                        return url
                    }
                }
            }
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

