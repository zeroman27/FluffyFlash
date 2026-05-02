//
//  FluffyUSBDoctorView.swift
//  Fluffy Flash
//
//  Library tab: "USB Doctor". Lists Fluffy-flashed drives (Windows + macOS),
//  re-verifies Windows split chunks or macOS installer + sidecar, speed tests,
//  and offers macOS maintenance actions.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class FluffyUSBDoctorViewModel: ObservableObject {

    enum Status: Equatable {
        case idle
        case running(String)
        case healthy(String)
        case slow(String)
        case corrupted(String)
        case missing(String)
    }

    @Published var statusByDevice: [String: Status] = [:]

    func runHealthCheck(for drive: RemovableDriveInfo) {
        Task { await runHealthCheckBody(for: drive) }
    }

    private func runHealthCheckBody(for drive: RemovableDriveInfo) async {
        guard let mount = drive.mountPoint else {
            statusByDevice[drive.deviceIdentifier] = .missing(String(localized: "Drive not mounted."))
            return
        }

        if drive.fluffyMacOSSidecarMeta != nil {
            await runMacOSHealthCheck(drive: drive, mount: mount)
            return
        }

        if drive.wistSidecarMeta != nil {
            await runWindowsHealthCheck(drive: drive, mount: mount)
            return
        }

        statusByDevice[drive.deviceIdentifier] = .missing(String(localized: "No Fluffy metadata."))
    }

    private func runWindowsHealthCheck(drive: RemovableDriveInfo, mount: URL) async {
        statusByDevice[drive.deviceIdentifier] = .running(String(localized: "Verifying chunks…"))

        guard let meta = WistUSBMetadata.read(from: mount) else {
            statusByDevice[drive.deviceIdentifier] = .missing(String(localized: "No Fluffy metadata."))
            return
        }
        guard let chunks = meta.splitChunks, !chunks.isEmpty else {
            statusByDevice[drive.deviceIdentifier] = .healthy(String(localized: "No verification data, looks OK."))
            return
        }

        let sources = mount.appendingPathComponent("sources", isDirectory: true)
        for chunk in chunks {
            let url = sources.appendingPathComponent(chunk.fileName)
            statusByDevice[drive.deviceIdentifier] = .running(
                String(format: String(localized: "Hashing %@…"), chunk.fileName)
            )
            guard let actual = await SHA256Hasher.hashFileBestEffort(at: url) else {
                statusByDevice[drive.deviceIdentifier] = .corrupted(
                    String(format: String(localized: "Cannot read %@."), chunk.fileName)
                )
                return
            }
            if actual != chunk.sha256 {
                statusByDevice[drive.deviceIdentifier] = .corrupted(
                    String(format: String(localized: "Hash mismatch on %@."), chunk.fileName)
                )
                return
            }
        }
        statusByDevice[drive.deviceIdentifier] = .healthy(
            String(format: String(localized: "All %lld chunks verified."), Int64(chunks.count))
        )
    }

    private func runMacOSHealthCheck(drive: RemovableDriveInfo, mount: URL) async {
        statusByDevice[drive.deviceIdentifier] = .running(String(localized: "Checking installer…"))

        guard let appURL = FluffyMacOSUSBMetadata.installAssistantAppBundle(atVolumeRoot: mount) else {
            statusByDevice[drive.deviceIdentifier] = .corrupted(
                String(localized: "No installer app with createinstallmedia on this volume.")
            )
            return
        }

        let fresh: FluffyMacOSUSBMetadata
        do {
            fresh = try FluffyMacOSUSBMetadata.make(installerAppURL: appURL)
        } catch {
            statusByDevice[drive.deviceIdentifier] = .corrupted(
                String(localized: "Could not read installer Info.plist.")
            )
            return
        }

        guard let onDisk = FluffyMacOSUSBMetadata.read(from: mount) else {
            statusByDevice[drive.deviceIdentifier] = .corrupted(
                String(localized: "Sidecar JSON missing on volume.")
            )
            return
        }

        if Self.macOSInstallerFieldsMatch(onDisk, fresh) {
            statusByDevice[drive.deviceIdentifier] = .healthy(
                String(localized: "Installer and sidecar metadata match.")
            )
        } else {
            statusByDevice[drive.deviceIdentifier] = .corrupted(
                String(localized: "Sidecar is out of date vs installer on disk — use “Re-write metadata”.")
            )
        }
    }

    /// Compares fields that describe the Apple installer; ignores `writtenAt` / Fluffy app version.
    private static func macOSInstallerFieldsMatch(_ a: FluffyMacOSUSBMetadata, _ b: FluffyMacOSUSBMetadata) -> Bool {
        a.installerDisplayName == b.installerDisplayName
            && a.installerShortVersion == b.installerShortVersion
            && a.installerBundleVersion == b.installerBundleVersion
            && a.installerMarketingVersion == b.installerMarketingVersion
            && a.installerAppleBuildFromName == b.installerAppleBuildFromName
            && a.installerDTPlatformVersion == b.installerDTPlatformVersion
    }

    func runSpeedTest(for drive: RemovableDriveInfo) {
        Task { await runSpeedTestBody(for: drive) }
    }

    private func runSpeedTestBody(for drive: RemovableDriveInfo) async {
        statusByDevice[drive.deviceIdentifier] = .running(String(localized: "Read speed test…"))
        guard let mount = drive.mountPoint else {
            statusByDevice[drive.deviceIdentifier] = .missing(String(localized: "Drive not mounted."))
            return
        }

        let target: URL?
        if drive.fluffyMacOSSidecarMeta != nil {
            target = Self.macOSSpeedProbeURL(volumeRoot: mount)
        } else {
            let sources = mount.appendingPathComponent("sources", isDirectory: true)
            let probe: URL? = (try? FileManager.default.contentsOfDirectory(
                at: sources,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ).first { $0.lastPathComponent.lowercased().hasPrefix("install.swm") })
            target = probe ?? mount.appendingPathComponent(WistUSBMetadata.fileName)
        }

        guard let target else {
            statusByDevice[drive.deviceIdentifier] = .corrupted(String(localized: "Could not find a large file to read."))
            return
        }

        let mbps = await measureReadMBps(from: target, bytesToRead: 100 * 1024 * 1024)
        if mbps == 0 {
            statusByDevice[drive.deviceIdentifier] = .corrupted(String(localized: "Could not read from drive."))
            return
        }
        let mbpsString = String(format: "%.1f MB/s", mbps)
        if mbps < 8 {
            statusByDevice[drive.deviceIdentifier] = .slow(mbpsString)
        } else {
            statusByDevice[drive.deviceIdentifier] = .healthy(mbpsString)
        }
    }

    /// Best-effort large file inside the installer for sequential read throughput.
    private static func macOSSpeedProbeURL(volumeRoot: URL) -> URL? {
        guard let app = FluffyMacOSUSBMetadata.installAssistantAppBundle(atVolumeRoot: volumeRoot) else { return nil }
        let shared = app.appendingPathComponent("Contents/SharedSupport", isDirectory: true)
        let candidates = [
            shared.appendingPathComponent("SharedSupport.dmg"),
            shared.appendingPathComponent("BaseSystem.dmg"),
            shared.appendingPathComponent("InstallESD.dmg"),
        ]
        let fm = FileManager.default
        for u in candidates where fm.fileExists(atPath: u.path) {
            return u
        }
        return app.appendingPathComponent("Contents/Info.plist")
    }

    /// Streams up to `bytesToRead` from `url` and returns the throughput in MB/s.
    /// Best-effort: returns 0 on any error.
    private nonisolated func measureReadMBps(from url: URL, bytesToRead: Int) async -> Double {
        await Task.detached(priority: .utility) { () -> Double in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
            defer { try? handle.close() }
            let block = 1 << 20
            var read = 0
            let start = Date()
            while read < bytesToRead {
                let want = min(block, bytesToRead - read)
                guard let chunk = try? handle.read(upToCount: want), !chunk.isEmpty else { break }
                read += chunk.count
            }
            let secs = Date().timeIntervalSince(start)
            guard secs > 0, read > 0 else { return 0 }
            return Double(read) / secs / 1_000_000
        }.value
    }

    func rewriteMacOSMetadata(drive: RemovableDriveInfo) {
        Task { await rewriteMacOSMetadataBody(drive: drive) }
    }

    private func rewriteMacOSMetadataBody(drive: RemovableDriveInfo) async {
        statusByDevice[drive.deviceIdentifier] = .running(String(localized: "Writing metadata…"))
        guard let mount = drive.mountPoint else {
            statusByDevice[drive.deviceIdentifier] = .missing(String(localized: "Drive not mounted."))
            return
        }
        guard let appURL = FluffyMacOSUSBMetadata.installAssistantAppBundle(atVolumeRoot: mount) else {
            statusByDevice[drive.deviceIdentifier] = .corrupted(String(localized: "No installer app found."))
            return
        }
        do {
            let meta = try FluffyMacOSUSBMetadata.makeAfterWrite(
                volumeRoot: mount,
                fallbackInstallerAppURL: appURL
            )
            try meta.write(to: mount)
            statusByDevice[drive.deviceIdentifier] = .healthy(String(localized: "Metadata updated."))
        } catch {
            statusByDevice[drive.deviceIdentifier] = .corrupted(error.localizedDescription)
        }
    }

    func ejectDrive(deviceIdentifier: String, diskManager: DiskManager) {
        Task {
            let dev = deviceIdentifier.hasPrefix("/dev/") ? deviceIdentifier : "/dev/\(deviceIdentifier)"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            p.arguments = ["eject", dev]
            try? p.run()
            p.waitUntilExit()
            await diskManager.refresh()
        }
    }
}

