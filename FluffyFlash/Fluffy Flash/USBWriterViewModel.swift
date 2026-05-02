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
    case metadataWriteFailed(String)
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
        case .metadataWriteFailed(let s):
            return s
        case .fat32OversizeUnsupported(let detail):
            // Two-line friendly explanation, then the list of files we cannot place
            // on FAT32. The technical "wimlib split" / 2^32-1 trivia stays in the log.
            let header = String(localized: "This USB is formatted as FAT32 and cannot store a single file larger than about 4 GB.")
            let middle = String(localized: "Fluffy splits the Windows install image (install.wim / install.esd) automatically, but this ISO has other oversized files we can’t split:")
            return "\(header)\n\(middle)\n\(detail)"
        case .insufficientSpace(let needed, let free):
            return String(format: String(localized: "Not enough space on the USB drive: need about %@, free %@."), needed, free)
        }
    }
}

/// Full flow: FAT32 USB → copy without huge install.wim/install.esd → wimlib split (WinDiskWriter-style).
@MainActor
final class USBWriterViewModel: ObservableObject {

    enum DriveStep: Int, CaseIterable, Equatable, Sendable {
        case erasingDisk = 1
        case waitingForMount
        case mountingISO
        case copyingFiles
        case splittingInstallImage
        case detachingISO
        case syncingAndEjecting

        var title: String {
            switch self {
            case .erasingDisk: return String(localized: "Erasing disk")
            case .waitingForMount: return String(localized: "Waiting for mount")
            case .mountingISO: return String(localized: "Mounting ISO")
            case .copyingFiles: return String(localized: "Copying files")
            case .splittingInstallImage: return String(localized: "Splitting install image")
            case .detachingISO: return String(localized: "Detaching ISO")
            case .syncingAndEjecting: return String(localized: "Sync & eject")
            }
        }
    }

    struct DriveProgress: Equatable, Sendable {
        var step: DriveStep
        /// 0…1 within the current step (best-effort).
        var stepProgress: Double
        /// 0…1 for the whole write (best-effort).
        var overallProgress: Double
        var detail: String?
        /// Best-effort ETA (seconds remaining) for the current step (usually copying).
        var stepEtaSeconds: Double?
        /// Best-effort ETA (seconds remaining) to finish the whole drive write.
        var overallEtaSeconds: Double?
        /// Smoothed throughput for the current step (bytes per second). 0 means unknown.
        var stepBytesPerSecond: Double = 0
    }

    @Published private(set) var logLines: [String] = []
    /// True while at least one whole-disk write is in progress (supports parallel jobs on different devices).
    @Published private(set) var isWriting = false
    @Published var lastError: String?

    @Published private(set) var perDriveProgress: [String: DriveProgress] = [:]

    private var activeWriteDeviceIds: Set<String> = []
    private var copyEtaState: [String: CopyETAState] = [:]
    private var splitEtaState: [String: SplitETAState] = [:]

    private let usbVolumeLabel = "WINSETUP"
    /// Chunk size for `wimlib-imagex split` in MiB.
    /// FAT32 max file size is 4,294,967,295 bytes; 4095 MiB stays safely below that limit.
    private let wimChunkMB = "4095"
    private let applyFinderIconKey = "fluffy.applyVolumeIconsToFluffyDrives"

