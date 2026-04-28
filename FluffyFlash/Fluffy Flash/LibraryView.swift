//
//  LibraryView.swift
//  Fluffy Flash
//
//  Cached artefacts: UUP downloads, produced ISOs, history log, detected
//  Fluffy drives (with upgrade badges).
//

import AppKit
import SwiftUI

enum LibraryTab: String, CaseIterable, Identifiable {
    case downloads
    case isos
    case macos
    case history
    case drives

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .downloads: return "Downloads"
        case .isos: return "ISOs"
        case .macos: return "macOS"
        case .history: return "History"
        case .drives: return "Fluffy drives"
        }
    }
}

struct LibraryView: View {
    @ObservedObject var diskManager: DiskManager
    @ObservedObject var usbWriter: USBWriterViewModel
    @ObservedObject var downloadModel: DownloadISOViewModel
    @ObservedObject var e2e: EndToEndMediaPipeline
    @ObservedObject var upgradeDetector: WistUSBUpgradeDetector
    @ObservedObject var history: WriteHistoryStore

    @State private var tab: LibraryTab = .downloads
    @State private var cacheFolders: [UUPCacheFolder] = []
    @State private var macosArtefacts: [MacOSCache.Artefact] = []
    @State private var isPresentingHistoryLog = false
    @State private var historyLogTitle: String = ""
    @State private var historyLogText: String = ""

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = .useAll
        f.countStyle = .file
        return f
    }()

    var body: some View {
        MistDetailCanvas {
            VStack(alignment: .leading, spacing: 0) {
                MistPageHeader(
                    eyebrow: String(localized: "Library"),
                    title: String(localized: "Your artefacts"),
                    subtitle: String(localized: "Cached UUP downloads, built ISOs, recent write history, and detected Fluffy drives."),
                    symbolName: "books.vertical",
                    assetName: "FluffyIconLibrary"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                Picker(String(localized: "Library section"), selection: $tab) {
                    ForEach(LibraryTab.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, WistTheme.pagePadding)
                .padding(.top, WistTheme.gutter)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        switch tab {
                        case .downloads: downloadsSection
                        case .isos: isosSection
                        case .macos: macosSection
                        case .history: historySection
                        case .drives: drivesSection
                        }
                    }
                    .padding(WistTheme.pagePadding)
                }
            }
        }
        .sheet(isPresented: $isPresentingHistoryLog) {
            FluffyHistoryLogSheet(
                title: historyLogTitle,
                text: historyLogText
            )
        }
        .task {
            reloadCache()
            reloadMacOSCache()
        }
        .onChange(of: tab) {
            if tab == .downloads || tab == .isos { reloadCache() }
            if tab == .macos { reloadMacOSCache() }
        }
    }

    private func reloadCache() {
        cacheFolders = WistCache.listUUPFolders()
    }

    private func reloadMacOSCache() {
        // Ensure the folder exists so "Reveal" always works.
        try? FileManager.default.createDirectory(at: MacOSCache.rootDirectory, withIntermediateDirectories: true)
        macosArtefacts = MacOSCache.listArtefacts()
    }

    // MARK: - Downloads (UUP cache)

    private var downloadsSection: some View {
        MistSectionCard(title: String(localized: "UUP cache"), systemImage: "tray.full") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(format: String(localized: "%lld cache folders"), Int64(cacheFolders.count)))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        reloadCache()
                    } label: {
                        Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([WistCache.uupRootDirectory])
                    } label: {
                        Label(String(localized: "Reveal folder"), systemImage: "folder")
                    }
                }
                if cacheFolders.isEmpty {
                    MistEmptyState(
                        systemImage: "tray",
                        title: String(localized: "No downloads yet"),
                        message: String(localized: "Downloaded UUP folders will appear here.")
                    )
                } else {
                    ForEach(cacheFolders) { folder in
                        cacheFolderRow(folder: folder)
                    }
                }
            }
        }
    }

    private func cacheFolderRow(folder: UUPCacheFolder) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.cachedMetadata?.title ?? folder.name)
                    .font(WistFont.headline(13))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let m = folder.cachedMetadata {
                        Text("\(m.buildNumber) · \(m.arch) · \(m.languageCode)")
                            .font(WistFont.caption(10))
                            .foregroundStyle(.secondary)
                    }
                    Text(Self.byteFormatter.string(fromByteCount: folder.totalBytes))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
                Text(folder.url.path)
                    .font(WistFont.caption(9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                } label: {
                    Image(systemName: "folder")
                }
                .help(String(localized: "Reveal in Finder"))
                .buttonStyle(.borderless)
                Button {
                    Task { await downloadModel.convertUUPFolderToISO(uupDirectory: folder.url) }
                } label: {
                    Image(systemName: "opticaldisc")
                }
                .help(String(localized: "Build ISO from this UUP cache"))
                .buttonStyle(.borderless)
                .disabled(downloadModel.isConvertingUUP || e2e.isActive)
                Button(role: .destructive) {
                    try? FileManager.default.removeItem(at: folder.url)
                    reloadCache()
                } label: {
                    Image(systemName: "trash")
                }
                .help(String(localized: "Delete cache folder"))
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        }
    }

    // MARK: - ISOs

    private var isosSection: some View {
        MistSectionCard(title: String(localized: "Built ISOs"), systemImage: "opticaldisc") {
            VStack(alignment: .leading, spacing: 12) {
                let isos = scanCachedISOs()
                if isos.isEmpty {
                    MistEmptyState(
                        systemImage: "opticaldisc",
                        title: String(localized: "No ISOs in cache"),
                        message: String(localized: "Build an ISO from a UUP cache folder or drop one into the cache manually.")
                    )
                } else {
                    ForEach(isos, id: \.self) { url in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent)
                                    .font(WistFont.headline(13))
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(WistFont.caption(9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                    Text(Self.byteFormatter.string(fromByteCount: Int64(size)))
                                        .font(WistFont.caption(10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: { Image(systemName: "folder") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Reveal in Finder"))
                            Button(role: .destructive) {
                                try? FileManager.default.removeItem(at: url)
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Delete ISO"))
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private func scanCachedISOs() -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        guard let top = try? fm.contentsOfDirectory(at: WistCache.uupRootDirectory, includingPropertiesForKeys: nil) else { return [] }
        for dir in top {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for child in children where child.pathExtension.lowercased() == "iso" {
                    out.append(child)
                }
            }
        }
        return out.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: - macOS

    private var macosSection: some View {
        MistSectionCard(title: String(localized: "macOS artefacts"), systemImage: "apple.logo") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(format: String(localized: "%lld items"), Int64(macosArtefacts.count)))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        reloadMacOSCache()
                    } label: {
                        Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([MacOSCache.rootDirectory])
                    } label: {
                        Label(String(localized: "Reveal folder"), systemImage: "folder")
                    }
                }

                if macosArtefacts.isEmpty {
                    MistEmptyState(
                        systemImage: "apple.logo",
                        title: String(localized: "No macOS artefacts yet"),
                        message: String(localized: "Downloads and exports from the macOS mode will appear here.")
                    )
                } else {
                    ForEach(macosArtefacts) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.url.lastPathComponent)
                                    .font(WistFont.headline(13))
                                    .lineLimit(1)
                                if let date = item.modifiedAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(WistFont.caption(10))
                                        .foregroundStyle(.secondary)
                                }
                                if let size = item.fileSizeBytes {
                                    Text(Self.byteFormatter.string(fromByteCount: size))
                                        .font(WistFont.caption(10))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(item.url.deletingLastPathComponent().path)
                                    .font(WistFont.caption(9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: { Image(systemName: "folder") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Reveal in Finder"))
                            Button(role: .destructive) {
                                try? FileManager.default.removeItem(at: item.url)
                                reloadMacOSCache()
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Delete"))
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        MistSectionCard(title: String(localized: "Recent writes"), systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(format: String(localized: "%lld entries"), Int64(history.entries.count)))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        history.clear()
                    } label: {
                        Label(String(localized: "Clear history"), systemImage: "trash")
                    }
                    .disabled(history.entries.isEmpty)
                }
                if history.entries.isEmpty {
                    MistEmptyState(
                        systemImage: "clock",
                        title: String(localized: "Nothing yet"),
                        message: String(localized: "Successful or failed USB writes will be logged here.")
                    )
                } else {
                    ForEach(history.entries) { entry in
                        historyRow(entry: entry)
                    }
                }
            }
        }
    }

    private func historyRow(entry: WriteHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(entry.succeeded ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.buildTitle ?? entry.buildNumber)
                    .font(WistFont.headline(13))
                    .lineLimit(2)
                Text("\(entry.buildNumber) · \(entry.arch) · \(entry.language) · \(entry.driveMediaName)")
                    .font(WistFont.caption(10))
                    .foregroundStyle(.secondary)
                if let date = entry.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(WistFont.caption(9))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(entry.dateISO8601)
                        .font(WistFont.caption(9))
                        .foregroundStyle(.tertiary)
                }
                if let err = entry.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                if let log = history.loadFullLogText(for: entry), !log.isEmpty {
                    Button {
                        historyLogTitle = String(localized: "Write log")
                        historyLogText = log
                        isPresentingHistoryLog = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .help(String(localized: "View log"))
                    .buttonStyle(.borderless)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help(String(localized: "Copy log"))
                    .buttonStyle(.borderless)

                    if let url = history.logFileURL(for: entry), FileManager.default.fileExists(atPath: url.path) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help(String(localized: "Reveal in Finder"))
                        .buttonStyle(.borderless)
                    }
                }

                if let iso = entry.isoPath, FileManager.default.fileExists(atPath: iso) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: iso)])
                    } label: { Image(systemName: "opticaldisc") }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Reveal ISO"))
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        }
    }

    // MARK: - Fluffy drives

    private var drivesSection: some View {
        MistSectionCard(title: String(localized: "Detected Fluffy drives"), systemImage: "externaldrive.badge.checkmark") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "Drives previously written by Fluffy Flash. Badges reflect the newest known stable build for each tuple (arch · language · edition)."))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        upgradeDetector.forceCheck()
                    } label: {
                        Label(String(localized: "Check now"), systemImage: "arrow.clockwise")
                    }
                    .disabled(upgradeDetector.isChecking)
                }

                let drives = diskManager.drives.filter { $0.wistSidecarMeta != nil }
                if drives.isEmpty {
                    MistEmptyState(
                        systemImage: "externaldrive",
                        title: String(localized: "No Fluffy drives connected"),
                        message: String(localized: "Attach a USB drive previously formatted by this app to see upgrade offers.")
                    )
                } else {
                    ForEach(drives) { drive in
                        drivesRow(drive: drive)
                    }
                }
            }
        }
    }

    private func drivesRow(drive: RemovableDriveInfo) -> some View {
        DrivesLibraryRow(
            drive: drive,
            offer: upgradeDetector.offers.first { $0.drive.deviceIdentifier == drive.deviceIdentifier },
            sizeText: Self.byteFormatter.string(fromByteCount: drive.totalSizeBytes)
        )
    }
}

