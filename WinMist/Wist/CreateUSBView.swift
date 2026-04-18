//
//  CreateUSBView.swift
//  Wist
//

import SwiftUI
import UniformTypeIdentifiers

/// ISO + USB selection, erase confirmation, write log.
struct CreateUSBView: View {
    @ObservedObject var diskManager: DiskManager
    @ObservedObject var usbWriter: USBWriterViewModel
    @ObservedObject var downloadModel: DownloadISOViewModel
    @ObservedObject var e2e: EndToEndMediaPipeline
    @Binding var selectedDeviceIds: Set<String>

    @State private var selectedISOURL: URL?
    @State private var isoPickerPresented = false
    @State private var confirmErase = false
    @State private var confirmUpdateDrive: RemovableDriveInfo?
    @State private var logCopiedNotice = false

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
                    eyebrow: String(localized: "Write"),
                    title: String(localized: "Create USB"),
                    subtitle: String(localized: "Bootable media for UEFI PCs: ISO, one or more removable drives, erase confirmation."),
                    symbolName: "externaldrive"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        MistPipelineNumbered(
                            titles: [
                                String(localized: "ISO image"),
                                String(localized: "USB drives"),
                                String(localized: "Write"),
                            ],
                            activeIndex: usbPipelineActiveIndex
                        )

                        wistSidecarDetectedSection

