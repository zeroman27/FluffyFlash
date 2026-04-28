//
//  SettingsView.swift
//  Fluffy Flash
//
//  App-level preferences: language, concurrency, cache paths, Expert mode,
//  upgrade-check cadence.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var upgradeDetector: WistUSBUpgradeDetector

    @AppStorage("wist.appLanguage") private var appLanguageRaw: String = WistAppLanguage.system.rawValue
    @AppStorage("fluffy.maxConcurrentWrites") private var maxConcurrentWrites: Int = 3
    @AppStorage("fluffy.expertMode") private var expertModeEnabled: Bool = false
    @AppStorage("fluffy.upgradeCheckMinutes") private var upgradeCheckMinutes: Int = 15
    @AppStorage("fluffy.upgradeCheckEnabled") private var upgradeCheckEnabled: Bool = true
    @AppStorage(FluffyUSBIconStyle.appStorageKey) private var usbIconStyleRaw: String = FluffyUSBIconStyle.defaultStyle.rawValue
    @AppStorage("fluffy.applyVolumeIconsToFluffyDrives") private var applyVolumeIconsToFluffyDrives: Bool = true

    @State private var cacheSize: Int64 = 0
    @State private var showingClearCacheConfirm = false

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
                    eyebrow: String(localized: "Settings"),
                    title: String(localized: "Preferences"),
                    subtitle: String(localized: "Interface language, write concurrency, cache location, upgrade detection, Expert mode."),
                    symbolName: "gearshape",
                    assetName: "FluffyIconSettings"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        appearanceCard
                        languageCard
                        concurrencyCard
                        upgradeCard
                        expertModeCard
                        cacheCard
                    }
                    .padding(WistTheme.pagePadding)
                }
            }
        }
        .task { refreshCacheSize() }
        .alert(String(localized: "Clear cache?"), isPresented: $showingClearCacheConfirm) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete"), role: .destructive) { clearCache() }
        } message: {
            Text(String(localized: "All cached UUP downloads and built ISOs will be removed. This cannot be undone."))
        }
    }

    private var appearanceCard: some View {
        MistSectionCard(title: String(localized: "USB drive icon"), systemImage: "externaldrive.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "Choose the artwork shown next to each connected USB drive."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)

                Toggle(String(localized: "Also set this icon in Finder for Fluffy drives"), isOn: $applyVolumeIconsToFluffyDrives)
                    .font(WistFont.body(12))

                let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FluffyUSBIconStyle.allCases) { style in
                        FluffyUSBIconStyleTile(
                            style: style,
                            isSelected: style.rawValue == usbIconStyleRaw
                        ) {
                            usbIconStyleRaw = style.rawValue
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await applyFinderIconsToConnectedFluffyDrives() }
                    } label: {
                        Label(String(localized: "Apply now"), systemImage: "paintbrush.fill")
                    }
                    .disabled(!applyVolumeIconsToFluffyDrives)

                    Button(role: .destructive) {
                        Task { await clearFinderIconsFromConnectedFluffyDrives() }
                    } label: {
                        Label(String(localized: "Reset icons"), systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
    }

    @MainActor
    private func applyFinderIconsToConnectedFluffyDrives() async {
        let style = FluffyUSBIconStyle.resolve(rawValue: usbIconStyleRaw)
        // Best-effort: apply to currently mounted Fluffy drives only.
        let dm = DiskManager()
        await dm.refresh()
        for d in dm.drives where d.wistSidecarMeta != nil {
            guard let mount = d.mountPoint else { continue }
            // Per-drive override wins.
            let overrideRaw = FluffyDriveIconOverrides.overrideStyleRawValue(for: d.deviceIdentifier)
            let resolved = FluffyUSBIconStyle.resolve(rawValue: overrideRaw ?? style.rawValue)
            try? FluffyVolumeIconManager.setVolumeIcon(style: resolved, mountPoint: mount)
        }
    }

    @MainActor
    private func clearFinderIconsFromConnectedFluffyDrives() async {
        let dm = DiskManager()
        await dm.refresh()
        for d in dm.drives where d.wistSidecarMeta != nil {
            guard let mount = d.mountPoint else { continue }
            try? FluffyVolumeIconManager.clearVolumeIcon(mountPoint: mount)
        }
    }

    private var languageCard: some View {
        MistSectionCard(title: String(localized: "Interface language"), systemImage: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                Picker(String(localized: "App language"), selection: $appLanguageRaw) {
                ForEach(WistAppLanguage.selectable) { lang in
                    Text(lang.menuLabel).tag(lang.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 280, alignment: .leading)
                Text(String(localized: "Only English is available for now."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var concurrencyCard: some View {
        MistSectionCard(title: String(localized: "Parallel USB writes"), systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 8) {
                Stepper(
                    value: Binding(
                        get: { max(1, min(4, maxConcurrentWrites)) },
                        set: { maxConcurrentWrites = max(1, min(4, $0)) }
                    ),
                    in: 1 ... 4
                ) {
                    Text(String(format: String(localized: "Max parallel writes: %lld"), Int64(maxConcurrentWrites)))
                }
                Text(String(localized: "Higher values flash more drives at once but can saturate USB bandwidth. 3 is a good default."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var upgradeCard: some View {
        MistSectionCard(title: String(localized: "Upgrade detection"), systemImage: "arrow.up.circle") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(String(localized: "Check UUPDump for newer builds"), isOn: $upgradeCheckEnabled)
                    .onChange(of: upgradeCheckEnabled) {
                        upgradeDetector.isNetworkProbingEnabled = upgradeCheckEnabled
                    }

                Picker(String(localized: "Check interval"), selection: $upgradeCheckMinutes) {
                    Text(String(localized: "15 minutes")).tag(15)
                    Text(String(localized: "60 minutes")).tag(60)
                }
                .pickerStyle(.segmented)
                .onChange(of: upgradeCheckMinutes) {
                    upgradeDetector.cacheTTLSeconds = TimeInterval(upgradeCheckMinutes * 60)
                }
                .disabled(!upgradeCheckEnabled)

                Button {
                    upgradeDetector.forceCheck()
                } label: {
                    Label(String(localized: "Check now"), systemImage: "arrow.clockwise")
                }
                .disabled(upgradeDetector.isChecking || !upgradeCheckEnabled)

                if let last = upgradeDetector.lastCheckDate {
                    Text(String(format: String(localized: "Last check: %@"), last.formatted(date: .omitted, time: .shortened)))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var expertModeCard: some View {
        MistSectionCard(title: String(localized: "Expert mode"), systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(String(localized: "Show step-by-step controls on Home"), isOn: $expertModeEnabled)
                Text(String(localized: "Adds manual Download / Build ISO / Write USB buttons and a live log to the Home screen."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cacheCard: some View {
        MistSectionCard(title: String(localized: "Cache"), systemImage: "internaldrive") {
            VStack(alignment: .leading, spacing: 10) {
                Text(WistCache.cachesRootDirectory.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(String(format: String(localized: "Total size: %@"), Self.byteFormatter.string(fromByteCount: cacheSize)))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([WistCache.cachesRootDirectory])
                    } label: {
                        Label(String(localized: "Reveal"), systemImage: "folder")
                    }
                    Button {
                        refreshCacheSize()
                    } label: {
                        Label(String(localized: "Recalculate"), systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        showingClearCacheConfirm = true
                    } label: {
                        Label(String(localized: "Clear"), systemImage: "trash")
                    }
                }
            }
        }
    }

    private func refreshCacheSize() {
        let root = WistCache.cachesRootDirectory
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            cacheSize = 0
            return
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        cacheSize = total
    }

    private func clearCache() {
        try? FileManager.default.removeItem(at: WistCache.cachesRootDirectory)
        refreshCacheSize()
    }
}

// MARK: - USB icon style tile

/// Square tile in the appearance grid: artwork + style name, highlighted with
/// the fluffy purple ring when selected.
private struct FluffyUSBIconStyleTile: View {
    let style: FluffyUSBIconStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    FluffyColor.elevated.opacity(0.88),
                                    FluffyColor.surface.opacity(0.9),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(style.assetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(10)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
                }
                .frame(height: 92)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? FluffyColor.purpleGlow.opacity(0.95)
                                : Color.white.opacity(isHovered ? 0.18 : 0.08),
                            lineWidth: isSelected ? 1.6 : 0.9
                        )
                }
                .shadow(
                    color: isSelected
                        ? FluffyColor.purpleGlow.opacity(0.4)
                        : Color.black.opacity(0.2),
                    radius: isSelected ? 10 : 5,
                    y: isSelected ? 3 : 2
                )

                HStack(spacing: 6) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(FluffyColor.purpleGlow)
                    }
                    Text(style.displayName)
                        .font(WistFont.caption(11).weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
