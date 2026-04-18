//
//  RootView.swift
//  Wist
//

import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case downloadISO
    case downloads
    case createUSB

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloadISO: return String(localized: "Source")
        case .downloads: return String(localized: "Downloads")
        case .createUSB: return String(localized: "Create USB")
        }
    }

    var subtitle: String {
        switch self {
        case .downloadISO: return String(localized: "Build catalog")
        case .downloads: return String(localized: "Cache & ISO")
        case .createUSB: return String(localized: "USB imaging")
        }
    }

    var systemImage: String {
        switch self {
        case .downloadISO: return "arrow.down.circle"
        case .downloads: return "arrow.down.doc"
        case .createUSB: return "externaldrive"
        }
    }
}

/// Main shell: sidebar navigation; detail hosts each phase.
struct RootView: View {
    @StateObject private var diskManager = DiskManager()
    @StateObject private var downloadISOViewModel = DownloadISOViewModel()
    @StateObject private var usbWriterViewModel = USBWriterViewModel()
    @StateObject private var e2ePipeline = EndToEndMediaPipeline()
    @State private var section: AppSection = .downloadISO
    /// USB drives selected for the end-to-end “Run all” flow (and multi-write on the USB screen).
    @State private var selectedUSBDeviceIds: Set<String> = []

    @Namespace private var sidebarHighlightNS
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarBrand
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Workflow")
                            .font(WistFont.caption(10))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)

                        VStack(spacing: 4) {
                            ForEach(AppSection.allCases) { item in
                                SidebarNavRowView(
                                    item: item,
                                    isSelected: section == item,
                                    highlightNS: sidebarHighlightNS
                                ) {
                                    selectSection(item)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    WistTheme.sidebarGradient
                    Rectangle()
                        .fill(WistTheme.surfaceElevated.opacity(0.22))
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch section {
                    case .downloadISO:
                        DownloadISOView(
                            model: downloadISOViewModel,
                            diskManager: diskManager,
                            selectedUSBDeviceIds: $selectedUSBDeviceIds,
                            e2ePipeline: e2ePipeline,
                            usbWriter: usbWriterViewModel,
                            onRunFullPipeline: {
                                Task {
                                    let drives = resolvedSelectedDrives
                                    await e2ePipeline.runFullPipeline(
                                        download: downloadISOViewModel,
                                        usb: usbWriterViewModel,
                                        drives: drives
                                    )
                                }
                            }
                        )
                    case .downloads:
                        DownloadsView(downloadISOViewModel: downloadISOViewModel)
                    case .createUSB:
                        CreateUSBView(
                            diskManager: diskManager,
                            usbWriter: usbWriterViewModel,
                            downloadModel: downloadISOViewModel,
                            e2e: e2ePipeline,
                            selectedDeviceIds: $selectedUSBDeviceIds
                        )
                    }
                }
                .frame(minWidth: 520, minHeight: 360)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if section != .downloadISO {
                    WorkflowBottomBar(
                        statusLine: e2ePipelineStatusText,
                        pipelinePhase: e2ePipeline.phase,
                        canRunFullPipeline: canRunFullEndToEndPipeline,
                        isDownloadBusy: downloadISOViewModel.isDownloading,
                        isConvertBusy: downloadISOViewModel.isConvertingUUP,
                        primaryActionDisabledHint: runAllDisabledUserHint,
                        onRunFullPipeline: {
                            Task {
                                let drives = resolvedSelectedDrives
                                await e2ePipeline.runFullPipeline(
                                    download: downloadISOViewModel,
                                    usb: usbWriterViewModel,
                                    drives: drives
                                )
                            }
                        }
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await diskManager.refresh()
        }
    }

    /// Shown when “Run all” is disabled (UI/UX: never leave primary actions unexplained).
    private var runAllDisabledUserHint: String? {
        guard !canRunFullEndToEndPipeline else { return nil }
        return String(
            localized: "Choose a build on Source, load download options, select at least one USB drive on Media, then try again."
        )
    }

    private var resolvedSelectedDrives: [RemovableDriveInfo] {
        let order = diskManager.drives.map(\.deviceIdentifier)
        let set = selectedUSBDeviceIds
        return order.compactMap { id in
            set.contains(id) ? diskManager.drives.first { $0.deviceIdentifier == id } : nil
        }
    }

    private var canRunFullEndToEndPipeline: Bool {
        guard downloadISOViewModel.selectedBuild != nil else { return false }
        guard downloadISOViewModel.details != nil, downloadISOViewModel.editions != nil else { return false }
        guard !downloadISOViewModel.selectedLanguageCode.isEmpty else { return false }
        if let list = downloadISOViewModel.editions?.editionList, !list.isEmpty,
           downloadISOViewModel.selectedEditionToken.isEmpty {
            return false
        }
        guard !selectedUSBDeviceIds.isEmpty else { return false }
        guard !usbWriterViewModel.isWriting else { return false }
        guard !e2ePipeline.isActive else { return false }
        return true
    }

    private var e2ePipelineStatusText: String {
        switch e2ePipeline.phase {
        case .failed(let msg):
            return String(format: String(localized: "Error: %@"), msg)
        case .completed:
            return e2ePipeline.statusLine
        case .idle:
            if !selectedUSBDeviceIds.isEmpty {
                return String(
                    format: String(localized: "Selected removable drives: %lld. Use the Media step to adjust the list if needed, then Run all."),
                    Int64(selectedUSBDeviceIds.count)
                )
            }
            return String(localized: "Choose a build on Source, select USB on Media, then Run all.")
        case .downloadingUUP:
            return String(localized: "Pipeline: downloading UUP…") + " " + e2ePipeline.statusLine
        case .convertingToISO:
            return String(localized: "Pipeline: building ISO…") + " " + e2ePipeline.statusLine
        case .writingUSB(let cur, let total):
            return String(
                format: String(localized: "Pipeline: USB write (%lld/%lld). %@"),
                Int64(cur), Int64(total), e2ePipeline.statusLine
            )
        }
    }

    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WistTheme.surfaceElevated.opacity(0.92))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(WistTheme.glassBorder, lineWidth: 1)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .medium, design: .default))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wist")
                    .font(WistFont.title(16))
                Text("Windows on Mac")
                    .font(WistFont.caption(10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var sidebarSelectionAnimation: Animation {
        if accessibilityReduceMotion {
            return .easeInOut(duration: 0.2)
        }
        // Slight overshoot / settle — lower damping = more “springy” travel.
        return .spring(response: 0.44, dampingFraction: 0.56, blendDuration: 0.12)
    }

    private func selectSection(_ item: AppSection) {
        guard section != item else { return }
        withAnimation(sidebarSelectionAnimation) {
            section = item
        }
    }

}

// MARK: - Sidebar row (hover + glass selection — avoids List row / highlight mismatch)

private struct SidebarNavRowView: View {
    let item: AppSection
    let isSelected: Bool
    let highlightNS: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: item.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(WistFont.headline(13))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    Text(item.subtitle)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mistHoverRowHighlight(isHovered && !isSelected)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WistTheme.mistVioletTint.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(WistTheme.surfaceElevated.opacity(0.42))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.16),
                                            Color.white.opacity(0.05),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .matchedGeometryEffect(id: "sidebarGlassPill", in: highlightNS)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable()
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(String(localized: "Switches the main workflow step."))
    }
}

#Preview {
    RootView()
        .frame(width: 960, height: 600)
}
