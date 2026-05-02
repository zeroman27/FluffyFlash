//
//  EndToEndMediaPipeline.swift
//  Wist
//
//  UUP download → convert.sh ISO → USB write (sequential or parallel via USBWriterViewModel).
//

import Combine
import Foundation

private enum E2EUSBWriteError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .failed(let s): return s
        }
    }
}

/// Single end-to-end flow: cache UUP, build ISO, write to one or more removable drives.
@MainActor
final class EndToEndMediaPipeline: ObservableObject {

    enum USBWriteJobStatus: Equatable, Sendable {
        case queued
        case writing
        case done
        case failed(String)
    }

    enum Phase: Equatable {
        case idle
        case downloadingUUP
        case convertingToISO
        case writingUSB(current: Int, total: Int)
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Short line for UI (step name or progress).
    @Published private(set) var statusLine: String = ""
    /// Per-drive status for the current write stage (key: whole disk id, e.g. `disk7`).
    @Published private(set) var usbWriteStatuses: [String: USBWriteJobStatus] = [:]
    /// Full diagnostic log captured for the last failure, suitable for copying.
    @Published private(set) var lastFailureLog: String?

    /// Currently running pipeline task. `cancel()` is enough to unwind everything via
    /// `Task.checkCancellation()` in the long-running stages.
    private var runningTask: Task<Void, Never>?

    /// Single sleep-prevention assertion held for the whole pipeline duration.
    private let powerAssertion = PowerAssertion()

    var isActive: Bool {
        switch phase {
        case .idle, .completed, .failed:
            return false
        case .downloadingUUP, .convertingToISO, .writingUSB:
            return true
        }
    }

    /// Whether the user can hit "Stop" right now. Same as `isActive` but kept
    /// as a separate flag so the UI can disable the button after click while
    /// the cancellation propagates.
    var canCancel: Bool { runningTask != nil }

    func reset() {
        phase = .idle
        statusLine = ""
        usbWriteStatuses = [:]
        lastFailureLog = nil
    }

    /// Asks the running pipeline task to stop. The actual unwind happens in the
    /// async stages via `Task.checkCancellation()` and `Process.terminate()`.
    func requestCancel() {
        runningTask?.cancel()
    }

    /// Full chain using the current selection in `download` and the given drives. ISO comes from `convertUUPFolderToISO` → `lastProducedISOPath`.
    func runFullPipeline(
        download: DownloadISOViewModel,
        usb: USBWriterViewModel,
        drives: [RemovableDriveInfo],
        maxConcurrentUSBWrites: Int = 3
    ) async {
        await runTracked { [weak self] in
            await self?.fullPipelineBody(
                download: download,
                usb: usb,
                drives: drives,
                maxConcurrentUSBWrites: maxConcurrentUSBWrites
            )
        }
    }

