//
//  LibraryView.swift
//  Fluffy Flash
//
//  Cached artefacts: UUP downloads, produced ISOs, history log, detected
//  Fluffy drives (with upgrade badges).
//

import AppKit
import SwiftUI

private enum LibraryHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case windows
    case macos
    case failed

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .windows: return "Windows"
        case .macos: return "macOS"
        case .failed: return "Failed"
        }
    }
}

enum LibraryTab: String, CaseIterable, Identifiable {
    case uup
    case isos
    case macos
    case history
    case drives
    case doctor

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .uup: return "UUP"
        case .isos: return "ISOs"
        case .macos: return "macOS"
        case .history: return "History"
        case .drives: return "Fluffy drives"
        case .doctor: return "USB Doctor"
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
    /// Switches to Home and passes the entry id so `HomeView` can restore ISO/installer + drive selection.
    var onRequestHistoryRepeat: (UUID) -> Void

    @State private var tab: LibraryTab = .uup
    @State private var cacheFolders: [UUPCacheFolder] = []
    @State private var macosArtefacts: [MacOSCache.Artefact] = []
    @State private var isPresentingHistoryLog = false
    @State private var historyLogTitle: String = ""
    @State private var historyLogText: String = ""
    @State private var pendingDeleteUUPParent: URL?
    @State private var historyFilter: LibraryHistoryFilter = .all
    @State private var historySearch: String = ""

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
                    subtitle: String(localized: "UUP caches (in progress), built ISOs, recent write history, and detected Fluffy drives."),
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
                        case .uup: uupSection
                        case .isos: isosSection
                        case .macos: macosSection
                        case .history: historySection
                        case .drives: drivesSection
                        case .doctor:
                            FluffyUSBDoctorView(diskManager: diskManager)
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
            if tab == .uup || tab == .isos { reloadCache() }
            if tab == .macos { reloadMacOSCache() }
        }
        .confirmationDialog(
            String(localized: "Delete the UUP source folder?"),
            isPresented: Binding(
                get: { pendingDeleteUUPParent != nil },
                set: { if !$0 { pendingDeleteUUPParent = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete folder"), role: .destructive) {
                if let u = pendingDeleteUUPParent {
                    try? FileManager.default.removeItem(at: u)
                    pendingDeleteUUPParent = nil
                    reloadCache()
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingDeleteUUPParent = nil
            }
        } message: {
            Text(String(localized: "This removes the UUP cache directory that contained the ISO. The ISO file will be deleted too."))
        }
    }

    private func reloadCache() {
        cacheFolders = WistCache.listUUPFolders().filter { !WistCache.folderContainsBuiltISO(at: $0.url) }
    }

    private func reloadMacOSCache() {
        // Ensure the folder exists so "Reveal" always works.
        try? FileManager.default.createDirectory(at: MacOSCache.rootDirectory, withIntermediateDirectories: true)
        macosArtefacts = MacOSCache.listArtefacts()
    }

    // MARK: - UUP (folders without a built ISO yet)

    private var uupSection: some View {
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
                        title: String(localized: "No UUP folders in progress"),
                        message: String(localized: "Downloaded UUP folders appear here until an ISO is built — then they move to the ISOs tab.")
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
                        let uupParent = url.deletingLastPathComponent()
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent)
                                    .font(WistFont.headline(13))
                                    .lineLimit(1)
                                Text(uupParent.path)
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
                            } label: { Image(systemName: "opticaldisc") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Reveal ISO in Finder"))
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([uupParent])
                            } label: { Image(systemName: "folder") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Open UUP folder"))
                            Button(role: .destructive) {
                                pendingDeleteUUPParent = uupParent
                            } label: { Image(systemName: "folder.badge.minus") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Delete UUP source folder"))
                            Button(role: .destructive) {
                                try? FileManager.default.removeItem(at: url)
                                reloadCache()
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help(String(localized: "Delete ISO only"))
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

    private var filteredHistoryEntries: [WriteHistoryEntry] {
        let q = historySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return history.entries.filter { entry in
            switch historyFilter {
            case .all:
                break
            case .windows:
                if entry.resolvedKind == .macOSInstaller { return false }
            case .macos:
                if entry.resolvedKind != .macOSInstaller { return false }
            case .failed:
                if entry.succeeded { return false }
            }
            if q.isEmpty { return true }
            let hay = [
                entry.buildNumber,
                entry.buildTitle,
                entry.arch,
                entry.language,
                entry.editionToken,
                entry.driveMediaName,
                entry.installerDisplayName,
                entry.installerMarketingVersion,
                entry.macOSCatalogBuild,
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            return hay.contains(q)
        }
    }

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

                Picker(String(localized: "History filter"), selection: $historyFilter) {
                    ForEach(LibraryHistoryFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                TextField(String(localized: "Search build, drive, installer…"), text: $historySearch)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                if history.entries.isEmpty {
                    MistEmptyState(
                        systemImage: "clock",
                        title: String(localized: "Nothing yet"),
                        message: String(localized: "Successful or failed USB writes will be logged here.")
                    )
                } else if filteredHistoryEntries.isEmpty {
                    MistEmptyState(
                        systemImage: "line.3.horizontal.decrease.circle",
                        title: String(localized: "No matches"),
                        message: String(localized: "Try another filter or search query.")
                    )
                } else {
                    ForEach(filteredHistoryEntries) { entry in
                        historyRow(entry: entry)
                    }
                }
            }
        }
    }

    private func formatHistoryDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 {
            return String(format: String(localized: "%.0f s"), seconds)
        }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: String(localized: "%lld min %lld s"), Int64(m), Int64(s))
    }

    private func historyKindLabel(_ entry: WriteHistoryEntry) -> String {
        switch entry.resolvedKind {
        case .windowsUUP:
            return String(localized: "Windows · UUP")
        case .windowsExistingISO:
            return String(localized: "Windows · ISO")
        case .macOSInstaller:
            return String(localized: "macOS installer")
        }
    }

    private func historyRow(entry: WriteHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: entry.resolvedKind == .macOSInstaller ? "apple.logo" : "pc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: entry.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(entry.succeeded ? Color.green : Color.red)
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.buildTitle ?? entry.buildNumber)
                    .font(WistFont.headline(13))
                    .lineLimit(2)
                if entry.resolvedKind == .macOSInstaller {
                    Text("\(entry.buildNumber) · \(entry.driveMediaName)")
                        .font(WistFont.caption(10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(entry.buildNumber) · \(entry.arch) · \(entry.language) · \(entry.driveMediaName)")
                        .font(WistFont.caption(10))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(historyKindLabel(entry))
                        .font(WistFont.caption(9))
                        .foregroundStyle(.tertiary)
                    if let d = entry.durationSeconds {
                        Text("\(String(localized: "Duration")): \(formatHistoryDuration(d))")
                            .font(WistFont.caption(9))
                            .foregroundStyle(.tertiary)
                    }
                }
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
                Button {
                    onRequestHistoryRepeat(entry.id)
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .help(String(localized: "Repeat on Home"))
                .buttonStyle(.borderless)

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
                    Text(String(localized: "USB drives that contain Fluffy metadata (Windows installer or macOS installer). Upgrade badges apply to Windows tuples (arch · language · edition)."))
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

                let drives = diskManager.drives.filter { $0.hasFluffySidecar }
                if drives.isEmpty {
                    MistEmptyState(
                        systemImage: "externaldrive",
                        title: String(localized: "No Fluffy drives connected"),
                        message: String(localized: "Attach a USB drive written by Fluffy (look for Fluffy metadata on the volume) to see it here.")
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
                            macOSOffer: upgradeDetector.macOSOffers.first { $0.drive.deviceIdentifier == drive.deviceIdentifier },
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
    let macOSOffer: MacOSDriveUpgradeOffer?
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
                } else if let mac = drive.fluffyMacOSSidecarMeta {
                    Text(mac.summarySubtitle)
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
                } else if let macOSOffer, macOSOffer.isNewer {
                    Label(
                        String(format: String(localized: "Newer installer: %@ (%@)"), macOSOffer.latestInstaller.version, macOSOffer.latestInstaller.build),
                        systemImage: "arrow.up.circle.fill"
                    )
                    .font(WistFont.caption(10).weight(.medium))
                    .foregroundStyle(FluffyColor.orangeHi)
                } else if offer != nil || macOSOffer != nil {
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
        guard drive.hasFluffySidecar else { return }
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
