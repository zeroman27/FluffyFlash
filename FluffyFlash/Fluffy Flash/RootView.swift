//
//  RootView.swift
//  Fluffy Flash
//
//  Shell with a 3-area sidebar (Home / Library / Settings). Home is the
//  adaptive tool screen; Library holds cached artefacts + history; Settings
//  holds preferences. Upgrade offers surface on the sidebar as a pill and on
//  Home as a hero card.
//

import AppKit
import SwiftUI

enum WistArea: String, CaseIterable, Identifiable {
    case home
    case library
    case settings
#if DEBUG && LAB_LOCAL
    case lab
#endif

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .settings: return "Settings"
#if DEBUG && LAB_LOCAL
        case .lab: return "Lab"
#endif
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .home: return "Create & upgrade"
        case .library: return "Caches · history · drives"
        case .settings: return "Preferences"
#if DEBUG && LAB_LOCAL
        case .lab: return "Experiments"
#endif
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "sparkles"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
#if DEBUG && LAB_LOCAL
        case .lab: return "testtube.2"
#endif
        }
    }

    /// Name of the soft-textured asset used in the sidebar (replaces SF Symbols).
    var fluffyIconAsset: String {
        switch self {
        case .home: return "FluffyIconHome"
        case .library: return "FluffyIconLibrary"
        case .settings: return "FluffyIconSettings"
#if DEBUG && LAB_LOCAL
        case .lab: return "FluffyIconInfo"
#endif
        }
    }
}

struct RootView: View {
    @StateObject private var diskManager = DiskManager()
    @StateObject private var downloadISOViewModel = DownloadISOViewModel()
    @StateObject private var usbWriterViewModel = USBWriterViewModel()
    @StateObject private var e2ePipeline = EndToEndMediaPipeline()
    @StateObject private var writeHistory = WriteHistoryStore()
    @StateObject private var upgradeDetector = WistUSBUpgradeDetector()
    @StateObject private var macOSDownloadModel = MacOSDownloadViewModel()
    @StateObject private var macOSUSBWriter = MacOSUSBWriter()
    @StateObject private var macOSE2E = MacOSEndToEndPipeline()

    @SceneStorage("wist.lastArea") private var areaRaw: String = WistArea.home.rawValue
    @State private var selectedUSBDeviceIdsWindows: Set<String> = []
    @State private var selectedUSBDeviceIdsMacOS: Set<String> = []
    /// Library → History «Repeat»: set together with switching to Home so `HomeView` can apply on appear.
    @State private var historyRepeatEntryId: UUID?

    private var area: WistArea {
        get { WistArea(rawValue: areaRaw) ?? .home }
        nonmutating set { areaRaw = newValue.rawValue }
    }

    @AppStorage("wist.appLanguage") private var appLanguageRaw: String = WistAppLanguage.system.rawValue
    @AppStorage("fluffy.upgradeCheckMinutes") private var upgradeCheckMinutes: Int = 15
    @AppStorage("fluffy.upgradeCheckEnabled") private var upgradeCheckEnabled: Bool = true
    @AppStorage("wist.appMode") private var appModeRaw: String = AppMode.windows.rawValue

    @Namespace private var sidebarHighlightNS
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private let floatingNavWidth: CGFloat = 268
    private let windowInnerCornerRadius: CGFloat = 34
    private let windowInnerInset: CGFloat = 10

    private var appMode: AppMode {
        AppMode(rawValue: appModeRaw) ?? .windows
    }