    private func fullPipelineBody(
        download: DownloadISOViewModel,
        usb: USBWriterViewModel,
        drives: [RemovableDriveInfo],
        maxConcurrentUSBWrites: Int
    ) async {
        reset()
        guard !drives.isEmpty else {
            phase = .failed(String(localized: "Select at least one USB drive."))
            return
        }
        guard let build = download.selectedBuild else {
            phase = .failed(String(localized: "Select a Windows build."))
            return
        }
        guard download.details != nil, download.editions != nil else {
            phase = .failed(String(localized: "Load languages and editions for the selected build first."))
            return
        }
        guard !download.selectedLanguageCode.isEmpty else {
            phase = .failed(String(localized: "Select a language."))
            return
        }
        if let list = download.editions?.editionList, !list.isEmpty, download.selectedEditionToken.isEmpty {
            phase = .failed(String(localized: "Select a Windows edition."))
            return
        }

        let uuid = build.uuid
        let uupDir = WistCache.cachesRootDirectory
            .appendingPathComponent("UUP/\(uuid)", isDirectory: true)

        phase = .downloadingUUP
        statusLine = String(localized: "Downloading UUP…")
        await download.downloadSelectedPackageToCache()
        if Task.isCancelled {
            phase = .failed(String(localized: "Cancelled."))
            return
        }
        if let err = download.lastError, !err.isEmpty {
            lastFailureLog = buildFailureLog(download: download, usb: usb, extra: err)
            phase = .failed(err)
            return
        }

        guard FileManager.default.fileExists(atPath: uupDir.path) else {
            phase = .failed(String(format: String(localized: "UUP folder missing after download: %@"), uupDir.path))
            return
        }

        phase = .convertingToISO
        statusLine = String(localized: "Building ISO…")
        await download.convertUUPFolderToISO(uupDirectory: uupDir)
        if Task.isCancelled {
            phase = .failed(String(localized: "Cancelled."))
            return
        }
        if let err = download.convertLastError, !err.isEmpty {
            lastFailureLog = buildFailureLog(download: download, usb: usb, extra: err)
            phase = .failed(err)
            return
        }
        guard let isoPath = download.lastProducedISOPath else {
            phase = .failed(String(localized: "Conversion did not produce an ISO path."))
            return
        }
        let isoURL = URL(fileURLWithPath: isoPath)

        let metadata = WistUSBMetadata(
            buildUuid: build.uuid,
            buildNumber: build.build,
            arch: build.arch,
            language: download.selectedLanguageCode,
            editionToken: download.selectedEditionToken,
            buildTitle: build.title,
            sourceIsoPath: isoPath
        )

        phase = .writingUSB(current: 0, total: drives.count)
        statusLine = String(localized: "Writing to USB…")

        do {
            try await runUSBWritesWithConcurrencyLimit(
                isoURL: isoURL,
                drives: drives,
                metadata: metadata,
                usb: usb,
                maxConcurrent: maxConcurrentUSBWrites
            )
        } catch is CancellationError {
            phase = .failed(String(localized: "Cancelled."))
            return
        } catch {
            let msg = error.localizedDescription
            lastFailureLog = buildFailureLog(download: download, usb: usb, extra: msg)
            phase = .failed(msg)
            WistNotificationCenter.notifyWriteFailed(message: msg)
            return
        }

        phase = .completed
        statusLine = String(localized: "Done: image written to the selected drives.")
        WistNotificationCenter.notifyWriteSucceeded(driveCount: drives.count)
        Task { await FluffyFinderIconAutomation.reapplyAfterUSBWriteBestEffort() }
    }

    /// Re-run pipeline for «update stick» when user already has ISO path or will convert again — here we only write using existing ISO path.
    func writeExistingISOToDrives(
        isoURL: URL,
        download: DownloadISOViewModel,
        usb: USBWriterViewModel,
        drives: [RemovableDriveInfo],
        maxConcurrentUSBWrites: Int = 3
    ) async {
        await runTracked { [weak self] in
            await self?.writeExistingISOBody(
                isoURL: isoURL,
                download: download,
                usb: usb,
                drives: drives,
                maxConcurrentUSBWrites: maxConcurrentUSBWrites
            )
        }
    }

    private func writeExistingISOBody(
        isoURL: URL,
        download: DownloadISOViewModel,
        usb: USBWriterViewModel,
        drives: [RemovableDriveInfo],
        maxConcurrentUSBWrites: Int
    ) async {
        reset()
        guard !drives.isEmpty else {
            phase = .failed(String(localized: "Select at least one USB drive."))
            return
        }
        let metadata: WistUSBMetadata? = download.selectedBuild.map { build in
            WistUSBMetadata(
                buildUuid: build.uuid,
                buildNumber: build.build,
                arch: build.arch,
                language: download.selectedLanguageCode,
                editionToken: download.selectedEditionToken,
                buildTitle: build.title,
                sourceIsoPath: isoURL.path
            )
        }

        phase = .writingUSB(current: 0, total: drives.count)
        statusLine = String(localized: "Writing to USB…")

        do {
            try await runUSBWritesWithConcurrencyLimit(
                isoURL: isoURL,
                drives: drives,
                metadata: metadata,
                usb: usb,
                maxConcurrent: maxConcurrentUSBWrites
            )
        } catch is CancellationError {
            phase = .failed(String(localized: "Cancelled."))
            return
        } catch {
            let msg = error.localizedDescription
            lastFailureLog = buildFailureLog(download: download, usb: usb, extra: msg)
            phase = .failed(msg)
            WistNotificationCenter.notifyWriteFailed(message: msg)
            return
        }

        phase = .completed
        statusLine = String(localized: "Done.")
        WistNotificationCenter.notifyWriteSucceeded(driveCount: drives.count)
        Task { await FluffyFinderIconAutomation.reapplyAfterUSBWriteBestEffort() }
    }

