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

    var isActive: Bool {
        switch phase {
        case .idle, .completed, .failed:
            return false
        case .downloadingUUP, .convertingToISO, .writingUSB:
            return true
        }
    }

    func reset() {
        phase = .idle
        statusLine = ""
    }

    /// Full chain using the current selection in `download` and the given drives. ISO comes from `convertUUPFolderToISO` → `lastProducedISOPath`.
    func runFullPipeline(
        download: DownloadISOViewModel,
        usb: USBWriterViewModel,
        drives: [RemovableDriveInfo],
        maxConcurrentUSBWrites: Int = 3
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
        let uupDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wist/UUP/\(uuid)", isDirectory: true)

        phase = .downloadingUUP
        statusLine = String(localized: "Downloading UUP…")
        await download.downloadSelectedPackageToCache()
        if let err = download.lastError, !err.isEmpty {
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
        if let err = download.convertLastError, !err.isEmpty {
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
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        phase = .completed
        statusLine = String(localized: "Done: image written to the selected drives.")
    }

    /// Re-run pipeline for «update stick» when user already has ISO path or will convert again — here we only write using existing ISO path.
    func writeExistingISOToDrives(
        isoURL: URL,
        download: DownloadISOViewModel,
        usb: USBWriterViewModel,
        drives: [RemovableDriveInfo],
        maxConcurrentUSBWrites: Int = 3
    ) async {
        reset()
        guard !drives.isEmpty else {
            phase = .failed(String(localized: "Select at least one USB drive."))
            return
        }
        guard let build = download.selectedBuild else {
            phase = .failed(String(localized: "Select a Windows build (for on-drive metadata)."))
            return
        }

        let metadata = WistUSBMetadata(
            buildUuid: build.uuid,
            buildNumber: build.build,
            arch: build.arch,
            language: download.selectedLanguageCode,
            editionToken: download.selectedEditionToken,
            buildTitle: build.title,
            sourceIsoPath: isoURL.path
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
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        phase = .completed
        statusLine = String(localized: "Done.")
    }

    /// Parallel writes with a concurrency cap; each job resolves its own mount path after `eraseDisk`.
    private func runUSBWritesWithConcurrencyLimit(
        isoURL: URL,
        drives: [RemovableDriveInfo],
        metadata: WistUSBMetadata,
        usb: USBWriterViewModel,
        maxConcurrent: Int
    ) async throws {
        let total = drives.count
        let limit = max(1, maxConcurrent)
        let work = Array(drives.enumerated())

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
                    if let err = await usb.writeWindowsInstaller(isoURL: isoURL, drive: drive, metadata: metadata) {
                        throw E2EUSBWriteError.failed(err)
                    }
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
                    if let err = await usb.writeWindowsInstaller(isoURL: isoURL, drive: drive, metadata: metadata) {
                        throw E2EUSBWriteError.failed(err)
                    }
                }
            }

            for try await _ in group {}
        }
    }
}