struct FluffyUSBDoctorView: View {
    @ObservedObject var diskManager: DiskManager
    @StateObject private var model = FluffyUSBDoctorViewModel()

    @AppStorage(FluffyUSBIconStyle.appStorageKey) private var usbIconStyleRaw: String = FluffyUSBIconStyle.defaultStyle.rawValue

    private var fluffyDrives: [RemovableDriveInfo] {
        diskManager.drives.filter { $0.hasFluffySidecar }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WistTheme.gutter) {
            MistSectionCard(title: String(localized: "USB Doctor"), systemImage: "cross.case.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Re-verify drives written by Fluffy Flash: Windows (install.swm chunk hashes) or macOS (installer + sidecar JSON). Run a quick read speed test."))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if fluffyDrives.isEmpty {
                MistSectionCard(title: String(localized: "No Fluffy drives connected"), systemImage: "externaldrive.badge.questionmark") {
                    Text(String(localized: "Plug in a USB you flashed with Fluffy Flash (Windows or macOS) and it will appear here."))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(fluffyDrives) { drive in
                    driveCard(drive)
                }
            }
        }
    }

    @ViewBuilder
    private func driveCard(_ drive: RemovableDriveInfo) -> some View {
        let status = model.statusByDevice[drive.deviceIdentifier] ?? .idle
        let title: String = {
            if drive.fluffyMacOSSidecarMeta != nil {
                return drive.fluffyMacOSSidecarMeta?.summarySubtitle ?? drive.mediaName
            }
            return drive.mediaName
        }()

        MistSectionCard(title: title, systemImage: drive.fluffyMacOSSidecarMeta != nil ? "apple.logo" : "externaldrive.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if drive.wistSidecarMeta != nil {
                    Text(String(localized: "Windows installer USB"))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                } else if drive.fluffyMacOSSidecarMeta != nil {
                    Text(String(localized: "macOS installer USB"))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    statusBadge(for: status)
                    Spacer()
                    Button {
                        model.runHealthCheck(for: drive)
                    } label: {
                        Label(String(localized: "Verify"), systemImage: "checkmark.shield")
                    }
                    Button {
                        model.runSpeedTest(for: drive)
                    } label: {
                        Label(String(localized: "Speed test"), systemImage: "speedometer")
                    }
                }

                if drive.fluffyMacOSSidecarMeta != nil {
                    Divider().opacity(0.35)
                    HStack(spacing: 8) {
                        Button {
                            applyMacOSFinderIcon(drive: drive)
                        } label: {
                            Label(String(localized: "Re-apply Finder icon"), systemImage: "paintbrush.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            model.rewriteMacOSMetadata(drive: drive)
                        } label: {
                            Label(String(localized: "Re-write metadata"), systemImage: "doc.badge.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if let m = drive.mountPoint {
                                NSWorkspace.shared.activateFileViewerSelecting([m])
                            }
                        } label: {
                            Label(String(localized: "Reveal"), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .disabled(drive.mountPoint == nil)

                        Button {
                            model.ejectDrive(deviceIdentifier: drive.deviceIdentifier, diskManager: diskManager)
                        } label: {
                            Label(String(localized: "Eject"), systemImage: "eject")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func applyMacOSFinderIcon(drive: RemovableDriveInfo) {
        guard drive.hasFluffySidecar, let mount = drive.mountPoint else { return }
        let style = FluffyUSBIconStyle.resolve(rawValue: usbIconStyleRaw)
        FluffyDriveIconOverrides.setOverride(deviceIdentifier: drive.deviceIdentifier, styleRawValue: usbIconStyleRaw)
        try? FluffyVolumeIconManager.setVolumeIcon(style: style, mountPoint: mount)
    }

    @ViewBuilder
    private func statusBadge(for status: FluffyUSBDoctorViewModel.Status) -> some View {
        switch status {
        case .idle:
            Label(String(localized: "Idle"), systemImage: "circle")
                .foregroundStyle(.secondary)
        case .running(let m):
            Label(m, systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .healthy(let m):
            Label(m, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
        case .slow(let m):
            Label(m, systemImage: "tortoise.fill")
                .foregroundStyle(FluffyColor.orange)
        case .corrupted(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .missing(let m):
            Label(m, systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}
