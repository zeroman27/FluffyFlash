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

    @StateObject private var permissionsService = PermissionsService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPermissionsDetails = false

    @AppStorage("wist.appLanguage") private var appLanguageRaw: String = WistAppLanguage.system.rawValue
    @AppStorage("fluffy.maxConcurrentWrites") private var maxConcurrentWrites: Int = 3
    @AppStorage("fluffy.expertMode") private var expertModeEnabled: Bool = false
    @AppStorage("fluffy.upgradeCheckMinutes") private var upgradeCheckMinutes: Int = 15
    @AppStorage("fluffy.upgradeCheckEnabled") private var upgradeCheckEnabled: Bool = true
    @AppStorage(FluffyUSBIconStyle.appStorageKey) private var usbIconStyleRaw: String = FluffyUSBIconStyle.defaultStyle.rawValue
    @AppStorage("fluffy.applyVolumeIconsToFluffyDrives") private var applyVolumeIconsToFluffyDrives: Bool = true
    @AppStorage(WistPreferences.Keys.preferredISOFolder) private var preferredISOFolderPath: String = ""
    @AppStorage(WistPreferences.Keys.autoEjectAfterWrite) private var autoEjectAfterWrite: Bool = true
    @AppStorage(WistPreferences.Keys.notifyOnComplete) private var notifyOnComplete: Bool = true
    @AppStorage(WistPreferences.Keys.productionLineMode) private var productionLineMode: Bool = false

    @State private var cacheSize: Int64 = 0
    @State private var showingClearCacheConfirm = false
    @State private var manualFinderDrives: [RemovableDriveInfo] = []
    @State private var manualFinderDeviceId: String = ""

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
                        privacyPermissionsCard
                        languageCard
                        writeBehaviourCard
                        isoFolderCard
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
        .task {
            await permissionsService.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await permissionsService.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permissionsService.refresh() }
        }
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

                Toggle(String(localized: "Also set this icon in Finder for drives written by Fluffy (Windows or macOS)"), isOn: $applyVolumeIconsToFluffyDrives)
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

                Divider().opacity(0.35)

                Text(String(localized: "Apply the selected artwork to any mounted USB volume (Finder only). Does not require Fluffy metadata on the drive."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Picker(String(localized: "Volume"), selection: $manualFinderDeviceId) {
                        Text(String(localized: "Choose a drive…")).tag("")
                        ForEach(manualFinderDrives.filter { $0.mountPoint != nil }) { d in
                            Text("\(d.mediaName) — \(d.deviceIdentifier)").tag(d.deviceIdentifier)
                        }
                    }
                    .frame(minWidth: 220, maxWidth: 360, alignment: .leading)
                    .labelsHidden()

                    Button {
                        Task { await refreshManualFinderDrives(selectFirstIfNeeded: false) }
                    } label: {
                        Label(String(localized: "Refresh list"), systemImage: "arrow.clockwise")
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await applyManualFinderIconToSelection() }
                    } label: {
                        Label(String(localized: "Apply icon to selected volume"), systemImage: "paintbrush.pointed.fill")
                    }
                    .disabled(manualFinderDeviceId.isEmpty)

                    Button(role: .destructive) {
                        Task { await clearManualFinderIconForSelection() }
                    } label: {
                        Label(String(localized: "Reset icon on selected volume"), systemImage: "arrow.uturn.backward")
                    }
                    .disabled(manualFinderDeviceId.isEmpty)
                }
            }
        }
        .task {
            await refreshManualFinderDrives(selectFirstIfNeeded: true)
        }
    }

    @MainActor
    private func applyFinderIconsToConnectedFluffyDrives() async {
        await FluffyFinderIconAutomation.applyToConnectedFluffyDrivesIfSettingEnabled()
    }

    @MainActor
    private func clearFinderIconsFromConnectedFluffyDrives() async {
        let dm = DiskManager()
        await dm.refresh()
        for d in dm.drives where d.hasFluffySidecar {
            guard let mount = d.mountPoint else { continue }
            try? FluffyVolumeIconManager.clearVolumeIcon(mountPoint: mount)
        }
    }

    @MainActor
    private func refreshManualFinderDrives(selectFirstIfNeeded: Bool) async {
        let dm = DiskManager()
        await dm.refresh()
        manualFinderDrives = dm.drives
        let mounted = dm.drives.filter { $0.mountPoint != nil }.map(\.deviceIdentifier)
        if manualFinderDeviceId.isEmpty || !mounted.contains(manualFinderDeviceId) {
            if selectFirstIfNeeded {
                manualFinderDeviceId = dm.drives.first(where: { $0.mountPoint != nil })?.deviceIdentifier ?? ""
            } else if !mounted.contains(manualFinderDeviceId) {
                manualFinderDeviceId = ""
            }
        }
    }

    @MainActor
    private func applyManualFinderIconToSelection() async {
        guard !manualFinderDeviceId.isEmpty else { return }
        let dm = DiskManager()
        await dm.refresh()
        manualFinderDrives = dm.drives
        guard let d = dm.drives.first(where: { $0.deviceIdentifier == manualFinderDeviceId }),
              let mount = d.mountPoint
        else { return }
        let style = FluffyUSBIconStyle.resolve(rawValue: usbIconStyleRaw)
        FluffyDriveIconOverrides.setOverride(deviceIdentifier: d.deviceIdentifier, styleRawValue: style.rawValue)
        try? FluffyVolumeIconManager.setVolumeIcon(style: style, mountPoint: mount)
    }

    @MainActor
    private func clearManualFinderIconForSelection() async {
        guard !manualFinderDeviceId.isEmpty else { return }
        let dm = DiskManager()
        await dm.refresh()
        manualFinderDrives = dm.drives
        guard let d = dm.drives.first(where: { $0.deviceIdentifier == manualFinderDeviceId }),
              let mount = d.mountPoint
        else { return }
        FluffyDriveIconOverrides.clearOverride(deviceIdentifier: d.deviceIdentifier)
        try? FluffyVolumeIconManager.clearVolumeIcon(mountPoint: mount)
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

    private var isoFolderCard: some View {
        MistSectionCard(title: String(localized: "ISO browse folder"), systemImage: "folder.badge.gearshape") {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "When you tap “Choose ISO…” we open this folder by default. Leave empty to use the app cache."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(displayedISOFolderPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    Button {
                        presentISOFolderPicker()
                    } label: {
                        Label(String(localized: "Choose…"), systemImage: "folder")
                    }
                    Button {
                        let url = preferredISOFolderPath.isEmpty
                            ? WistCache.uupRootDirectory
                            : URL(fileURLWithPath: preferredISOFolderPath, isDirectory: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label(String(localized: "Reveal"), systemImage: "arrow.up.right.square")
                    }
                    Button(role: .destructive) {
                        preferredISOFolderPath = ""
                    } label: {
                        Label(String(localized: "Reset"), systemImage: "arrow.uturn.backward")
                    }
                    .disabled(preferredISOFolderPath.isEmpty)
                }
            }
        }
    }

    private var displayedISOFolderPath: String {
        if preferredISOFolderPath.isEmpty {
            return String(format: String(localized: "Default: %@"), WistCache.uupRootDirectory.path)
        }
        return preferredISOFolderPath
    }

    private func presentISOFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = WistPreferences.isoPickerStartingDirectory()
        panel.prompt = String(localized: "Use this folder")
        panel.title = String(localized: "Choose default ISO folder")
        if panel.runModal() == .OK, let url = panel.url {
            preferredISOFolderPath = url.path
        }
    }

    private var writeBehaviourCard: some View {
        MistSectionCard(title: String(localized: "Write behaviour"), systemImage: "externaldrive.badge.checkmark") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(String(localized: "Auto-eject after a successful write"), isOn: $autoEjectAfterWrite)
                Text(String(localized: "When off, the drive is unmounted but stays connected so you can drop extra files on it."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.3)

                Toggle(String(localized: "Notify when a write finishes"), isOn: $notifyOnComplete)
                Text(String(localized: "Posts a system notification and updates the Dock badge while writes are running."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.3)

                Toggle(String(localized: "Production Line mode"), isOn: $productionLineMode)
                Text(String(localized: "Auto-flash a freshly inserted blank USB drive using the last successful settings."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                Toggle(String(localized: "Check for newer builds (Windows via UUP; macOS via Mist catalog)"), isOn: $upgradeCheckEnabled)
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

    private var privacyPermissionsCard: some View {
        MistSectionCard(title: String(localized: "Privacy & permissions"), systemImage: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Fluffy Flash needs a few macOS permissions for USB workflows, icons, and notifications."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "Privileged helper: tap Install — macOS will ask for your password once (Apple does not allow silent install). Other items open the right Settings pane."))
                    .font(WistFont.caption(10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(PermissionItem.allCases) { item in
                    settingsPermissionRow(item: item)
                }

                if let helperErr = permissionsService.lastPrivilegedHelperInstallError {
                    Text(helperErr)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await permissionsService.refresh() }
                    } label: {
                        Label(String(localized: "Re-check all"), systemImage: "arrow.clockwise")
                    }
                    Spacer()
                }

                DisclosureGroup(isExpanded: $showPermissionsDetails) {
                    MacOSPermissionsChecklistView()
                        .padding(.top, 8)
                } label: {
                    Text(String(localized: "Show details"))
                        .font(WistFont.caption(11).weight(.medium))
                }
                .tint(.secondary)
            }
        }
    }

    private func settingsPermissionRow(item: PermissionItem) -> some View {
        let st = permissionsService.statuses[item] ?? .unknown
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: settingsStatusIcon(st))
                .foregroundStyle(settingsStatusColor(st))
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(WistFont.headline(12))
                Text(item.detail)
                    .font(WistFont.caption(10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                Task { await permissionsService.grantFlow(for: item) }
            } label: {
                Text(item == .privilegedHelper ? String(localized: "Install helper…") : String(localized: "Open"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func settingsStatusIcon(_ st: PermissionStatus) -> String {
        switch st {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .unknown: return "ellipsis.circle.fill"
        }
    }

    private func settingsStatusColor(_ st: PermissionStatus) -> Color {
        switch st {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        case .unknown: return .secondary
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