private struct FluffyHistoryLogSheet: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FluffySheetChrome {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(WistFont.title(16))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Label(String(localized: "Close"), systemImage: "xmark")
                            .font(WistFont.caption(11).weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().opacity(0.35)

                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(16)
                }
                .frame(minHeight: 360)

                Divider().opacity(0.35)

                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label(String(localized: "Copy log"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .fluffyPillow(cornerRadius: 22)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 640)
    }
}

// MARK: - Fluffy drives row (Library)

/// Row variant used inside Library → Fluffy drives. Mirrors the visual style of
/// `FluffyDriveRow` on Home (custom USB artwork, glassy rounded surface) but
/// surfaces upgrade badges instead of a selection indicator.
private struct DrivesLibraryRow: View {
    let drive: RemovableDriveInfo
    let offer: DriveUpgradeOffer?
    let sizeText: String

    @AppStorage(FluffyUSBIconStyle.appStorageKey) private var iconStyleRaw: String = FluffyUSBIconStyle.defaultStyle.rawValue

    private var iconStyle: FluffyUSBIconStyle {
        FluffyUSBIconStyle.resolve(rawValue: iconStyleRaw)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(iconStyle.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .shadow(color: Color.black.opacity(0.35), radius: 5, y: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(drive.mediaName)
                        .font(WistFont.headline(13))
                        .lineLimit(1)
                    Text(String(localized: "Fluffy"))
                        .font(WistFont.caption(9))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(FluffyColor.purpleGlow.opacity(0.28)))
                        .overlay(Capsule().strokeBorder(FluffyColor.purpleGlow.opacity(0.55), lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.95))
                }
                if let meta = drive.wistSidecarMeta {
                    Text("\(meta.buildNumber) · \(meta.arch) · \(meta.language) · \(meta.editionToken)")
                        .font(WistFont.caption(10))
                        .foregroundStyle(.secondary)
                }
                if let offer, offer.isNewer {
                    Label(
                        String(format: String(localized: "Latest stable: %@"), offer.latestBuild.build),
                        systemImage: "arrow.up.circle.fill"
                    )
                    .font(WistFont.caption(10).weight(.medium))
                    .foregroundStyle(FluffyColor.orangeHi)
                } else if offer != nil {
                    Label(String(localized: "Up-to-date"), systemImage: "checkmark.seal.fill")
                        .font(WistFont.caption(10))
                        .foregroundStyle(Color.green)
                }
            }