    func clearLog() {
        logLines = []
        lastError = nil
        perDriveProgress = [:]
        copyEtaState = [:]
        splitEtaState = [:]
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
    /// - Parameter metadata: optional sidecar JSON at the volume root (`FluffyFlash.meta.json`) before sync/eject.
    /// - Returns: `nil` on success, otherwise a user-facing error string (also stored in `lastError` when no concurrent write overwrites it).
    @discardableResult
    /// `preMountedISO` — when supplied, we skip our own `hdiutil attach`/`detach`
    /// and reuse the caller's mount. The caller is responsible for detaching when
    /// every parallel writer finishes. This avoids racing N attach calls when the
    /// user flashes several USBs from the same ISO.
    func writeWindowsInstaller(
        isoURL: URL,
        drive: RemovableDriveInfo,
        metadata: WistUSBMetadata? = nil,
        preMountedISO: URL? = nil
    ) async -> String? {
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
        perDriveProgress[drive.deviceIdentifier] = DriveProgress(
            step: .erasingDisk,
            stepProgress: 0,
            overallProgress: 0,
            detail: nil,
            stepEtaSeconds: nil,
            overallEtaSeconds: nil
        )
        copyEtaState[drive.deviceIdentifier] = CopyETAState()
        splitEtaState[drive.deviceIdentifier] = SplitETAState()

        do {
            log(String(localized: "— Fluffy Flash: bootable USB write —"))
            log(String(format: String(localized: "Device: %@ — %@"), devPath, drive.mediaName))
            log(String(format: String(localized: "ISO: %@"), isoURL.path))

            log(String(format: String(localized: "[1/7] Erasing as MS-DOS (FAT32), volume label %@…"), usbVolumeLabel))
            setDriveStep(drive.deviceIdentifier, .erasingDisk, stepProgress: 0, detail: nil)
            try await runProcess(
                BundledToolLocator.diskutil,
                arguments: ["eraseDisk", "MS-DOS", usbVolumeLabel, "MBRFormat", devPath]
            )
            setDriveStep(drive.deviceIdentifier, .erasingDisk, stepProgress: 1, detail: nil)

            try await Task.sleep(nanoseconds: 1_500_000_000)

            log(String(localized: "[2/7] Waiting for USB to mount…"))
            setDriveStep(drive.deviceIdentifier, .waitingForMount, stepProgress: 0, detail: nil)
            let usbMount = try await waitForUSBMountPoint(wholeDisk: drive.deviceIdentifier)
            setDriveStep(drive.deviceIdentifier, .waitingForMount, stepProgress: 1, detail: usbMount.path)

            let isoMount: URL
            let ownsISOMount: Bool
            if let preMountedISO {
                log(String(format: String(localized: "[3/7] Reusing shared ISO mount: %@"), preMountedISO.path))
                setDriveStep(drive.deviceIdentifier, .mountingISO, stepProgress: 1, detail: preMountedISO.path)
                isoMount = preMountedISO
                ownsISOMount = false
            } else {
                log(String(localized: "[3/7] Mounting ISO (read-only)…"))
                setDriveStep(drive.deviceIdentifier, .mountingISO, stepProgress: 0, detail: nil)
                do {
                    isoMount = try await HdiutilAttach.attachISOReadOnly(at: isoURL) { [weak self] line in
                        Task { @MainActor in self?.log(line) }
                    }
                } catch {
                    throw USBWriterError.isoMountFailed(error.localizedDescription)
                }
                log(String(format: String(localized: "ISO volume: %@"), isoMount.path))
                setDriveStep(drive.deviceIdentifier, .mountingISO, stepProgress: 1, detail: isoMount.path)
                ownsISOMount = true
            }

            let installWim = isoMount.appendingPathComponent("sources/install.wim")
            let installEsd = isoMount.appendingPathComponent("sources/install.esd")
            let hasWim = FileManager.default.fileExists(atPath: installWim.path)
            let hasEsd = FileManager.default.fileExists(atPath: installEsd.path)
            guard hasWim || hasEsd else {
                if ownsISOMount {
                    try? await HdiutilAttach.detach(mountPoint: isoMount) { [weak self] line in
                        Task { @MainActor in self?.log(line) }
                    }
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
                if ownsISOMount {
                    try? await HdiutilAttach.detach(mountPoint: isoMount) { [weak self] line in
                        Task { @MainActor in self?.log(line) }
                    }
                }
                throw USBWriterError.wimlibMissing(error.localizedDescription)
            }
            log(String(format: String(localized: "wimlib-imagex: %@"), wimlib.path))

            // Source ISO SHA-256 in the background, so it usually finishes by the time
            // we get to writing metadata. Best-effort — if it fails, we just store nil.
            let sourceISOHashTask: Task<String?, Never> = Task.detached(priority: .utility) {
                await SHA256Hasher.hashFileBestEffort(at: isoURL)
            }

            log(String(localized: "[4/7] Copying files (no rsync; install.wim/esd skipped — split next)…"))
            setDriveStep(drive.deviceIdentifier, .copyingFiles, stepProgress: 0, detail: nil)
            try await WindowsISOFileCopy.copyTree(from: isoMount, to: usbMount, log: { [weak self] line in
                Task { @MainActor in self?.log(line) }
            }, onProgress: { [weak self] copied, total, rel in
                Task { @MainActor in
                    guard total > 0 else { return }
                    let p = Double(copied) / Double(total)
                    self?.updateCopyETA(deviceId: drive.deviceIdentifier, copiedBytes: copied, totalBytes: total)
                    self?.setDriveStep(drive.deviceIdentifier, .copyingFiles, stepProgress: p, detail: rel)
                }
            })

            log(String(format: String(localized: "[5/7] Splitting %@ (wimlib split)…"), installImage.lastPathComponent))
            setDriveStep(drive.deviceIdentifier, .splittingInstallImage, stepProgress: 0, detail: installImage.lastPathComponent)
            let splitDest = usbMount.appendingPathComponent("sources/install.swm")
            try await runWimlibSplitWithProgress(
                wimlibExecutable: wimlib,
                installImage: installImage,
                splitDest: splitDest,
                usbMount: usbMount,
                deviceId: drive.deviceIdentifier
            )
            setDriveStep(drive.deviceIdentifier, .splittingInstallImage, stepProgress: 1, detail: nil)

            if var metadata {
                let chunks = await collectSplitChunkInfos(in: usbMount.appendingPathComponent("sources"))
                metadata.splitChunks = chunks.isEmpty ? nil : chunks
                metadata.sourceIsoSHA256 = await sourceISOHashTask.value
                try await writeAndVerifyMetadata(metadata, to: usbMount, wholeDisk: drive.deviceIdentifier)
                if !chunks.isEmpty {
                    log(String(format: String(localized: "Hashed %lld split chunk(s) for verification."), Int64(chunks.count)))
                }
                log(String(format: String(localized: "Metadata written: %@"), WistUSBMetadata.fileName))

                // Optional: apply Finder icon automatically to Fluffy drives.
                if UserDefaults.standard.bool(forKey: applyFinderIconKey) {
                    let globalRaw = UserDefaults.standard.string(forKey: FluffyUSBIconStyle.appStorageKey)
                    let overrideRaw = FluffyDriveIconOverrides.overrideStyleRawValue(for: drive.deviceIdentifier)
                    let raw = overrideRaw ?? globalRaw ?? FluffyUSBIconStyle.defaultStyle.rawValue
                    let style = FluffyUSBIconStyle.resolve(rawValue: raw)
                    try? FluffyVolumeIconManager.setVolumeIcon(style: style, mountPoint: usbMount)
                }
            } else {
                sourceISOHashTask.cancel()
            }

            if ownsISOMount {
                log(String(localized: "[6/7] Detaching ISO volume…"))
                setDriveStep(drive.deviceIdentifier, .detachingISO, stepProgress: 0, detail: nil)
                try await HdiutilAttach.detach(mountPoint: isoMount) { [weak self] line in
                    Task { @MainActor in self?.log(line) }
                }
                setDriveStep(drive.deviceIdentifier, .detachingISO, stepProgress: 1, detail: nil)
            } else {
                log(String(localized: "[6/7] ISO mount stays attached for the other parallel writers."))
                setDriveStep(drive.deviceIdentifier, .detachingISO, stepProgress: 1, detail: nil)
            }

            log(String(localized: "[7/7] Sync and finalising USB…"))
            setDriveStep(drive.deviceIdentifier, .syncingAndEjecting, stepProgress: 0, detail: nil)
            try await runProcess(URL(fileURLWithPath: "/bin/sync"), arguments: [])
            if WistPreferences.autoEjectAfterWrite {
                try await runProcess(
                    BundledToolLocator.diskutil,
                    arguments: ["eject", devPath]
                )
                log(String(localized: "Drive ejected. You can unplug it now."))
            } else {
                log(String(localized: "Auto-eject is off — drive stays mounted so you can drop extra files on it."))
            }
            setDriveStep(drive.deviceIdentifier, .syncingAndEjecting, stepProgress: 1, detail: nil)

            log(String(localized: "Done. You can unplug the drive and use it to install Windows."))
            lastError = nil
            perDriveProgress[drive.deviceIdentifier] = DriveProgress(
                step: .syncingAndEjecting,
                stepProgress: 1,
                overallProgress: 1,
                detail: nil,
                stepEtaSeconds: nil,
                overallEtaSeconds: nil
            )
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

    private func setDriveStep(_ deviceId: String, _ step: DriveStep, stepProgress: Double, detail: String?) {
        // Weight the 7 steps, giving most of the time budget to copying + wim split.
        let weights: [DriveStep: Double] = [
            .erasingDisk: 0.08,
            .waitingForMount: 0.04,
            .mountingISO: 0.04,
            .copyingFiles: 0.55,
            .splittingInstallImage: 0.20,
            .detachingISO: 0.04,
            .syncingAndEjecting: 0.05,
        ]
        let ordered = DriveStep.allCases
        let clampedStepP = max(0, min(1, stepProgress))

        var done: Double = 0
        for s in ordered {
            if s == step { break }
            done += weights[s] ?? 0
        }
        let w = weights[step] ?? 0
        let overall = max(0, min(1, done + w * clampedStepP))

        perDriveProgress[deviceId] = DriveProgress(
            step: step,
            stepProgress: clampedStepP,
            overallProgress: overall,
            detail: detail,
            stepEtaSeconds: nil,
            overallEtaSeconds: nil
        )
    }

    private func runWimlibSplitWithProgress(
        wimlibExecutable: URL,
        installImage: URL,
        splitDest: URL,
        usbMount: URL,
        deviceId: String
    ) async throws {
        let fm = FileManager.default
        let installBytes: UInt64 = {
            guard let attrs = try? fm.attributesOfItem(atPath: installImage.path) else { return 0 }
            if let n = attrs[.size] as? NSNumber { return n.uint64Value }
            if let u = attrs[.size] as? UInt64 { return u }
            return 0
        }()

        let completion = CompletionFlag()
        let runTask = Task {
            defer { completion.markFinished() }
            try await ProcessRunner.runCollectingOutput(
                executableURL: wimlibExecutable,
                arguments: [
                    "split",
                    installImage.path,
                    splitDest.path,
                    wimChunkMB,
                ],
                currentDirectoryURL: nil,
                environment: HostToolPaths.environmentForBundledAndHostCLI(),
                onStdoutLine: { [weak self] line in Task { @MainActor in self?.log(line) } },
                onStderrLine: { [weak self] line in Task { @MainActor in self?.log(line) } }
            )
        }

        // Poll the produced install*.swm sizes as a proxy for progress.
        // Best-effort: updates only while the process runs.
        while !completion.isFinished {
            try Task.checkCancellation()
            do {
                // Avoid hammering the USB filesystem with frequent directory scans.
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                runTask.cancel()
                throw error
            }

            let written = swmWrittenBytes(usbMount: usbMount)
            if installBytes > 0, written > 0 {
                let p = Double(min(written, installBytes)) / Double(installBytes)
                updateSplitETA(deviceId: deviceId, writtenBytes: min(written, installBytes), totalBytes: installBytes)
                setDriveStep(deviceId, .splittingInstallImage, stepProgress: p, detail: installImage.lastPathComponent)
            }
        }

        // Ensure the process actually completed (or throws).
        try await runTask.value
        setDriveStep(deviceId, .splittingInstallImage, stepProgress: 1, detail: installImage.lastPathComponent)
    }

    private func swmWrittenBytes(usbMount: URL) -> UInt64 {
        let fm = FileManager.default
        let dir = usbMount.appendingPathComponent("sources", isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return 0
        }
        var total: UInt64 = 0
        for url in urls {
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix("install"), name.hasSuffix(".swm") else { continue }
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                total &+= UInt64(max(0, size))
            }
        }
        return total
    }

    private struct CopyETAState: Sendable {
        var lastSampleAt: Date?
        var lastCopiedBytes: UInt64 = 0
        var emaBytesPerSecond: Double = 0
    }

    private struct SplitETAState: Sendable {
        var lastSampleAt: Date?
        var lastWrittenBytes: UInt64 = 0
        var emaBytesPerSecond: Double = 0
    }

    private final class CompletionFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false

        var isFinished: Bool {
            lock.lock()
            defer { lock.unlock() }
            return finished
        }

        func markFinished() {
            lock.lock()
            finished = true
            lock.unlock()
        }
    }

    private static let etaRemainingAfterCopySeconds: Double = 12
    private static let etaRemainingAfterSplitSeconds: Double = 6

    private func updateCopyETA(deviceId: String, copiedBytes: UInt64, totalBytes: UInt64) {
        guard totalBytes > 0, copiedBytes <= totalBytes else { return }
        var state = copyEtaState[deviceId] ?? CopyETAState()
        let now = Date()

        if let lastAt = state.lastSampleAt {
            let dt = now.timeIntervalSince(lastAt)
            let delta = copiedBytes >= state.lastCopiedBytes ? (copiedBytes - state.lastCopiedBytes) : 0
            if dt > 0.2, delta > 0 {
                let inst = Double(delta) / dt
                let alpha = 0.25
                state.emaBytesPerSecond = state.emaBytesPerSecond <= 0 ? inst : (alpha * inst + (1 - alpha) * state.emaBytesPerSecond)
            }
        }

        state.lastSampleAt = now
        state.lastCopiedBytes = copiedBytes
        copyEtaState[deviceId] = state

        guard state.emaBytesPerSecond > 0 else { return }
        let remaining = Double(totalBytes - copiedBytes)
        let eta = remaining / state.emaBytesPerSecond

        if var p = perDriveProgress[deviceId], p.step == .copyingFiles {
            p.stepEtaSeconds = (eta.isFinite && eta >= 0 && eta < 365 * 24 * 3600) ? eta : nil
            p.overallEtaSeconds = p.stepEtaSeconds.map { $0 + Self.etaRemainingAfterCopySeconds }
            p.stepBytesPerSecond = state.emaBytesPerSecond
            perDriveProgress[deviceId] = p
        }
    }

    private func updateSplitETA(deviceId: String, writtenBytes: UInt64, totalBytes: UInt64) {
        guard totalBytes > 0, writtenBytes <= totalBytes else { return }
        var state = splitEtaState[deviceId] ?? SplitETAState()
        let now = Date()

        if let lastAt = state.lastSampleAt {
            let dt = now.timeIntervalSince(lastAt)
            let delta = writtenBytes >= state.lastWrittenBytes ? (writtenBytes - state.lastWrittenBytes) : 0
            if dt > 0.2, delta > 0 {
                let inst = Double(delta) / dt
                let alpha = 0.25
                state.emaBytesPerSecond = state.emaBytesPerSecond <= 0 ? inst : (alpha * inst + (1 - alpha) * state.emaBytesPerSecond)
            }
        }

        state.lastSampleAt = now
        state.lastWrittenBytes = writtenBytes
        splitEtaState[deviceId] = state

        guard state.emaBytesPerSecond > 0 else { return }
        let remaining = Double(totalBytes - writtenBytes)
        let eta = remaining / state.emaBytesPerSecond

        if var p = perDriveProgress[deviceId], p.step == .splittingInstallImage {
            p.stepEtaSeconds = (eta.isFinite && eta >= 0 && eta < 365 * 24 * 3600) ? eta : nil
            p.overallEtaSeconds = p.stepEtaSeconds.map { $0 + Self.etaRemainingAfterSplitSeconds }
            p.stepBytesPerSecond = state.emaBytesPerSecond
            perDriveProgress[deviceId] = p
        }
    }

    static func formatETA(seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0, seconds < 365 * 24 * 3600 else { return nil }
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
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
                    if FileManager.default.fileExists(atPath: url.path),
                       Self.mountPoint(url, belongsToWholeDisk: wholeDisk) {
                        return url
                    }
                }
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw USBWriterError.usbVolumeMissing(String(format: String(localized: "Could not determine mount point for %@"), wholeDisk))
    }

    /// Walks `sources/install.swm*` and returns one `SplitChunkInfo` per chunk
    /// (with streamed SHA-256). Robust to drives without any chunks.
    private func collectSplitChunkInfos(in sourcesDir: URL) async -> [SplitChunkInfo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: sourcesDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let chunks = entries
            .filter { $0.lastPathComponent.lowercased().hasPrefix("install.swm") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var out: [SplitChunkInfo] = []
        out.reserveCapacity(chunks.count)
        for url in chunks {
            let size: UInt64 = {
                if let v = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    return UInt64(max(0, v))
                }
                return 0
            }()
            let hash = await SHA256Hasher.hashFileBestEffort(at: url) ?? ""
            out.append(SplitChunkInfo(
                fileName: url.lastPathComponent,
                sizeBytes: size,
                sha256: hash
            ))
        }
        return out
    }

    private func writeAndVerifyMetadata(_ metadata: WistUSBMetadata, to usbMount: URL, wholeDisk: String) async throws {
        let metaURL = usbMount.appendingPathComponent(WistUSBMetadata.fileName)
        var lastErr: String?
        for attempt in 0 ..< 3 {
            do {
                try metadata.write(to: usbMount)
            } catch {
                lastErr = error.localizedDescription
            }
            // Verify presence (metadata is the signal for Fluffy drive detection).
            if FileManager.default.fileExists(atPath: metaURL.path) {
                return
            }
            try await Task.sleep(nanoseconds: 180_000_000)
        }
        let detail = lastErr.map { " \($0)" } ?? ""
        throw USBWriterError.metadataWriteFailed(
            String(format: String(localized: "Could not write %@ for %@.%@"), WistUSBMetadata.fileName, wholeDisk, detail)
        )
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

    /// Double-check a mount path belongs to the expected whole disk to avoid
    /// races when multiple drives share the same volume label (WINSETUP / WINSETUP 1).
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
            throw USBWriterError.usbVolumeMissing(pathOrDevice)
        }
        return out.fileHandleForReading.readDataToEndOfFile()
    }

    nonisolated private static func plistDict(_ data: Data) throws -> [String: Any] {
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (obj as? [String: Any]) ?? [:]
    }

    nonisolated private static func wholeDiskFromSliceIdentifier(_ deviceIdentifier: String) -> String? {
        if deviceIdentifier.range(of: #"^disk\d+$"#, options: .regularExpression) != nil {
            return deviceIdentifier
        }
        guard let regex = try? NSRegularExpression(pattern: #"^(disk\d+)s\d+$"#) else { return nil }
        let ns = deviceIdentifier as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: deviceIdentifier, range: full), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
