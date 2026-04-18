//
//  DownloadISOView.swift
//  Wist
//

import SwiftUI

private enum SourceWorkflowMode: String, CaseIterable, Identifiable {
    case catalogDownload
    case fullPipelineToUSB

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalogDownload:
            return String(localized: "Catalog & download")
        case .fullPipelineToUSB:
            return String(localized: "Full flow to USB")
        }
    }
}

/// UUPDump catalog: pick a build, confirm, load languages, download UUP. Optional full pipeline to USB on this screen.
struct DownloadISOView: View {
    @ObservedObject var model: DownloadISOViewModel
    @ObservedObject var diskManager: DiskManager
    @Binding var selectedUSBDeviceIds: Set<String>
    @ObservedObject var e2ePipeline: EndToEndMediaPipeline
    @ObservedObject var usbWriter: USBWriterViewModel
    var onRunFullPipeline: () -> Void

    @State private var tentativeBuildUUID: String?
    @State private var workflowMode: SourceWorkflowMode = .catalogDownload

    private static var hostArchLowercased: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "amd64"
        #else
        return "x86"
        #endif
    }

    var body: some View {
        MistDetailCanvas {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock
                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        workflowModePicker

                        if workflowMode == .fullPipelineToUSB {
                            fullPipelineUSBCard
                        }

                        windowsLanguageSummaryCard

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: WistTheme.gutter) {
                                leftColumn
                                buildListCard
                                    .frame(minWidth: 340, maxWidth: .infinity)
                            }
                            VStack(alignment: .leading, spacing: WistTheme.gutter) {
                                leftColumn
                                buildListCard
                            }
                        }
                    }
                    .padding(WistTheme.pagePadding)
                }
            }
        }
        .searchable(text: $model.filterSearch, prompt: String(localized: "Search by title, build, architecture…"))
        .task {
            if model.allBuilds.isEmpty {
                await model.loadBuilds()
            }
            syncTentativeAfterReconcile()
        }
        /// `displayedBuilds` is debounced for search and reconciled in the view model; sync list highlight when the filtered list changes.
        .onChange(of: model.displayedBuildsGeneration) { _, _ in
            syncTentativeAfterReconcile()
        }
        .onChange(of: tentativeBuildUUID) { _, new in
            if let new, new != model.selectedBuildUUID {
                model.clearDetailsAndEditions()
            }
        }
        .onChange(of: workflowMode) { _, mode in
            if mode == .fullPipelineToUSB {
                Task { await diskManager.refresh() }
            }
        }
    }

    private func syncTentativeAfterReconcile() {
        tentativeBuildUUID = model.selectedBuildUUID
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            MistPageHeader(
                eyebrow: String(localized: "Source"),
                title: String(localized: "Build catalog"),
                subtitle: String(localized: "Choose a Windows build from the UUPDump catalog. The installable .iso file is assembled on the next step — Cache & ISO — after the UUP payload is on disk."),
                symbolName: "square.stack.3d.down.right"
            )
            if model.details != nil, model.editions != nil {
                HStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(headerLanguageEditionLine)
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(WistTheme.pagePadding)
        .background(MistHeroBackground())
    }

    private var headerLanguageEditionLine: String {
        let code = model.selectedLanguageCode
        let lang: String = {
            if let d = model.details, let fancy = d.langFancyNames[code] {
                return "\(fancy) (\(code))"
            }
            return code
        }()
        let token = model.selectedEditionToken
        let ed: String = {
            if let editions = model.editions, !token.isEmpty, let fancy = editions.editionFancyNames[token] {
                return fancy
            }
            return token.isEmpty ? "—" : token
        }()
        return String(format: String(localized: "%@ · %@"), lang, ed)
    }

    // MARK: - Mode

    private var workflowModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Workflow"))
                .font(WistFont.caption(10))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Picker(String(localized: "Workflow"), selection: $workflowMode) {
                ForEach(SourceWorkflowMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if workflowMode == .fullPipelineToUSB {
                Text(String(localized: "Uses the same steps as Run all: UUP download → ISO conversion → USB write. Select removable drives below, then run the full pipeline."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Full pipeline USB

    private var fullPipelineUSBCard: some View {
        MistSectionCard(title: String(localized: "USB drives (full flow)"), systemImage: "externaldrive") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        Task { await diskManager.refresh() }
                    } label: {
                        Label(String(localized: "Refresh list"), systemImage: "arrow.clockwise")
                    }
                    .disabled(diskManager.isRefreshing)
                    Spacer()
                    if !selectedUSBDeviceIds.isEmpty {
                        Text(String(format: String(localized: "Selected: %lld"), Int64(selectedUSBDeviceIds.count)))
                            .font(WistFont.caption(10))
                            .foregroundStyle(.secondary)
                    }
                }
                if diskManager.drives.isEmpty {
                    Text(String(localized: "Connect a USB drive and refresh."))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: $selectedUSBDeviceIds) {
                        ForEach(diskManager.drives) { drive in
                            HStack {
                                Text(drive.mediaName)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: drive.totalSizeBytes, countStyle: .file))
                                    .font(WistFont.caption(10))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(drive.deviceIdentifier)
                        }
                    }
                    .frame(minHeight: 120)
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }

                Button {
                    onRunFullPipeline()
                } label: {
                    Label(String(localized: "Run full pipeline"), systemImage: "bolt.horizontal.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canRunFullPipelineLocal || e2ePipeline.isActive || usbWriter.isWriting || model.isDownloading || model.isConvertingUUP)

                if e2ePipeline.isActive {
                    MistProProgressIndeterminate(height: 4, label: e2ePipeline.statusLine)
                }
            }
        }
    }

    private var canRunFullPipelineLocal: Bool {
        guard model.selectedBuild != nil else { return false }
        guard model.details != nil, model.editions != nil else { return false }
        guard !model.selectedLanguageCode.isEmpty else { return false }
        if let list = model.editions?.editionList, !list.isEmpty, model.selectedEditionToken.isEmpty {
            return false
        }
        guard !selectedUSBDeviceIds.isEmpty else { return false }
        return true
    }

    // MARK: - Language summary (duplicate of Downloads, compact)

    private var windowsLanguageSummaryCard: some View {
        MistSectionCard(title: String(localized: "Windows package language & edition"), systemImage: "globe") {
            VStack(alignment: .leading, spacing: 8) {
                if model.details != nil {
                    HStack {
                        Text(String(localized: "Language"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(languageSummaryLine)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(WistFont.body(12))
                    HStack {
                        Text(String(localized: "Edition"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(editionSummaryLine)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(WistFont.body(12))
                } else {
                    Text(String(localized: "Confirm a build and load download options to see language and edition here."))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var languageSummaryLine: String {
        let code = model.selectedLanguageCode
        if code.isEmpty { return "—" }
        if let d = model.details, let fancy = d.langFancyNames[code] {
            return "\(fancy) (\(code))"
        }
        return code
    }

    private var editionSummaryLine: String {
        let token = model.selectedEditionToken
        if token.isEmpty { return "—" }
        if let editions = model.editions, let fancy = editions.editionFancyNames[token] {
            return fancy
        }
        return token
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: WistTheme.gutter) {
            filterBar
            confirmRow
            insiderCallout
            optionsCard
            downloadCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var confirmRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await confirmSelectionAndLoadDetails() }
            } label: {
                Label(String(localized: "Confirm selection & load options"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canConfirmSelection)

            if model.isLoadingBuilds {
                MistProProgressIndeterminate(height: 4, label: String(localized: "Loading…"))
                    .frame(maxWidth: 160, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private var canConfirmSelection: Bool {
        guard let t = tentativeBuildUUID else { return false }
        if model.isLoadingBuilds || model.isDownloading { return false }
        if model.details != nil, model.selectedBuildUUID == t { return false }
        return true
    }

    private func confirmSelectionAndLoadDetails() async {
        guard let t = tentativeBuildUUID else { return }
        model.selectedBuildUUID = t
        await model.loadDetailsAndEditionsForSelection()
    }

    @ViewBuilder
    private var insiderCallout: some View {
        if let b = tentativeBuild, b.uupIsInsiderStyleChannel {
            MistWarningCallout(
                title: String(localized: "Preview / Insider build"),
                message: String(localized: "This build looks like an Insider or preview channel. It may be less stable than retail releases.")
            )
        }
    }

    private var tentativeBuild: UUPBuilds.Build? {
        guard let id = tentativeBuildUUID else { return nil }
        return model.displayedBuilds.first { $0.uuid == id } ?? model.allBuilds.first { $0.uuid == id }
    }

    private var filterBar: some View {
        MistSectionCard(title: String(localized: "Filters"), systemImage: "line.3.horizontal.decrease.circle") {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    filterFiltersRowWide
                    filterFiltersStacked
                }

                Text(filterSummary)
                    .font(WistFont.caption(11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// One row when the window is wide enough; avoids crushing label text into single-character “columns”.
    private var filterFiltersRowWide: some View {
        HStack(alignment: .center, spacing: 12) {
            filterProductPicker
            filterChannelPicker
            filterArchPicker
            Spacer(minLength: 8)
            filterResetButton
        }
    }

    /// Stacked layout when horizontal space is tight — labels stay horizontal above each control.
    private var filterFiltersStacked: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterProductPicker
            filterChannelPicker
            HStack(alignment: .top, spacing: 12) {
                filterArchPicker
                Spacer(minLength: 0)
                filterResetButton
            }
        }
    }

    private var filterProductPicker: some View {
        filterLabeledPicker(title: String(localized: "Product"), selection: $model.filterProduct) {
            ForEach(UUPProductFilter.allCases) { f in
                Text(f.rawValue).tag(f)
            }
        }
    }

    private var filterChannelPicker: some View {
        filterLabeledPicker(title: String(localized: "Channel"), selection: $model.filterChannel) {
            ForEach(UUPChannelFilter.allCases) { f in
                Text(f.rawValue).tag(f)
            }
        }
    }

    private var filterArchPicker: some View {
        filterLabeledPicker(title: String(localized: "Architecture"), selection: $model.filterArch) {
            ForEach(UUPArchFilter.allCases) { f in
                Text(f.rawValue).tag(f)
            }
        }
    }

    private var filterResetButton: some View {
        Button(String(localized: "Reset")) {
            model.filterProduct = .all
            model.filterChannel = .all
            model.filterArch = .all
            model.filterSearch = ""
        }
        .disabled(model.filterProduct == .all && model.filterChannel == .all && model.filterArch == .all && model.filterSearch.isEmpty)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var filterSummary: String {
        let n = model.displayedBuilds.count
        let total = model.allBuilds.count
        return String(format: String(localized: "Showing %lld of %lld builds · newest first"), Int64(n), Int64(total))
    }

    private func filterLabeledPicker<Selection: Hashable, Content: View>(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Picker(title, selection: selection, content: content)
                    .labelsHidden()
                    .frame(minWidth: 130, idealWidth: 168, maxWidth: 280, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Picker(title, selection: selection, content: content)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var buildListCard: some View {
        MistOpenSection(title: String(localized: "Windows builds (UUP)"), systemImage: "list.bullet.rectangle") {
            HStack(spacing: 10) {
                Button {
                    Task { await model.loadBuilds() }
                } label: {
                    Label(String(localized: "Refresh catalog"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingBuilds || model.isDownloading)
                .controlSize(.small)

                if model.isLoadingBuilds && !model.allBuilds.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
            .padding(.bottom, 8)

            buildListScrollOrPlaceholder
        }
    }

    @ViewBuilder
    private var buildListScrollOrPlaceholder: some View {
        if model.isLoadingBuilds && model.allBuilds.isEmpty {
            buildCatalogLoadingPlaceholder
                .frame(minHeight: 260)
        } else if model.displayedBuilds.isEmpty {
            buildCatalogEmptyPlaceholder
                .frame(minHeight: 260)
        } else {
            // No `MistSectionCard` here: one glass rect behind the whole list = huge CALayer. Rows use flat fills (no per-row Material).
            LazyVStack(spacing: 6) {
                ForEach(model.displayedBuilds, id: \.uuid) { build in
                    UUPBuildRow(
                        build: build,
                        isSelected: tentativeBuildUUID == build.uuid,
                        isHostArch: build.arch.lowercased() == Self.hostArchLowercased
                    ) {
                        tentativeBuildUUID = build.uuid
                    }
                }
            }
        }
    }

    private var buildCatalogLoadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            Text(String(localized: "Loading catalog…"))
                .font(WistFont.caption(11))
                .foregroundStyle(.secondary)
            Text(String(localized: "Fetching the build list from UUPDump."))
                .font(WistFont.caption(10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var buildCatalogEmptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(String(localized: "No matching builds"))
                .font(WistFont.title(14))
            Text(emptyBuildListExplanation)
                .font(WistFont.body(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if buildListHasActiveFiltersOrSearch {
                Button(String(localized: "Reset filters")) {
                    model.filterProduct = .all
                    model.filterChannel = .all
                    model.filterArch = .all
                    model.filterSearch = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private var buildListHasActiveFiltersOrSearch: Bool {
        let q = model.filterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.filterProduct != .all
            || model.filterChannel != .all
            || model.filterArch != .all
            || !q.isEmpty
    }

    private var emptyBuildListExplanation: String {
        if model.allBuilds.isEmpty {
            return String(localized: "The catalog is empty. Tap Refresh catalog to try again.")
        }
        if buildListHasActiveFiltersOrSearch {
            return String(localized: "Nothing matches the current filters or search. Reset filters or broaden your search.")
        }
        return String(localized: "No builds are available to show.")
    }

    private func dateLabel(for created: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(created))
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    @ViewBuilder
    private var optionsCard: some View {
        MistSectionCard(title: String(localized: "Download options"), systemImage: "globe") {
            if let details = model.details, let editions = model.editions {
                Form {
                    Picker(String(localized: "Language"), selection: $model.selectedLanguageCode) {
                        ForEach(details.langList, id: \.self) { code in
                            let fancy = details.langFancyNames[code] ?? code
                            Text("\(fancy) (\(code))").tag(code)
                        }
                    }
                    Picker(String(localized: "Edition"), selection: $model.selectedEditionToken) {
                        ForEach(editions.editionList, id: \.self) { key in
                            let fancy = editions.editionFancyNames[key] ?? key
                            Text(fancy).tag(key)
                        }
                    }
                }
                .padding(.vertical, 2)
            } else {
                MistEmptyState(
                    systemImage: "cursorarrow.click.2",
                    title: String(localized: "Load options"),
                    message: String(localized: "Pick a build in the list, then tap Confirm selection & load options.")
                )
            }
        }
    }

    private var downloadCard: some View {
        MistSectionCard(title: String(localized: "Cache"), systemImage: "arrow.down.doc") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        Task { await model.downloadSelectedPackageToCache() }
                    } label: {
                        Label(String(localized: "Download UUP to cache"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canDownloadUUP)

                    if model.isDownloading {
                        Button(String(localized: "Stop"), role: .cancel) {
                            model.cancelActiveDownload()
                        }
                    }
                }

                if !canDownloadUUP, !model.isDownloading, tentativeBuildUUID != nil {
                    Text(downloadDisabledHint)
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                }

                if model.isDownloading {
                    Group {
                        if let p = model.downloadProgress {
                            MistProProgressBar(
                                value: p,
                                label: model.downloadStatus ?? String(localized: "Downloading…")
                            )
                        } else {
                            MistProProgressIndeterminate(label: model.downloadStatus ?? String(localized: "Downloading…"))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else if let status = model.downloadStatus, !status.isEmpty {
                    Text(status)
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let err = model.lastError {
                    Text(err)
                        .font(WistFont.body(12))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .animation(.easeInOut(duration: WistMotion.quick), value: model.isDownloading)
        }
    }

    private var canDownloadUUP: Bool {
        guard model.details != nil else { return false }
        guard !model.isDownloading else { return false }
        guard tentativeBuildUUID != nil else { return false }
        guard model.selectedBuildUUID == tentativeBuildUUID else { return false }
        return true
    }

    private var downloadDisabledHint: String {
        if model.details == nil {
            return String(localized: "Confirm your build and load download options before downloading.")
        }
        if model.selectedBuildUUID != tentativeBuildUUID {
            return String(localized: "Your list selection doesn’t match the confirmed build. Confirm again or pick Download.")
        }
        return ""
    }

}

// MARK: - Build list row (flat surface + hover — avoids per-row Material on macOS SwiftUI)

private struct UUPBuildRow: View {
    let build: UUPBuilds.Build
    let isSelected: Bool
    let isHostArch: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(build.title)
                            .font(WistFont.body(13))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)

                        if isHostArch {
                            Text(String(localized: "This Mac"))
                                .font(WistFont.caption(9))
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(chipFill)
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                        }
                                }
                        }
                    }

                    HStack(spacing: 8) {
                        Text(String(format: String(localized: "Build %@"), build.build))
                        Text("·")
                        Text(build.arch)
                        if let created = build.created {
                            Text("·")
                            Text(dateLabelStatic(created))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(WistFont.caption(10))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mistHoverRowHighlight(isHovered && !isSelected)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(rowFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isSelected
                                ? [Color.white.opacity(0.2), WistTheme.glassBorder.opacity(0.95)]
                                : [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable()
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(build.title)
    }

    private var rowFill: Color {
        switch (isSelected, isHostArch) {
        case (true, _):
            return WistTheme.mistVioletTint.opacity(colorScheme == .dark ? 0.26 : 0.18)
        case (false, true):
            return WistTheme.mistVioletTint.opacity(colorScheme == .dark ? 0.1 : 0.07)
        case (false, false):
            return WistTheme.surfaceElevated.opacity(colorScheme == .dark ? 0.52 : 0.88)
        }
    }

    private var chipFill: Color {
        WistTheme.surfaceElevated.opacity(colorScheme == .dark ? 0.72 : 0.92)
    }

    private func dateLabelStatic(_ created: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(created))
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview {
    struct PreviewDownloadISO: View {
        @StateObject private var model = DownloadISOViewModel()
        @StateObject private var disk = DiskManager()
        @StateObject private var usb = USBWriterViewModel()
        @StateObject private var e2e = EndToEndMediaPipeline()
        @State private var ids: Set<String> = []
        var body: some View {
            DownloadISOView(
                model: model,
                diskManager: disk,
                selectedUSBDeviceIds: $ids,
                e2ePipeline: e2e,
                usbWriter: usb,
                onRunFullPipeline: {}
            )
            .frame(width: 900, height: 720)
        }
    }
    return PreviewDownloadISO()
}