                        MistWarningCallout(
                            title: String(localized: "Data on selected USB drives will be erased"),
                            message: String(localized: "Each drive is formatted as FAT32 (volume label WINSETUP) and receives the Windows installer. Requires install.wim or install.esd and wimlib-imagex (brew install wimlib).")
                        )

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: WistTheme.gutter) {
                                isoRow.frame(maxWidth: .infinity, alignment: .leading)
                                driveSection.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: WistTheme.gutter) {
                                isoRow
                                driveSection
                            }
                        }

                        actionsRow
                        logSection
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
            switch result {
            case .success(let urls):
                selectedISOURL = urls.first
            case .failure(let error):
                usbWriter.lastError = error.localizedDescription
            }
        }
        .alert(String(localized: "Erase and write?"), isPresented: $confirmErase) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Erase and write"), role: .destructive) {
                guard let iso = selectedISOURL else { return }
                Task { await runManualWrites(iso: iso) }
            }
        } message: {
            Text(eraseAlertMessage)
        }
        .alert(String(localized: "Update this drive?"), isPresented: Binding(
            get: { confirmUpdateDrive != nil },
            set: { if !$0 { confirmUpdateDrive = nil } }
        )) {
            Button(String(localized: "Cancel"), role: .cancel) { confirmUpdateDrive = nil }
            Button(String(localized: "Erase and update"), role: .destructive) {
                if let d = confirmUpdateDrive {
                    Task { await runUpdateFlow(for: d) }
                }
                confirmUpdateDrive = nil
            }
        } message: {
            Text(String(localized: "The drive will be formatted and written using the build selected in the app."))
        }
    }

    private var eraseAlertMessage: String {
        let n = selectedDeviceIds.count
        if n <= 1 {
            return String(localized: "FAT32 (WINSETUP) will be applied and Windows setup files will be written.")
        }
        return String(format: String(localized: "FAT32 (WINSETUP) will be applied to %lld drives, one after another."), Int64(n))
    }

    private var usbPipelineActiveIndex: Int {
        if selectedISOURL == nil { return 0 }
        if selectedDeviceIds.isEmpty { return 1 }
        return 2
    }

    private var orderedSelectedDrives: [RemovableDriveInfo] {
        let order = diskManager.drives.map(\.deviceIdentifier)
        return order.compactMap { id in
            selectedDeviceIds.contains(id) ? diskManager.drives.first { $0.deviceIdentifier == id } : nil
        }
    }

    @ViewBuilder
    private var wistSidecarDetectedSection: some View {
        let withMeta = diskManager.drives.filter { $0.wistSidecarMeta != nil }
        if !withMeta.isEmpty {
            MistSectionCard(title: String(localized: "Wist drives"), systemImage: "externaldrive.badge.checkmark") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: String(localized: "Found %@ on a mounted volume. Build detection without this file is not guaranteed."), WistUSBMetadata.fileName))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)

                    ForEach(withMeta) { drive in
                        if let meta = drive.wistSidecarMeta {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(drive.mediaName)
                                            .font(WistFont.headline(13))
                                        Text("\(String(localized: "Build")) \(meta.buildNumber) · \(meta.arch) · \(meta.language)")
                                            .font(WistFont.caption(10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(String(localized: "Update to selected build")) {
                                        confirmUpdateDrive = drive
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .disabled(e2e.isActive || usbWriter.isWriting || downloadModel.isDownloading || downloadModel.isConvertingUUP)
                                }
                            }
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            }
                        }
                    }
                }
            }
        }
    }

    private var isoRow: some View {
        MistSectionCard(title: String(localized: "Windows image (.iso)"), systemImage: "opticaldisc") {
            if let u = selectedISOURL {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(u.lastPathComponent)
                            .font(WistFont.headline(13))
                            .lineLimit(2)
                        Text(u.deletingLastPathComponent().path)
                            .font(WistFont.caption(10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button(String(localized: "Other file…")) { isoPickerPresented = true }
                        .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    MistEmptyState(
                        systemImage: "doc.badge.plus",
                        title: String(localized: "No ISO selected"),
                        message: String(localized: "Choose an installer image with a sources folder and install.wim or install.esd. For Run all, the ISO is built automatically.")
                    )
                    Button(String(localized: "Choose ISO…")) { isoPickerPresented = true }
                        .keyboardShortcut("o", modifiers: [.command])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var driveSection: some View {
        MistSectionCard(title: String(localized: "USB drives"), systemImage: "externaldrive") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await diskManager.refresh() }
                    } label: {
                        Label(String(localized: "Refresh list"), systemImage: "arrow.clockwise")
                    }
                    .disabled(diskManager.isRefreshing || usbWriter.isWriting)
                    if diskManager.isRefreshing {
                        MistProProgressIndeterminate(height: 4, label: nil)
                            .frame(maxWidth: 160, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    if !selectedDeviceIds.isEmpty {
                        Text(String(format: String(localized: "Selected: %lld"), Int64(selectedDeviceIds.count)))
                            .font(WistFont.caption(10))
                            .foregroundStyle(.secondary)
                    }
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
                        message: String(localized: "Connect a USB drive and tap Refresh list. Internal disks are hidden.")
                    )
                } else {
                    List(selection: $selectedDeviceIds) {
                        ForEach(diskManager.drives) { drive in
                            HStack {
                                Image(systemName: "externaldrive")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(drive.mediaName)
                                        .font(WistFont.body(13))
                                    Text("/dev/\(drive.deviceIdentifier)")
                                        .font(WistFont.caption(10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Self.byteFormatter.string(fromByteCount: drive.totalSizeBytes))
                                    .font(WistFont.caption(10))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(drive.deviceIdentifier)
                        }
                    }
                    .frame(minHeight: 180)
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        }
    }

    private var actionsRow: some View {
        MistSectionCard(title: String(localized: "Action (ISO only)"), systemImage: "hammer") {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Writes the selected ISO to the selected drives. The UUP → ISO → USB chain is started with Run all at the bottom."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        confirmErase = true
                    } label: {
                        Label(String(localized: "Write ISO to USB…"), systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!canStartManual || usbWriter.isWriting || e2e.isActive)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(String(localized: "Clear log")) {
                        usbWriter.clearLog()
                    }
                    .disabled(usbWriter.isWriting)

                    Spacer(minLength: 0)
                }

                if usbWriter.isWriting {
                    MistProProgressIndeterminate(label: String(localized: "Writing to USB…"))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let err = usbWriter.lastError {
                    Text(err)
                        .font(WistFont.body(12))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .animation(.easeInOut(duration: WistMotion.quick), value: usbWriter.isWriting)
        }
    }

    private var canStartManual: Bool {
        selectedISOURL != nil && !selectedDeviceIds.isEmpty
    }

    private var logSection: some View {
        MistSectionCard(title: String(localized: "Log"), systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        usbWriter.copyLogToPasteboard()
                        logCopiedNotice = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run { logCopiedNotice = false }
                        }
                    } label: {
                        Label(String(localized: "Copy log"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(usbWriter.logLines.isEmpty)
                    if logCopiedNotice {
                        Text(String(localized: "Copied"))
                            .font(WistFont.caption(10))
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                ScrollView {
                    Text(usbWriter.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 160, maxHeight: 280)
            }
        }
    }

    private func runManualWrites(iso: URL) async {
        let access = iso.startAccessingSecurityScopedResource()
        defer {
            if access {
                iso.stopAccessingSecurityScopedResource()
            }
        }
        let metadata = manualMetadata(isoPath: iso.path)
        for drive in orderedSelectedDrives {
            let err = await usbWriter.writeWindowsInstaller(isoURL: iso, drive: drive, metadata: metadata)
            if err != nil { break }
        }
    }

    private func manualMetadata(isoPath: String) -> WistUSBMetadata? {
        guard let build = downloadModel.selectedBuild else { return nil }
        return WistUSBMetadata(
            buildUuid: build.uuid,
            buildNumber: build.build,
            arch: build.arch,
            language: downloadModel.selectedLanguageCode,
            editionToken: downloadModel.selectedEditionToken,
            buildTitle: build.title,
            sourceIsoPath: isoPath
        )
    }

    private func runUpdateFlow(for drive: RemovableDriveInfo) async {
        if let path = downloadModel.lastProducedISOPath {
            let url = URL(fileURLWithPath: path)
            await e2e.writeExistingISOToDrives(
                isoURL: url,
                download: downloadModel,
                usb: usbWriter,
                drives: [drive]
            )
        } else {
            await e2e.runFullPipeline(
                download: downloadModel,
                usb: usbWriter,
                drives: [drive]
            )
        }
    }
}

#Preview {
    @Previewable @State var ids: Set<String> = []
    return CreateUSBView(
        diskManager: DiskManager(),
        usbWriter: USBWriterViewModel(),
        downloadModel: DownloadISOViewModel(),
        e2e: EndToEndMediaPipeline(),
        selectedDeviceIds: $ids
    )
    .frame(width: 900, height: 780)
}