    private var selectedUSBDeviceIdsBinding: Binding<Set<String>> {
        Binding(
            get: { appMode == .windows ? selectedUSBDeviceIdsWindows : selectedUSBDeviceIdsMacOS },
            set: { newValue in
                if appMode == .windows {
                    selectedUSBDeviceIdsWindows = newValue
                } else {
                    selectedUSBDeviceIdsMacOS = newValue
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WistShellWindowBackdrop()
                .ignoresSafeArea()

            ZStack {
                HStack(alignment: .top, spacing: 16) {
                    floatingNavigationPanel
                        .frame(width: floatingNavWidth, alignment: .top)

                    mainContentColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .padding(windowInnerInset)
            .background {
                RoundedRectangle(cornerRadius: windowInnerCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.001)) // keeps hit-testing stable without changing look
            }
            .clipShape(RoundedRectangle(cornerRadius: windowInnerCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: windowInnerCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    .blendMode(.overlay)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TransparentTitleBarConfigurator())
        .environment(\.locale, (WistAppLanguage(rawValue: appLanguageRaw) ?? .system).locale)
        .id(appLanguageRaw)
        .task {
            upgradeDetector.cacheTTLSeconds = TimeInterval(upgradeCheckMinutes * 60)
            upgradeDetector.isNetworkProbingEnabled = upgradeCheckEnabled
            upgradeDetector.attach(to: diskManager)
            await diskManager.refresh()
        }
        // Prefetch mist catalog for macOS mode in the background (even before Home is opened).
        .task(id: "\(appModeRaw)-\(macOSDownloadModel.catalogAutoRefreshTaskID)") {
            guard appMode == .macos else { return }
            await macOSDownloadModel.refreshList()
        }
    }

    private var floatingNavigationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            fluffySidebarBanner
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mode")
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(appMode.title)
                        .font(WistFont.headline(12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ModeSliderSwitch(
                    mode: Binding(
                        get: { appMode },
                        set: { newMode in
                            withAnimation(sidebarSelectionAnimation) {
                                appModeRaw = newMode.rawValue
                            }
                        }
                    ),
                    width: 132,
                    height: 36
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                Text("Workspace")
                    .font(WistFont.caption(10))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)

                VStack(spacing: 6) {
                    ForEach(WistArea.allCases) { item in
                        FluffySidebarAreaRow(
                            area: item,
                            isSelected: area == item,
                            badge: badge(for: item),
                            highlightNS: sidebarHighlightNS
                        ) {
                            selectArea(item)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 12)

            if actionableUpgradeOfferCount > 0, area != .home {
                sidebarUpgradePill
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }

            Spacer(minLength: 0)

            fluffyTipSection
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .wistShellGlassCard(cornerRadius: 22)
    }

    private var fluffyTipSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WistTheme.neonOrange.opacity(0.85))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tip")
                    .font(WistFont.caption(10))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("Attach a USB drive written by Fluffy Flash (Windows or macOS installer) to see automatic upgrade offers.")
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .fluffyPillow(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    private var fluffySidebarBanner: some View {
        Image("FluffyBanner")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(minHeight: 96, idealHeight: 108, maxHeight: 120)
            .padding(.horizontal, 2)
            .accessibilityLabel("Fluffy Flash")
    }

    private var actionableUpgradeOfferCount: Int {
        upgradeDetector.offers.filter(\.isNewer).count + upgradeDetector.macOSOffers.filter(\.isNewer).count
    }

    private var sidebarUpgradePill: some View {
        let count = actionableUpgradeOfferCount
        return Button {
            selectArea(.home)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(Color.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Upgrade available"))
                        .font(WistFont.headline(12))
                        .foregroundStyle(.white)
                    Text(
                        count == 1
                            ? String(localized: "1 Fluffy drive")
                            : String(format: String(localized: "%lld Fluffy drives"), Int64(count))
                    )
                    .font(WistFont.caption(10))
                    .foregroundStyle(.white.opacity(0.82))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                LinearGradient(
                    colors: [FluffyColor.purple, FluffyColor.purpleGlow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: FluffyColor.purpleGlow.opacity(0.45), radius: 10, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func badge(for area: WistArea) -> Int? {
        if area == .home {
            let n = actionableUpgradeOfferCount
            return n == 0 ? nil : n
        }
        return nil
    }

    private var mainContentColumn: some View {
        VStack(spacing: 0) {
            Group {
                switch area {
                case .home:
                    HomeView(
                        appMode: appMode,
                        downloadModel: downloadISOViewModel,
                        macOSModel: macOSDownloadModel,
                        macOSUSBWriter: macOSUSBWriter,
                        macOSE2E: macOSE2E,
                        diskManager: diskManager,
                        usbWriter: usbWriterViewModel,
                        e2e: e2ePipeline,
                        upgradeDetector: upgradeDetector,
                        history: writeHistory,
                        selectedUSBDeviceIds: selectedUSBDeviceIdsBinding,
                        historyRepeatEntryId: $historyRepeatEntryId
                    )
                case .library:
                    LibraryView(
                        diskManager: diskManager,
                        usbWriter: usbWriterViewModel,
                        downloadModel: downloadISOViewModel,
                        e2e: e2ePipeline,
                        upgradeDetector: upgradeDetector,
                        history: writeHistory,
                        onRequestHistoryRepeat: { entryId in
                            areaRaw = WistArea.home.rawValue
                            historyRepeatEntryId = entryId
                        }
                    )
                case .settings:
                    SettingsView(upgradeDetector: upgradeDetector)
#if DEBUG && LAB_LOCAL
                case .lab:
                    LabView()
#endif
                }
            }
            .frame(minWidth: 520, minHeight: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Morph the entire right column when the app mode changes.
        .id(appModeRaw)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if downloadISOViewModel.isDownloading {
                WistGlobalDownloadProgressStrip(model: downloadISOViewModel)
            }
        }
        .wistShellGlassCard(cornerRadius: 22)
    }

    private var sidebarSelectionAnimation: Animation {
        if accessibilityReduceMotion {
            return .easeInOut(duration: 0.2)
        }
        return .spring(response: 0.44, dampingFraction: 0.56, blendDuration: 0.12)
    }

    private func selectArea(_ item: WistArea) {
        guard area != item else { return }
        withAnimation(sidebarSelectionAnimation) {
            area = item
        }
    }
}

// MARK: - Sidebar row

private struct FluffySidebarAreaRow: View {
    let area: WistArea
    let isSelected: Bool
    let badge: Int?
    let highlightNS: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(area.fluffyIconAsset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .shadow(
                        color: isSelected
                            ? FluffyColor.purpleGlow.opacity(0.55)
                            : Color.black.opacity(0.35),
                        radius: isSelected ? 10 : 6,
                        x: 0,
                        y: isSelected ? 3 : 2
                    )
                    .saturation(isSelected ? 1.0 : 0.85)
                    .opacity(isSelected ? 1.0 : 0.9)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(area.title)
                        .font(WistFont.headline(13))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(area.subtitle)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(WistFont.caption(10).monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(FluffyColor.orange))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mistHoverRowHighlight(isHovered && !isSelected)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .matchedGeometryEffect(id: "sidebarAreaPill", in: highlightNS)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    FluffyColor.purpleGlow.opacity(0.95),
                                    FluffyColor.purple.opacity(0.75),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }
            .shadow(color: FluffyColor.purple.opacity(isSelected ? 0.18 : 0), radius: 12, x: 0, y: 0)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable()
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Global UUP download progress

private struct WistGlobalDownloadProgressStrip: View {
    @ObservedObject var model: DownloadISOViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(localized: "UUP download"))
                    .font(WistFont.caption(10))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let p = model.downloadProgress {
                    Text("\(Int((p * 100).rounded()))%")
                        .font(WistFont.caption(10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let eta = model.downloadEtaFormatted {
                    Text(eta)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
            }
            if let st = model.downloadStatus, !st.isEmpty {
                Text(st)
                    .font(WistFont.caption(9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            FluffyRopeProgressBar(value: model.downloadProgress.map { CGFloat($0) }, label: nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                FluffyColor.surface.opacity(0.96)
                LinearGradient(
                    colors: [
                        FluffyColor.purpleGlow.opacity(0.14),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
    }
}

#Preview {
    RootView()
        .frame(width: 1040, height: 680)
}
