//
//  USBWriterViewModel.swift
//  Wist
//

import AppKit
import Combine
import Foundation

enum USBWriterError: LocalizedError {
    case usbVolumeMissing(String)
    case installImageMissing
    case isoMountFailed(String)
    case wimlibMissing(String)
    /// Files larger than ~4 GiB besides install.wim / install.esd — FAT32 cannot accept them in this flow.
    case fat32OversizeUnsupported(String)
    case insufficientSpace(needed: String, free: String)

    var errorDescription: String? {
        switch self {
        case .usbVolumeMissing(let p):
            return String(format: String(localized: "USB volume not found after formatting: %@"), p)
        case .installImageMissing:
            return String(localized: "The ISO has neither sources/install.wim nor sources/install.esd.")
        case .isoMountFailed(let s): return s
        case .wimlibMissing(let s): return s
        case .fat32OversizeUnsupported(let detail):
            return String(localized: "On FAT32 a single file cannot exceed ~4 GiB. The image contains files that cannot be split like install.wim:") + "\n" + detail
        case .insufficientSpace(let needed, let free):
            return String(format: String(localized: "Not enough space on the USB drive: need about %@, free %@."), needed, free)
        }
    }
}

/// Full flow: FAT32 USB → copy without huge install.wim/install.esd → wimlib split (WinDiskWriter-style).
@MainActor
final class USBWriterViewModel: ObservableObject {

    @Published private(set) var logLines: [String] = []
    /// True while at least one whole-disk write is in progress (supports parallel jobs on different devices).
    @Published private(set) var isWriting = false
    @Published var lastError: String?

    private var activeWriteDeviceIds: Set<String> = []

    private let usbVolumeLabel = "WINSETUP"
    private let wimChunkMB = "3800"

    func clearLog() {
        logLines = []
        lastError = nil
    }

    /// Log plus last error (if any) for copy-to-clipboard.
    var fullLogText: String {
        var s = logLines.joined(separator: "\n")
        if let e = lastError, !e.isEmpty {
            s += "\n\n--- lastError ---\n\(e)"
        }
        return s
    }