    /// Wraps a pipeline body so we hold a single `runningTask` (for cancellation),
    /// a single `PowerAssertion` (to keep the system awake), and a Dock badge for
    /// the whole run.
    private func runTracked(_ body: @MainActor @escaping () async -> Void) async {
        if let existing = runningTask {
            existing.cancel()
            _ = await existing.value
        }
        let task = Task<Void, Never> { @MainActor in
            self.powerAssertion.acquire(reason: "Fluffy Flash: writing USB")
            WistNotificationCenter.setDockBadge(activeWrites: 1)
            defer {
                self.powerAssertion.release()
                WistNotificationCenter.setDockBadge(activeWrites: 0)
            }
            await body()
        }
        runningTask = task
        await task.value
        runningTask = nil
    }

    /// Parallel writes with a concurrency cap. When more than one drive is in
    /// flight we mount the source ISO once and share the mount across all
    /// writers (significantly faster on slow ISO disks because we avoid N
    /// independent `hdiutil attach` calls).
    private func runUSBWritesWithConcurrencyLimit(
        isoURL: URL,
        drives: [RemovableDriveInfo],
        metadata: WistUSBMetadata?,
        usb: USBWriterViewModel,
        maxConcurrent: Int
    ) async throws {
        let total = drives.count
        let limit = max(1, maxConcurrent)
        let work = Array(drives.enumerated())

        var initial: [String: USBWriteJobStatus] = [:]
        for d in drives { initial[d.deviceIdentifier] = .queued }
        usbWriteStatuses = initial

        // Pre-mount once when there is more than one drive to flash.
        var sharedMount: URL?
        if drives.count > 1 {
            do {
                sharedMount = try await HdiutilAttach.attachISOReadOnly(at: isoURL) { [weak self] line in
                    Task { @MainActor in self?.statusLine = line }
                }
                statusLine = String(format: String(localized: "Shared ISO mount: %@"), sharedMount?.path ?? "")
            } catch {
                // Fall back to per-task attach if the shared mount fails.
                sharedMount = nil
            }
        }
        defer {
            if let mount = sharedMount {
                Task.detached {
                    try? await HdiutilAttach.detach(mountPoint: mount) { _ in }
                }
            }
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var iterator = work.makeIterator()

                for _ in 0 ..< min(limit, work.count) {
                    guard let (idx, drive) = iterator.next() else { break }
                    group.addTask { @MainActor in
                        self.phase = .writingUSB(current: idx + 1, total: total)
                        self.statusLine = String(
                            format: String(localized: "Write %lld of %lld: %@"),
                            Int64(idx + 1), Int64(total), drive.mediaName
                        )
                        self.usbWriteStatuses[drive.deviceIdentifier] = .writing
                        if let err = await usb.writeWindowsInstaller(
                            isoURL: isoURL,
                            drive: drive,
                            metadata: metadata,
                            preMountedISO: sharedMount
                        ) {
                            self.usbWriteStatuses[drive.deviceIdentifier] = .failed(err)
                            throw E2EUSBWriteError.failed(err)
                        }
                        self.usbWriteStatuses[drive.deviceIdentifier] = .done
                    }
                }

                while let (idx, drive) = iterator.next() {
                    _ = try await group.next()
                    group.addTask { @MainActor in
                        self.phase = .writingUSB(current: idx + 1, total: total)
                        self.statusLine = String(
                            format: String(localized: "Write %lld of %lld: %@"),
                            Int64(idx + 1), Int64(total), drive.mediaName
                        )
                        self.usbWriteStatuses[drive.deviceIdentifier] = .writing
                        if let err = await usb.writeWindowsInstaller(
                            isoURL: isoURL,
                            drive: drive,
                            metadata: metadata,
                            preMountedISO: sharedMount
                        ) {
                            self.usbWriteStatuses[drive.deviceIdentifier] = .failed(err)
                            throw E2EUSBWriteError.failed(err)
                        }
                        self.usbWriteStatuses[drive.deviceIdentifier] = .done
                    }
                }

                for try await _ in group {}
            }
        }
    }

    private func buildFailureLog(download: DownloadISOViewModel, usb: USBWriterViewModel, extra: String) -> String {
        var chunks: [String] = []
        chunks.append("— Fluffy Flash —")
        if !statusLine.isEmpty {
            chunks.append("statusLine: \(statusLine)")
        }
        if let e = download.lastError, !e.isEmpty {
            chunks.append("\n--- download.lastError ---\n\(e)")
        }
        if let e = download.convertLastError, !e.isEmpty {
            chunks.append("\n--- download.convertLastError ---\n\(e)")
        }
        chunks.append("\n--- pipeline.error ---\n\(extra)")
        chunks.append("\n--- usbWriter.log ---\n\(usb.fullLogText)")
        return chunks.joined(separator: "\n")
    }
}