            Spacer(minLength: 8)
            Text(sizeText)
                .font(WistFont.caption(11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            FluffyColor.surface.opacity(0.9),
                            FluffyColor.elevated.opacity(0.82),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.9)
        }
        .contextMenu {
            Button {
                applyFinderIcon(styleRawValue: iconStyleRaw)
            } label: {
                Text(String(localized: "Apply this icon in Finder"))
            }
            Menu(String(localized: "Choose Finder icon…")) {
                ForEach(FluffyUSBIconStyle.allCases) { style in
                    Button {
                        applyFinderIcon(styleRawValue: style.rawValue)
                    } label: {
                        Text(style.displayName)
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                clearFinderIcon()
            } label: {
                Text(String(localized: "Reset Finder icon"))
            }
        }
    }

    private func applyFinderIcon(styleRawValue: String) {
        guard drive.wistSidecarMeta != nil else { return }
        guard let mount = drive.mountPoint else { return }
        FluffyDriveIconOverrides.setOverride(deviceIdentifier: drive.deviceIdentifier, styleRawValue: styleRawValue)
        let style = FluffyUSBIconStyle.resolve(rawValue: styleRawValue)
        try? FluffyVolumeIconManager.setVolumeIcon(style: style, mountPoint: mount)
    }

    private func clearFinderIcon() {
        guard let mount = drive.mountPoint else { return }
        FluffyDriveIconOverrides.clearOverride(deviceIdentifier: drive.deviceIdentifier)
        try? FluffyVolumeIconManager.clearVolumeIcon(mountPoint: mount)
    }
}