    func copyLogToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullLogText, forType: .string)
    }

    private func log(_ message: String) {
        logLines.append(message)
        if logLines.count > 50_000 {
            logLines.removeFirst(logLines.count - 50_000)
        }
    }

    /// Writes the Windows installer to a selected **whole** disk (`diskN`).
    /// - Parameter metadata: optional sidecar JSON at the volume root (`Wist.meta.json`) before sync/eject.
    /// - Returns: `nil` on success, otherwise a user-facing error string (also stored in `lastError` when no concurrent write overwrites it).
    @discardableResult
    func writeWindowsInstaller(isoURL: URL, drive: RemovableDriveInfo, metadata: WistUSBMetadata? = nil) async -> String? {
        guard !activeWriteDeviceIds.contains(drive.deviceIdentifier) else {
            let msg = String(format: String(localized: "Device %@ is already being written."), drive.deviceIdentifier)
            log(msg)
            return msg
        }
        activeWriteDeviceIds.insert(drive.deviceIdentifier)
        isWriting = true
        lastError = nil
        defer {
            activeWriteDeviceIds.remove(drive.deviceIdentifier)
            isWriting = !activeWriteDeviceIds.isEmpty
        }

        let devPath = "/dev/\(drive.deviceIdentifier)"

        do {
            log(String(localized: "— Wist: bootable USB write —"))
            log(String(format: String(localized: "Device: %@ — %@"), devPath, drive.mediaName))
            log(String(format: String(localized: "ISO: %@"), isoURL.path))

            log(String(format: String(localized: "[1/7] Erasing as MS-DOS (FAT32), volume label %@…"), usbVolumeLabel))
            try await runProcess(
                BundledToolLocator.diskutil,
                arguments: ["eraseDisk", "MS-DOS", usbVolumeLabel, "MBRFormat", devPath]
            )

            try await Task.sleep(nanoseconds: 1_500_000_000)

            log(String(localized: "[2/7] Waiting for USB to mount…"))
            let usbMount = try await waitForUSBMountPoint(wholeDisk: drive.deviceIdentifier)

            log(String(localized: "[3/7] Mounting ISO (read-only)…"))
            let isoMount: URL
            do {
                isoMount = try await HdiutilAttach.attachISOReadOnly(at: isoURL) { [weak self] line in
                    Task { @MainActor in self?.log(line) }
                }
            } catch {
                throw USBWriterError.isoMountFailed(error.localizedDescription)
            }
            log(String(format: String(localized: "ISO volume: %@"), isoMount.path))

            let installWim = isoMount.appendingPathComponent("sources/install.wim")
            let installEsd = isoMount.appendingPathComponent("sources/install.esd")
            let hasWim = FileManager.default.fileExists(atPath: installWim.path)
            let hasEsd = FileManager.default.fileExists(atPath: installEsd.path)
            guard hasWim || hasEsd else {
                try? await HdiutilAttach.detach(mountPoint: isoMount) { [weak self] line in
                    Task { @MainActor in self?.log(line) }
                }
                throw USBWriterError.installImageMissing
            }

            let installImage = hasWim ? installWim : installEsd

            log(String(localized: "[3b/7] Checking file sizes (FAT32 ≤ ~4 GiB per file)…"))
            let oversize = try ISOFat32Precheck.oversizeFiles(isoRoot: isoMount)
            try ISOFat32Precheck.validateOnlyInstallImagesAreOversize(oversize)
            try validateOversizeWithFind(isoMount: isoMount)

            log(String(localized: "[3c/7] USB free space vs copy size (without install.wim/esd)…"))
            try validateUsbFreeSpace(isoMount: isoMount, installImage: installImage, usbMount: usbMount)

            log(String(localized: "[3d/7] Locating wimlib-imagex…"))
            let wimlib: URL
            do {
                wimlib = try BundledToolLocator.wimlibImagexExecutable()
            } catch {
                try? await HdiutilAttach.detach(mountPoint: isoMount) { [weak self] line in
                    Task { @MainActor in self?.log(line) }
                }
                throw USBWriterError.wimlibMissing(error.localizedDescription)
            }
            log(String(format: String(localized: "wimlib-imagex: %@"), wimlib.path))

            log(String(localized: "[4/7] Copying files (no rsync; install.wim/esd skipped — split next)…"))
            try await WindowsISOFileCopy.copyTree(from: isoMount, to: usbMount) { [weak self] line in
                Task { @MainActor in self?.log(line) }
            }

            log(String(format: String(localized: "[5/7] Splitting %@ (wimlib split)…"), installImage.lastPathComponent))
            let splitDest = usbMount.appendingPathComponent("sources/install.swm")
            try await runProcess(
                wimlib,
                arguments: [
                    "split",
                    installImage.path,
                    splitDest.path,
                    wimChunkMB,
                ]
            )

            if let metadata {
                do {
                    try metadata.write(to: usbMount)
                    log(String(format: String(localized: "Metadata written: %@"), WistUSBMetadata.fileName))
                } catch {
                    log(String(format: String(localized: "Warning: could not write %@: %@"), WistUSBMetadata.fileName, error.localizedDescription))
                }
            }

            log(String(localized: "[6/7] Detaching ISO volume…"))
            try await HdiutilAttach.detach(mountPoint: isoMount) { [weak self] line in
                Task { @MainActor in self?.log(line) }
            }

            log(String(localized: "[7/7] Sync and eject USB…"))
            try await runProcess(URL(fileURLWithPath: "/bin/sync"), arguments: [])
            try await runProcess(
                BundledToolLocator.diskutil,
                arguments: ["eject", devPath]
            )

            log(String(localized: "Done. You can unplug the drive and use it to install Windows."))
            lastError = nil
            return nil
        } catch is CancellationError {
            let message = String(localized: "Operation canceled.")
            lastError = message
            log(String(localized: "Canceled."))
            return message
        } catch {
            let message: String
            if case ProcessRunnerError.failed(let code, let stderr) = error, code == 23 {
                let tail = stderr.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }.suffix(24).joined(separator: "\n")
                let extra = tail.isEmpty ? "" : "\n\nstderr:\n\(tail)"
                message = String(format: String(localized: "External command exited with code 23 (partial failure).%@"), extra)
            } else {
                message = error.localizedDescription
            }
            lastError = message
            log(String(format: String(localized: "Error: %@"), message))
            return message
        }
    }

    /// `find -size +3800m`: cross-check file sizes on ISO (sometimes differs from FileManager).
    private func validateOversizeWithFind(isoMount: URL) throws {
        let absPaths = ISOFat32Precheck.oversizePathsViaFind(isoRoot: isoMount)
        guard !absPaths.isEmpty else { return }
        let root = isoMount.path
        let allowed: Set<String> = ["sources/install.wim", "sources/install.esd"]
        var bad: [String] = []
        for abs in absPaths {
            var rel = String(abs.dropFirst(root.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            let key = rel.lowercased()
            if !allowed.contains(key) { bad.append(rel) }
        }
        guard !bad.isEmpty else { return }
        let detail = bad.map { "  • \($0)" }.joined(separator: "\n")
        throw USBWriterError.fat32OversizeUnsupported("(find) \(detail)")
    }

    private func validateUsbFreeSpace(isoMount: URL, installImage: URL, usbMount: URL) throws {
        guard let isoBytes = VolumeBytes.directoryUsageBytesShell(at: isoMount),
              let freeBytes = VolumeBytes.freeBytes(onVolumeContaining: usbMount) else { return }
        let fm = FileManager.default
        let installBytes: UInt64 = {
            guard let attrs = try? fm.attributesOfItem(atPath: installImage.path) else { return 0 }
            if let n = attrs[.size] as? NSNumber { return n.uint64Value }
            if let u = attrs[.size] as? UInt64 { return u }
            return 0
        }()
        guard installBytes > 0 else {
            log(String(localized: "Warning: install.wim/esd size unknown — free space check skipped."))
            return
        }
        let needBytes = isoBytes > installBytes ? isoBytes - installBytes : isoBytes
        let margin: UInt64 = 256 * 1024 * 1024
        guard needBytes + margin < freeBytes else {
            let fmt = ByteCountFormatter()
            fmt.allowedUnits = [.useGB, .useMB]
            fmt.countStyle = .file
            let needS = fmt.string(fromByteCount: Int64(needBytes + margin))
            let freeS = fmt.string(fromByteCount: Int64(freeBytes))
            throw USBWriterError.insufficientSpace(needed: needS, free: freeS)
        }
    }

    private func runProcess(_ executable: URL, arguments: [String]) async throws {
        try await ProcessRunner.runCollectingOutput(
            executableURL: executable,
            arguments: arguments,
            currentDirectoryURL: nil,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onStdoutLine: { [weak self] line in Task { @MainActor in self?.log(line) } },
            onStderrLine: { [weak self] line in Task { @MainActor in self?.log(line) } }
        )
    }

    /// After `eraseDisk`, locate the FAT32 volume mount (may be `/Volumes/WINSETUP` or `WINSETUP 1` if several are connected).
    private func waitForUSBMountPoint(wholeDisk: String) async throws -> URL {
        let slices = ["\(wholeDisk)s1", "\(wholeDisk)s2"]
        for attempt in 0 ..< 48 {
            for slice in slices {
                if let path = Self.mountPointFromDiskutil(sliceBSD: slice) {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                }
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw USBWriterError.usbVolumeMissing(String(format: String(localized: "Could not determine mount point for %@"), wholeDisk))
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
}
