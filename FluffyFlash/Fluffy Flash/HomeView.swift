//
//  HomeView.swift
//  Fluffy Flash
//
//  Adaptive tool screen: Idle form → Running pipeline → Done card. Also
//  surfaces upgrade offers for previously flashed Fluffy drives and exposes a
//  progressive-disclosure "Expert mode" step-by-step path.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let appMode: AppMode
    @ObservedObject var downloadModel: DownloadISOViewModel
    @ObservedObject var macOSModel: MacOSDownloadViewModel
    @ObservedObject var macOSUSBWriter: MacOSUSBWriter
    @ObservedObject var macOSE2E: MacOSEndToEndPipeline
    @ObservedObject var diskManager: DiskManager
    @ObservedObject var usbWriter: USBWriterViewModel
    @ObservedObject var e2e: EndToEndMediaPipeline
    @ObservedObject var upgradeDetector: WistUSBUpgradeDetector
    @ObservedObject var history: WriteHistoryStore

    @Binding var selectedUSBDeviceIds: Set<String>

    @AppStorage("fluffy.expertMode") private var expertModeEnabled: Bool = false
    @AppStorage("fluffy.maxConcurrentWrites") private var maxConcurrentWrites: Int = 3
    @AppStorage(FluffyUSBIconStyle.appStorageKey) private var usbIconStyleRaw: String = FluffyUSBIconStyle.defaultStyle.rawValue

    @State private var isPresentingBuildPicker = false
    @State private var useExistingISO: Bool = false
    @State private var existingISOURL: URL?
    @State private var isoPickerPresented = false
    @State private var confirmFlash = false
    @State private var confirmUpgradeDrive: DriveUpgradeOffer?
    @State private var doneRingProgress: Double = 0

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
                    eyebrow: String(localized: "Home"),
                    title: headerTitle,
                    subtitle: headerSubtitle,
                    symbolName: headerSymbolName,
                    assetName: "FluffyIconHome"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        switch appMode {
                        case .windows:
                            if e2e.isActive {
                                runningSection
                            } else if case .completed = e2e.phase {
                                doneSection
                            }

                            upgradeHeroStack

                            if !e2e.isActive && !(e2e.phase == .completed) {
                                mainFormCard
                                if expertModeEnabled {
                                    expertDisclosure
                                }
                            }
                        case .macos:
                            if macOSE2E.isActive {
                                MacOSStepProgressView(
                                    e2e: macOSE2E,
                                    usbWriter: macOSUSBWriter,
                                    drives: resolvedSelectedDrives,
                                    isPresentingLog: $isPresentingMacOSFailureLog,
                                    onCopyError: { copyMacOSFailureLogToPasteboard() }
                                )
                            } else if case .completed = macOSE2E.phase {
                                macosDoneSection
                            } else if case .failed(let message) = macOSE2E.phase {
                                macosFailedSection(message: message)
                            }
                            if shouldShowMacOSForm {
                                macosFormCard
                            }
                        }
                    }
                    .padding(WistTheme.pagePadding)
                }
            }
        }
        .fileImporter(
            isPresented: $isoPickerPresented,
            allowedContentTypes: [UTType(filenameExtension: "iso") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                existingISOURL = first
            }
        }
        .sheet(isPresented: $isPresentingBuildPicker) {
            FluffyBuildPickerSheet(
                model: downloadModel,
                isPresented: $isPresentingBuildPicker
            )
        }
        .sheet(isPresented: $isPresentingFailureLog) {
            FluffyFailureLogSheet(
                title: String(localized: "Error log"),
                text: e2e.lastFailureLog ?? usbWriter.fullLogText
            ) {
                copyFailureLogToPasteboard()
            }
        }
        .sheet(isPresented: $isPresentingMacOSFailureLog) {
            FluffyFailureLogSheet(
                title: String(localized: "Error log"),
                text: macOSE2E.lastFailureLog ?? macOSUSBWriter.fullLogText
            ) {
                copyMacOSFailureLogToPasteboard()
            }
        }
        .alert(String(localized: "Erase and flash?"), isPresented: $confirmFlash) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Erase and flash"), role: .destructive) {
                startFlashFromForm()
            }
        } message: {
            Text(eraseAlertMessage)
        }
        .alert(String(localized: "Update this drive?"), isPresented: Binding(
            get: { confirmUpgradeDrive != nil },
            set: { if !$0 { confirmUpgradeDrive = nil } }
        )) {
            Button(String(localized: "Cancel"), role: .cancel) { confirmUpgradeDrive = nil }
            Button(String(localized: "Erase and update"), role: .destructive) {
                if let offer = confirmUpgradeDrive {
                    Task { await startUpgrade(offer: offer) }
                }
                confirmUpgradeDrive = nil
            }
        } message: {
            Text(String(localized: "The drive will be formatted and written with the newer build."))
        }
        .task {
            if downloadModel.allBuilds.isEmpty && !downloadModel.isLoadingBuilds {
                await downloadModel.loadBuilds()
            }
        }
    }

    private var headerTitle: String {
        switch appMode {
        case .windows:
            return String(localized: "Create a Windows USB")
        case .macos:
            return String(localized: "Create a macOS USB")
        }
    }

    private var headerSubtitle: String {
        switch appMode {
        case .windows:
            return String(localized: "Pick a Windows build, choose one or more USB drives, tap Flash. Detected Fluffy Flash drives show upgrade offers automatically.")
        case .macos:
            return String(localized: "Pick a macOS installer, choose a USB drive, download, then create bootable install media.")
        }
    }

    private var headerSymbolName: String {
        switch appMode {
        case .windows:
            return "sparkles"
        case .macos:
            return "apple.logo"
        }
    }

    // MARK: - Upgrade hero

    @ViewBuilder
    private var upgradeHeroStack: some View {
        let actionable = upgradeDetector.offers.filter { $0.isNewer }
        if !actionable.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(actionable) { offer in
                    upgradeHeroRow(offer: offer)
                }
            }
        }
    }

    private func upgradeHeroRow(offer: DriveUpgradeOffer) -> some View {
        MistSectionCard(
            title: String(localized: "Upgrade available for a Fluffy drive"),
            systemImage: "arrow.up.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(offer.drive.mediaName)
                            .font(WistFont.headline(14))
                        Text(
                            String(
                                format: String(localized: "Current build %@  →  Latest build %@"),
                                offer.currentMeta.buildNumber,
                                offer.latestBuild.build
                            )
                        )
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                        Text("\(offer.currentMeta.arch) · \(offer.currentMeta.language) · \(offer.currentMeta.editionToken)")
                            .font(WistFont.caption(10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        confirmUpgradeDrive = offer
                    } label: {
                        Label(String(localized: "Update in one click"), systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(e2e.isActive || usbWriter.isWriting)
                }
            }
        }
    }

    // MARK: - Main form

    private var mainFormCard: some View {
        MistSectionCard(title: String(localized: "Flash new Windows"), systemImage: "hammer") {
            VStack(alignment: .leading, spacing: 16) {
                sourceToggleRow
                if useExistingISO {
                    existingISORow
                } else {
                    buildSelectionRow
                    if downloadModel.details != nil && downloadModel.editions != nil {
                        languageEditionRow
                    } else if let build = downloadModel.selectedBuild {
                        Button {
                            Task { await downloadModel.loadDetailsAndEditionsForSelection() }
                        } label: {
                            Label(String(localized: "Load language and edition for \(build.title)"),
                                  systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(downloadModel.isLoadingBuilds)
                    }
                }

                driveListRow

                flashCTARow
            }
        }
    }

    private var sourceToggleRow: some View {
        Picker(selection: $useExistingISO) {
            Text(String(localized: "Download UUP + build ISO")).tag(false)
            Text(String(localized: "Use existing ISO")).tag(true)
        } label: {
            Text(String(localized: "Source"))
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }

    private var buildSelectionRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Windows build"))
                    .font(WistFont.eyebrow(10))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                if let build = downloadModel.selectedBuild {
                    Text(build.title)
                        .font(WistFont.headline(13))
                        .lineLimit(2)
                    Text("\(build.build) · \(build.arch)")
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "No build selected"))
                        .font(WistFont.body(12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                isPresentingBuildPicker = true
            } label: {
                Label(
                    downloadModel.selectedBuild == nil
                        ? String(localized: "Browse catalog…")
                        : String(localized: "Change build…"),
                    systemImage: "magnifyingglass"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var existingISORow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "ISO file"))
                    .font(WistFont.eyebrow(10))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                if let url = existingISOURL {
                    Text(url.lastPathComponent)
                        .font(WistFont.headline(13))
                        .lineLimit(2)
                    Text(url.deletingLastPathComponent().path)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(String(localized: "No ISO selected"))
                        .font(WistFont.body(12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                isoPickerPresented = true
            } label: {
                Label(String(localized: "Choose ISO…"), systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var languageEditionRow: some View {
        let details = downloadModel.details
        let editions = downloadModel.editions
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Language"))
                    .font(WistFont.eyebrow(10))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                if let details {
                    Picker(String(localized: "Language"), selection: $downloadModel.selectedLanguageCode) {
                        ForEach(details.langList, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: downloadModel.selectedLanguageCode) {
                        Task { await downloadModel.loadDetailsAndEditionsForSelection() }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Edition"))
                    .font(WistFont.eyebrow(10))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                if let editions {
                    Picker(String(localized: "Edition"), selection: $downloadModel.selectedEditionToken) {
                        ForEach(editions.editionList, id: \.self) { token in
                            Text(token).tag(token)
                        }
                    }
                    .labelsHidden()
                }
            }
            Spacer(minLength: 8)
        }
    }

    private var driveListRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "USB drives"))
                    .font(WistFont.eyebrow(10))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                if diskManager.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.trailing, 4)
                }
                Button {
                    Task { await diskManager.refresh() }
                } label: {
                    Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                        .font(WistFont.caption(11).weight(.medium))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(diskManager.isRefreshing || usbWriter.isWriting)
            }

            if let err = diskManager.lastError {
                Text(err)
                    .font(WistFont.caption(11))
                    .foregroundStyle(.red)
            }

            if diskManager.drives.isEmpty {
                MistEmptyState(
                    systemImage: "externaldrive.trianglebadge.exclamationmark",
                    title: String(localized: "No drives found"),
                    message: String(localized: "Connect one or more USB drives and tap Refresh. Internal disks are hidden.")
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(diskManager.drives) { drive in
                        FluffyDriveRow(
                            drive: drive,
                            isSelected: selectedUSBDeviceIds.contains(drive.deviceIdentifier),
                            sizeText: Self.byteFormatter.string(fromByteCount: drive.totalSizeBytes)
                        ) {
                            toggleDriveSelection(drive.deviceIdentifier)
                        }
                    }
                }
            }
        }
    }

    private func toggleDriveSelection(_ id: String) {
        if selectedUSBDeviceIds.contains(id) {
            selectedUSBDeviceIds.remove(id)
        } else {
            selectedUSBDeviceIds.insert(id)
        }
    }

    private var flashCTARow: some View {
        HStack(spacing: 12) {
            Text(flashCTAStatusHint)
                .font(WistFont.caption(11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                confirmFlash = true
            } label: {
                Label(flashCTALabel, systemImage: "bolt.fill")
                    .font(WistFont.headlineRounded(14))
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(WistCTAGradientButtonStyle(isEnabled: canFlash))
            .disabled(!canFlash)
        }
    }

    private var canFlash: Bool {
        guard !selectedUSBDeviceIds.isEmpty else { return false }
        guard !usbWriter.isWriting, !e2e.isActive else { return false }
        if useExistingISO {
            return existingISOURL != nil
        }
        guard downloadModel.selectedBuild != nil else { return false }
        guard downloadModel.details != nil, downloadModel.editions != nil else { return false }
        if !downloadModel.selectedLanguageCode.isEmpty && !downloadModel.selectedEditionToken.isEmpty {
            return true
        }
        return false
    }

    private var flashCTALabel: String {
        let count = selectedUSBDeviceIds.count
        if count <= 1 {
            return String(localized: "Flash")
        }
        return String(format: String(localized: "Flash (%lld drives)"), Int64(count))
    }

    private var flashCTAStatusHint: String {
        if selectedUSBDeviceIds.isEmpty {
            return String(localized: "Select at least one drive")
        }
        if useExistingISO, existingISOURL == nil {
            return String(localized: "Choose an ISO file")
        }
        if !useExistingISO, downloadModel.selectedBuild == nil {
            return String(localized: "Choose a Windows build")
        }
        if !useExistingISO, (downloadModel.details == nil || downloadModel.editions == nil) {
            return String(localized: "Load language and edition")
        }
        if !useExistingISO, downloadModel.selectedEditionToken.isEmpty {
            return String(localized: "Pick an edition")
        }
        return String(localized: "Ready")
    }

    private var eraseAlertMessage: String {
        let count = selectedUSBDeviceIds.count
        if count <= 1 {
            return String(localized: "FAT32 (WINSETUP) will be applied and the Windows installer will be written.")
        }
        return String(
            format: String(localized: "FAT32 (WINSETUP) will be applied to %lld drives in parallel."),
            Int64(count)
        )
    }

    // MARK: - Running

    private var runningSection: some View {
        FluffyStepProgressView(
            downloadModel: downloadModel,
            usbWriter: usbWriter,
            e2e: e2e,
            drives: resolvedSelectedDrives,
            isPresentingLog: $isPresentingFailureLog
        ) {
            copyFailureLogToPasteboard()
        }
    }

    @State private var isPresentingFailureLog = false
    @State private var isPresentingMacOSFailureLog = false

    /// macOS Home form: visible whenever we are not actively running and not showing the success “Done” card.
    private var shouldShowMacOSForm: Bool {
        if macOSE2E.isActive { return false }
        if case .completed = macOSE2E.phase { return false }
        return true
    }

    private func copyFailureLogToPasteboard() {
        let text = e2e.lastFailureLog ?? usbWriter.fullLogText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyMacOSFailureLogToPasteboard() {
        let text = macOSE2E.lastFailureLog ?? macOSUSBWriter.fullLogText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Done

    private var doneSection: some View {
        let style = FluffyUSBIconStyle.resolve(rawValue: usbIconStyleRaw)
        return VStack(spacing: 0) {
            VStack(spacing: 18) {
                ZStack {
                    FluffyCircularProgress(value: doneRingProgress, lineWidth: 14)
                        .frame(width: 168, height: 168)
                    Image(style.assetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 132, height: 132)
                        .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
                }
                Text(String(localized: "DONE"))
                    .font(WistFont.displayRounded(36))
                    .tracking(0.6)
                Text(e2e.statusLine.isEmpty ? String(localized: "Your USB drive is ready.") : e2e.statusLine)
                    .font(WistFont.body(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        e2e.reset()
                        doneRingProgress = 0
                    }
                } label: {
                    Label(String(localized: "Home"), systemImage: "house.fill")
                        .font(WistFont.headlineRounded(14))
                }
                .buttonStyle(WistCTAGradientButtonStyle(isEnabled: true))
                .frame(maxWidth: 220)
            }
            .padding(.vertical, 34)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FluffyColor.purpleGlow.opacity(0.20),
                                FluffyColor.elevated.opacity(0.65),
                                FluffyColor.surface.opacity(0.85),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: FluffyColor.purpleGlow.opacity(0.35), radius: 24, y: 10)
            }
        }
        .onAppear {
            doneRingProgress = 0
            withAnimation(.easeInOut(duration: 0.7)) {
                doneRingProgress = 1
            }
        }
    }

    // MARK: - Expert mode

    private var expertDisclosure: some View {
        MistSectionCard(title: String(localized: "Expert step-by-step"), systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Run each stage manually. Useful when only part of the pipeline is needed."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        Task { await downloadModel.downloadSelectedPackageToCache() }
                    } label: {
                        Label(String(localized: "1. Download UUP"), systemImage: "arrow.down.circle")
                    }
                    .disabled(!downloadModel.canStartUUPDownload || downloadModel.isDownloading)

                    Button {
                        guard let uuid = downloadModel.selectedBuild?.uuid else { return }
                        let dir = WistCache.uupRootDirectory.appendingPathComponent(uuid, isDirectory: true)
                        Task { await downloadModel.convertUUPFolderToISO(uupDirectory: dir) }
                    } label: {
                        Label(String(localized: "2. Build ISO"), systemImage: "opticaldisc")
                    }
                    .disabled(downloadModel.selectedBuild == nil || downloadModel.isConvertingUUP)

                    Button {
                        Task { await startWriteOnly() }
                    } label: {
                        Label(String(localized: "3. Write USB"), systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(!canWriteOnly)
                    Spacer()
                }

                if let err = downloadModel.lastError, !err.isEmpty {
                    Text(err).font(WistFont.caption(11)).foregroundStyle(.red)
                }
                if let err = downloadModel.convertLastError, !err.isEmpty {
                    Text(err).font(WistFont.caption(11)).foregroundStyle(.red)
                }
            }
        }
    }

    private var canWriteOnly: Bool {
        guard !selectedUSBDeviceIds.isEmpty else { return false }
        guard !usbWriter.isWriting, !e2e.isActive else { return false }
        if useExistingISO { return existingISOURL != nil }
        return downloadModel.lastProducedISOPath != nil
    }

    // MARK: - Actions

    private var resolvedSelectedDrives: [RemovableDriveInfo] {
        let order = diskManager.drives.map(\.deviceIdentifier)
        return order.compactMap { id in
            selectedUSBDeviceIds.contains(id) ? diskManager.drives.first { $0.deviceIdentifier == id } : nil
        }
    }

    private func startFlashFromForm() {
        let drives = resolvedSelectedDrives
        let conc = max(1, min(4, maxConcurrentWrites))
        if useExistingISO, let iso = existingISOURL {
            Task {
                await e2e.writeExistingISOToDrives(
                    isoURL: iso,
                    download: downloadModel,
                    usb: usbWriter,
                    drives: drives,
                    maxConcurrentUSBWrites: conc
                )
                recordHistoryAfterRun(drives: drives, isoPath: iso.path)
            }
        } else {
            Task {
                // Make the “1-click” flow actually 1-click: if the user picked a build but
                // hasn't expanded language/edition yet, fetch details automatically and
                // default to the first available options.
                if downloadModel.selectedBuild != nil, (downloadModel.details == nil || downloadModel.editions == nil) {
                    await downloadModel.loadDetailsAndEditionsForSelection()
                }
                if let details = downloadModel.details, downloadModel.selectedLanguageCode.isEmpty {
                    downloadModel.selectedLanguageCode = details.langList.first ?? ""
                }
                if let editions = downloadModel.editions, downloadModel.selectedEditionToken.isEmpty {
                    downloadModel.selectedEditionToken = editions.editionList.first ?? ""
                }
                await e2e.runFullPipeline(
                    download: downloadModel,
                    usb: usbWriter,
                    drives: drives,
                    maxConcurrentUSBWrites: conc
                )
                recordHistoryAfterRun(drives: drives, isoPath: downloadModel.lastProducedISOPath)
            }
        }
    }

    private func startUpgrade(offer: DriveUpgradeOffer) async {
        downloadModel.selectedBuildUUID = offer.latestBuild.uuid
        downloadModel.selectedLanguageCode = offer.currentMeta.language
        downloadModel.selectedEditionToken = offer.currentMeta.editionToken
        await downloadModel.loadDetailsAndEditionsForSelection()
        let drives = [offer.drive]
        let conc = max(1, min(4, maxConcurrentWrites))

        let cachedISO = lookupCachedISO(for: offer.latestBuild.uuid)
        if let cached = cachedISO {
            await e2e.writeExistingISOToDrives(
                isoURL: cached,
                download: downloadModel,
                usb: usbWriter,
                drives: drives,
                maxConcurrentUSBWrites: conc
            )
            recordHistoryAfterRun(drives: drives, isoPath: cached.path)
        } else {
            await e2e.runFullPipeline(
                download: downloadModel,
                usb: usbWriter,
                drives: drives,
                maxConcurrentUSBWrites: conc
            )
            recordHistoryAfterRun(drives: drives, isoPath: downloadModel.lastProducedISOPath)
        }
    }

    private func startWriteOnly() async {
        let drives = resolvedSelectedDrives
        let conc = max(1, min(4, maxConcurrentWrites))
        let path: URL?
        if useExistingISO {
            path = existingISOURL
        } else if let p = downloadModel.lastProducedISOPath {
            path = URL(fileURLWithPath: p)
        } else {
            path = nil
        }
        guard let url = path else { return }
        await e2e.writeExistingISOToDrives(
            isoURL: url,
            download: downloadModel,
            usb: usbWriter,
            drives: drives,
            maxConcurrentUSBWrites: conc
        )
        recordHistoryAfterRun(drives: drives, isoPath: url.path)
    }

    private func recordHistoryAfterRun(drives: [RemovableDriveInfo], isoPath: String?) {
        let succeeded: Bool
        var errorMessage: String?
        let fullLogText: String?
        switch e2e.phase {
        case .completed:
            succeeded = true
            fullLogText = nil
        case .failed(let m):
            succeeded = false
            errorMessage = m
            fullLogText = e2e.lastFailureLog ?? usbWriter.fullLogText
        default:
            return
        }
        let metadata = WistUSBMetadata(
            buildUuid: downloadModel.selectedBuild?.uuid ?? "",
            buildNumber: downloadModel.selectedBuild?.build ?? "",
            arch: downloadModel.selectedBuild?.arch ?? "",
            language: downloadModel.selectedLanguageCode,
            editionToken: downloadModel.selectedEditionToken,
            buildTitle: downloadModel.selectedBuild?.title,
            sourceIsoPath: isoPath
        )
        history.record(
            build: downloadModel.selectedBuild,
            metadata: metadata,
            drives: drives,
            isoPath: isoPath,
            succeeded: succeeded,
            errorMessage: errorMessage,
            fullLogText: fullLogText
        )
    }

    /// Best-effort lookup: scans UUP cache folders for an ISO whose parent folder matches the build UUID.
    private func lookupCachedISO(for uuid: String) -> URL? {
        let root = WistCache.uupRootDirectory
        let candidates = [
            root.appendingPathComponent(uuid, isDirectory: true),
            root.appendingPathComponent("\(uuid)-iso-build", isDirectory: true),
        ]
        let fm = FileManager.default
        for dir in candidates {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.lowercased().hasSuffix(".iso") {
                return dir.appendingPathComponent(name)
            }
        }
        return nil
    }

    // MARK: - macOS form (v1 skeleton)

    @State private var isPresentingMacOSList = false

    private var macosFormCard: some View {
        MistSectionCard(title: String(localized: "macOS"), systemImage: "apple.logo") {
            VStack(alignment: .leading, spacing: 14) {
                Picker(selection: $macOSModel.sourceKind) {
                    ForEach(MacOSDownloadViewModel.SourceKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                } label: {
                    Text(String(localized: "Source"))
                }
                .pickerStyle(.segmented)
                .controlSize(.large)

                HStack(spacing: 12) {
                    Toggle(String(localized: "Include betas"), isOn: $macOSModel.includeBetas)
                        .toggleStyle(.switch)
                    Spacer()
                    if macOSModel.sourceKind == .installer {
                        Picker(String(localized: "Catalog"), selection: $macOSModel.selectedCatalog) {
                            Text(String(localized: "Standard")).tag(MistCLITool.Catalog.standard)
                            Text(String(localized: "Customer Seed")).tag(MistCLITool.Catalog.customerSeed)
                            Text(String(localized: "Developer Seed")).tag(MistCLITool.Catalog.developerSeed)
                            Text(String(localized: "Public Seed")).tag(MistCLITool.Catalog.publicSeed)
                        }
                        .labelsHidden()
                    }
                }

                macOSSelectedReleaseSummary

                HStack(spacing: 10) {
                    Button {
                        isPresentingMacOSList = true
                    } label: {
                        Label(String(localized: "Choose…"), systemImage: "checkmark.circle")
                    }
                    .disabled(macOSModel.sourceKind == .local)

                    Button {
                        Task { await macOSModel.refreshList() }
                    } label: {
                        Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(macOSModel.isLoadingList || macOSModel.sourceKind == .local)

                    Spacer()

                    if macOSModel.isLoadingList {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let err = macOSModel.lastError, !err.isEmpty {
                    Text(err)
                        .font(WistFont.caption(11))
                        .foregroundStyle(.red)
                }

                driveListRow

                HStack(spacing: 12) {
                    Text(macosCTAStatusHint)
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        confirmMacOSFlash = true
                    } label: {
                        Label(String(localized: "Download & Create USB"), systemImage: "bolt.fill")
                            .font(WistFont.headlineRounded(14))
                    }
                    .buttonStyle(WistCTAGradientButtonStyle(isEnabled: canStartMacOSFlash))
                    .disabled(!canStartMacOSFlash)
                }
            }
        }
        .sheet(isPresented: $isPresentingMacOSList) {
            MacOSBrowseSheet(model: macOSModel, isPresented: $isPresentingMacOSList)
        }
        .alert(String(localized: "Erase and create macOS USB?"), isPresented: $confirmMacOSFlash) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Erase and create"), role: .destructive) {
                Task { await startMacOSFlash() }
            }
        } message: {
            Text(String(localized: "The selected drive(s) will be erased and formatted as Mac OS Extended (Journaled), then the installer will be written."))
        }
    }

    @ViewBuilder
    private var macOSSelectedReleaseSummary: some View {
        switch macOSModel.sourceKind {
        case .installer:
            if let item = macOSModel.selectedInstaller {
                macOSInstallerPickSummaryRow(item: item) {
                    isPresentingMacOSList = true
                }
            } else {
                Text(String(localized: "The catalog loads in the background. Tap Choose to pick an installer."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .firmware:
            if let item = macOSModel.selectedFirmware {
                macOSFirmwarePickSummaryRow(item: item) {
                    isPresentingMacOSList = true
                }
            } else {
                Text(String(localized: "The firmware list loads in the background. Tap Choose to pick an IPSW."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .local:
            EmptyView()
        }
    }

    private func macOSInstallerPickSummaryRow(item: MistCLITool.InstallerListItem, onChange: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FluffyColor.purple.opacity(0.2))
                Image(systemName: "apple.logo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.name) \(item.version)")
                    .font(WistFont.headline(14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(String(localized: "Build \(item.build)"))
                    .font(WistFont.caption(11).monospacedDigit())
                    .foregroundStyle(.secondary)
                if let bytes = item.sizeBytes {
                    Text(Self.byteFormatter.string(fromByteCount: bytes))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onChange) {
                Text(String(localized: "Change"))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func macOSFirmwarePickSummaryRow(item: MistCLITool.FirmwareListItem, onChange: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FluffyColor.purple.opacity(0.2))
                Image(systemName: "ipad.and.iphone")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.name) \(item.version)")
                    .font(WistFont.headline(14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(String(localized: "Build \(item.build)"))
                    .font(WistFont.caption(11).monospacedDigit())
                    .foregroundStyle(.secondary)
                if let bytes = item.sizeBytes {
                    Text(Self.byteFormatter.string(fromByteCount: bytes))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onChange) {
                Text(String(localized: "Change"))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    @State private var confirmMacOSFlash = false

    private var canStartMacOSFlash: Bool {
        guard !selectedUSBDeviceIds.isEmpty else { return false }
        guard !macOSE2E.isActive, !macOSUSBWriter.isWriting else { return false }
        guard macOSModel.sourceKind == .installer else { return false }
        guard let installer = macOSModel.selectedInstaller else { return false }
        return !installer.build.isEmpty
    }

    private var macosCTAStatusHint: String {
        if selectedUSBDeviceIds.isEmpty { return String(localized: "Select at least one drive") }
        if macOSModel.sourceKind != .installer { return String(localized: "Select Installer source") }
        if macOSModel.selectedInstaller == nil { return String(localized: "Choose an installer") }
        return String(localized: "Ready")
    }

    private func startMacOSFlash() async {
        let drives = resolvedSelectedDrives
        guard let installer = macOSModel.selectedInstaller else { return }
        let types = Array(macOSModel.installerOutputTypes)
        await macOSE2E.runInstallerToUSB(
            buildOrNameSearch: installer.build,
            outputTypes: types,
            outputDirectory: MacOSCache.rootDirectory,
            expectedDownloadBytes: installer.sizeBytes,
            drives: drives,
            usbWriter: macOSUSBWriter,
            catalog: macOSModel.selectedCatalog,
            includeBetas: macOSModel.includeBetas,
            forceOverwrite: true,
            logSink: { _ in }
        )
    }

    private func macosFailedSection(message: String) -> some View {
        MistSectionCard(title: String(localized: "Something went wrong"), systemImage: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(WistFont.body(12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button {
                        isPresentingMacOSFailureLog = true
                    } label: {
                        Label(String(localized: "View log"), systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            macOSE2E.reset()
                        }
                    } label: {
                        Label(String(localized: "Dismiss"), systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var macosRunningSection: some View {
        MistSectionCard(title: String(localized: "Running"), systemImage: "hourglass") {
            VStack(alignment: .leading, spacing: 10) {
                Text(macOSE2E.statusLine.isEmpty ? String(localized: "Working…") : macOSE2E.statusLine)
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
                if let st = macOSE2E.downloadStatusLine, !st.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(st)
                            .font(WistFont.caption(10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let eta = macOSE2E.downloadEtaFormatted {
                            Text(eta)
                                .font(WistFont.caption(10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                FluffyRopeProgressBar(value: macOSE2E.downloadProgress.map { CGFloat($0) }, label: nil, compactVertical: false)
            }
        }
    }

    private var macosDoneSection: some View {
        MistSectionCard(title: String(localized: "Done"), systemImage: "checkmark.seal.fill") {
            Text(macOSE2E.statusLine.isEmpty ? String(localized: "Your macOS USB is ready.") : macOSE2E.statusLine)
                .font(WistFont.body(12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - macOS browse sheet (v1)

private struct MacOSBrowseSheet: View {
    @ObservedObject var model: MacOSDownloadViewModel
    @Binding var isPresented: Bool

    private var sheetTitle: String {
        switch model.sourceKind {
        case .installer:
            return String(localized: "Choose macOS")
        case .firmware:
            return String(localized: "Choose firmware")
        case .local:
            return String(localized: "Catalog")
        }
    }

    var body: some View {
        FluffySheetChrome {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(sheetTitle)
                        .font(WistFont.title(16))
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Label(String(localized: "Close"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().opacity(0.35)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch model.sourceKind {
                        case .installer:
                            if model.isLoadingList {
                                loadingRow
                            } else if model.installers.isEmpty {
                                emptyListMessage(
                                    fallback: String(localized: "No installers in this catalog yet. Try Refresh or another seed catalog.")
                                )
                            } else {
                                ForEach(model.installers, id: \.self) { item in
                                    row(
                                        title: "\(item.name) \(item.version)",
                                        subtitle: item.build,
                                        isSelected: model.selectedInstaller?.build == item.build
                                    ) {
                                        model.selectedInstaller = item
                                    }
                                }
                            }
                        case .firmware:
                            if model.isLoadingList {
                                loadingRow
                            } else if model.firmwares.isEmpty {
                                emptyListMessage(
                                    fallback: String(localized: "No firmware files in the list yet. Try Refresh.")
                                )
                            } else {
                                ForEach(model.firmwares, id: \.self) { item in
                                    row(
                                        title: "\(item.name) \(item.version)",
                                        subtitle: item.build,
                                        isSelected: model.selectedFirmware?.build == item.build
                                    ) {
                                        model.selectedFirmware = item
                                    }
                                }
                            }
                        case .local:
                            Text(String(localized: "Local file mode has no catalog list."))
                                .font(WistFont.caption(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
                .frame(minHeight: 420)
            }
            .fluffyPillow(cornerRadius: 22)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 640)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(String(localized: "Loading catalog…"))
                .font(WistFont.caption(12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func emptyListMessage(fallback: String) -> some View {
        if let err = model.lastError, !err.isEmpty {
            Text(err)
                .font(WistFont.caption(11))
                .foregroundStyle(.red)
        } else {
            Text(fallback)
                .font(WistFont.caption(11))
                .foregroundStyle(.secondary)
        }
    }

    private func row(title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(WistFont.headline(13))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(WistFont.caption(10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FluffyColor.purpleGlow)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? FluffyColor.purple.opacity(0.22) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.14 : 0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fluffy drive row

/// Single drive row styled to match the fluffy design language: rounded soft
/// surface, accent stroke on selection, large tappable target. Replaces the
/// native `List` row look inside Home.
struct FluffyDriveRow: View {
    let drive: RemovableDriveInfo
    let isSelected: Bool
    let sizeText: String
    let onTap: () -> Void

    @State private var isHovered = false
    @AppStorage(FluffyUSBIconStyle.appStorageKey) private var iconStyleRaw: String = FluffyUSBIconStyle.defaultStyle.rawValue

    private var iconStyle: FluffyUSBIconStyle {
        FluffyUSBIconStyle.resolve(rawValue: iconStyleRaw)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                Image(iconStyle.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.black.opacity(0.35), radius: 5, y: 2)
                    .opacity(isSelected ? 1.0 : 0.95)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(drive.mediaName)
                            .font(WistFont.headline(13))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if drive.wistSidecarMeta != nil {
                            Text(String(localized: "Fluffy"))
                                .font(WistFont.caption(9))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(FluffyColor.purpleGlow.opacity(0.28))
                                )
                                .overlay(
                                    Capsule().strokeBorder(FluffyColor.purpleGlow.opacity(0.55), lineWidth: 0.5)
                                )
                                .foregroundStyle(Color.white.opacity(0.95))
                        }
                    }
                    Text("/dev/\(drive.deviceIdentifier)")
                        .font(WistFont.caption(10).monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let meta = drive.wistSidecarMeta {
                        Text("\(meta.buildNumber) · \(meta.language) · \(meta.arch) · \(meta.editionToken)")
                            .font(WistFont.caption(10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(sizeText)
                    .font(WistFont.caption(11).monospacedDigit())
                    .foregroundStyle(.secondary)

                selectionIndicator
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(rowBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(rowStroke, lineWidth: isSelected ? 1.4 : 1.0)
            }
            .shadow(
                color: isSelected
                    ? FluffyColor.purpleGlow.opacity(0.35)
                    : Color.black.opacity(0.22),
                radius: isSelected ? 10 : 6,
                y: isSelected ? 3 : 2
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionIndicator: some View {
        Image(isSelected ? "FluffyRadioOn" : "FluffyRadioOff")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 28, height: 28)
            .shadow(color: Color.black.opacity(0.22), radius: 3, y: 1)
            .accessibilityHidden(true)
    }

    private var rowBackground: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [
                    FluffyColor.purple.opacity(0.25),
                    FluffyColor.elevated.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isHovered {
            return LinearGradient(
                colors: [
                    FluffyColor.surface.opacity(0.98),
                    FluffyColor.elevated.opacity(0.9),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                FluffyColor.surface.opacity(0.88),
                FluffyColor.elevated.opacity(0.82),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var rowStroke: Color {
        if isSelected {
            return FluffyColor.purpleGlow.opacity(0.85)
        }
        return Color.white.opacity(isHovered ? 0.12 : 0.07)
    }
}

// MARK: - Fluffy sheet chrome

/// Wraps a sheet with the same fluffy surface/backdrop used across the app so
/// modals feel part of the product instead of plain `NSPanel`s.
struct FluffySheetChrome<Content: View>: View {
    var cornerRadius: CGFloat = 22
    let content: () -> Content

    var body: some View {
        ZStack {
            WistShellWindowBackdrop()
                .ignoresSafeArea()
            content()
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Build picker sheet

private struct FluffyBuildPickerSheet: View {
    @ObservedObject var model: DownloadISOViewModel
    @Binding var isPresented: Bool

    var body: some View {
        FluffySheetChrome {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                Divider().opacity(0.35)

                filtersBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                Divider().opacity(0.35)

                buildsList

                Divider().opacity(0.35)

                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .fluffyPillow(cornerRadius: 22)
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 600, idealHeight: 640)
        .task {
            if model.allBuilds.isEmpty && !model.isLoadingBuilds {
                await model.loadBuilds()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "CATALOG").uppercased())
                    .font(WistFont.eyebrow(10))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)
                Text(String(localized: "Choose a Windows build"))
                    .font(WistFont.title(18))
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Label(String(localized: "Close"), systemImage: "xmark")
                    .font(WistFont.caption(11).weight(.medium))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var filtersBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12, weight: .semibold))
                TextField(
                    String(localized: "Search by name, build, UUID…"),
                    text: $model.filterSearch
                )
                .textFieldStyle(.plain)
                .font(WistFont.body(13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .frame(maxWidth: .infinity)

            Picker(String(localized: "Product"), selection: $model.filterProduct) {
                ForEach(UUPProductFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 160)

            Picker(String(localized: "Channel"), selection: $model.filterChannel) {
                ForEach(UUPChannelFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)

            Picker(String(localized: "Architecture"), selection: $model.filterArch) {
                ForEach(UUPArchFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }

    @ViewBuilder
    private var buildsList: some View {
        if model.isLoadingBuilds && model.displayedBuilds.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(String(localized: "Loading catalog…"))
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.displayedBuilds.isEmpty {
            MistEmptyState(
                systemImage: "square.stack.3d.up.slash",
                title: String(localized: "No builds match your filters"),
                message: String(localized: "Clear the filters or try another search term.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.horizontal, 20)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.displayedBuilds, id: \.uuid) { build in
                        FluffyBuildRow(
                            build: build,
                            isSelected: model.selectedBuildUUID == build.uuid
                        ) {
                            model.selectedBuildUUID = build.uuid
                        } onDouble: {
                            model.selectedBuildUUID = build.uuid
                            Task { await confirmSelection() }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(minHeight: 320, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let err = model.lastError, !err.isEmpty {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(WistFont.caption(11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Task { await model.loadBuilds() }
            } label: {
                Label(String(localized: "Refresh catalog"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoadingBuilds)

            Button {
                Task { await confirmSelection() }
            } label: {
                Label(String(localized: "Use this build"), systemImage: "checkmark.circle.fill")
                    .font(WistFont.headlineRounded(13))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(WistCTAGradientButtonStyle(isEnabled: model.selectedBuildUUID != nil))
            .disabled(model.selectedBuildUUID == nil)
        }
    }

    private func confirmSelection() async {
        await model.loadDetailsAndEditionsForSelection()
        isPresented = false
    }
}

// MARK: - Build row inside the fluffy picker

private struct FluffyBuildRow: View {
    let build: UUPBuilds.Build
    let isSelected: Bool
    let onSelect: () -> Void
    let onDouble: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(build.title)
                        .font(WistFont.headline(13))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(build.build)
                            .font(WistFont.caption(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(build.arch)
                            .font(WistFont.caption(11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if build.uupIsInsiderStyleChannel {
                    Text(String(localized: "Insider"))
                        .font(WistFont.caption(10).weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(FluffyColor.orange.opacity(0.22))
                        )
                        .overlay(
                            Capsule().strokeBorder(FluffyColor.orange.opacity(0.55), lineWidth: 0.5)
                        )
                        .foregroundStyle(FluffyColor.orangeHi)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(rowStroke, lineWidth: isSelected ? 1.3 : 0.9)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onDouble() }
        )
    }

    private var rowBackground: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [
                    FluffyColor.purple.opacity(0.28),
                    FluffyColor.elevated.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isHovered {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.02),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color.clear, Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var rowStroke: Color {
        if isSelected {
            return FluffyColor.purpleGlow.opacity(0.85)
        }
        return Color.white.opacity(isHovered ? 0.1 : 0.04)
    }
}

// MARK: - Failure log sheet

private struct FluffyFailureLogSheet: View {
    let title: String
    let text: String
    let onCopy: () -> Void

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
                        onCopy()
                    } label: {
                        Label(String(localized: "Copy error"), systemImage: "doc.on.doc")
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
