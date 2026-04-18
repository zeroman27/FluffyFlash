//
//  DownloadsView.swift
//  Wist
//

import AppKit
import SwiftUI

/// Active UUP download, cache folders, and `.iso` conversion via bundled `convert.sh`.
struct DownloadsView: View {
    @ObservedObject var downloadISOViewModel: DownloadISOViewModel
    @State private var cacheFolders: [UUPCacheFolder] = []

    var body: some View {
        MistDetailCanvas {
            VStack(alignment: .leading, spacing: 0) {
                MistPageHeader(
                    eyebrow: String(localized: "Status"),
                    title: String(localized: "Downloads"),
                    subtitle: String(format: String(localized: "UUP progress, cache folders, and ISO conversion. Folder: %@"), WistCache.uupRootDirectory.path),
                    symbolName: "arrow.down.doc"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        activeDownloadSection
                        convertProgressSection
                        languageAndEditionSection
                        cacheSection
                        uupToIsoHelpSection
                    }
                    .padding(WistTheme.pagePadding)
                }
            }
        }
        .onAppear { refreshCache() }
        .onChange(of: downloadISOViewModel.lastProducedISOPath) { _, _ in
            refreshCache()
        }
        .task {
            if downloadISOViewModel.allBuilds.isEmpty {
                await downloadISOViewModel.loadBuilds()
                refreshCache()
            }
        }
    }

    private var languageAndEditionSection: some View {
        MistSectionCard(title: String(localized: "Windows language & edition"), systemImage: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                if downloadISOViewModel.details != nil {
                    HStack {
                        Text(String(localized: "Language"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(languageDisplay)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(WistFont.body(12))
                    HStack {
                        Text(String(localized: "Edition"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(editionDisplay)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(WistFont.body(12))
                } else {
                    Text(String(localized: "Load Languages & editions on Download ISO so the app can show friendly names here and in the cache list."))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "These settings apply to new UUP downloads and metadata written into each cache folder. Change them on Download ISO → Parameters (after tapping Languages & editions)."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var languageDisplay: String {
        let code = downloadISOViewModel.selectedLanguageCode
        if code.isEmpty { return String(localized: "—") }
        if let d = downloadISOViewModel.details, let fancy = d.langFancyNames[code] {
            return "\(fancy) (\(code))"
        }
        return code
    }

    private var editionDisplay: String {
        let token = downloadISOViewModel.selectedEditionToken
        if token.isEmpty { return String(localized: "—") }
        if let editions = downloadISOViewModel.editions, let fancy = editions.editionFancyNames[token] {
            return fancy
        }
        return token
    }

    @ViewBuilder
    private var activeDownloadSection: some View {
        MistSectionCard(title: String(localized: "Current UUP download"), systemImage: "arrow.down.circle") {
            if downloadISOViewModel.isDownloading {
                VStack(alignment: .leading, spacing: 12) {
                    if let p = downloadISOViewModel.downloadProgress {
                        MistProProgressBar(
                            value: p,
                            label: downloadISOViewModel.downloadStatus ?? String(localized: "Downloading…")
                        )
                    } else {
                        MistProProgressIndeterminate(label: downloadISOViewModel.downloadStatus ?? String(localized: "Downloading…"))
                    }
                    HStack {
                        Spacer(minLength: 0)
                        Button(String(localized: "Stop"), role: .cancel) {
                            downloadISOViewModel.cancelActiveDownload()
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: WistMotion.quick), value: downloadISOViewModel.isDownloading)
            } else if let st = downloadISOViewModel.downloadStatus, !st.isEmpty {
                Text(st)
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                MistEmptyState(
                    systemImage: "tray",
                    title: String(localized: "No active download"),
                    message: String(localized: "Start a download on Download ISO — progress appears here.")
                )
            }
            if let err = downloadISOViewModel.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(WistFont.caption(11))
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var convertProgressSection: some View {
        if downloadISOViewModel.isConvertingUUP {
            MistSectionCard(title: String(localized: "ISO build"), systemImage: "opticaldisc") {
                VStack(alignment: .leading, spacing: 10) {
                    MistProProgressIndeterminate(label: String(localized: "Building image…"))
                    if let line = downloadISOViewModel.convertStatusLine {
                        Text(line)
                            .font(WistFont.caption(11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    ScrollView {
                        Text(downloadISOViewModel.convertLogLines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                }
            }
        } else if !downloadISOViewModel.convertLogLines.isEmpty, downloadISOViewModel.lastProducedISOPath != nil {
            MistSectionCard(title: String(localized: "Last ISO build"), systemImage: "checkmark.circle") {
                ScrollView {
                    Text(downloadISOViewModel.convertLogLines.suffix(24).joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 100)
            }
        }
    }

    private var cacheSection: some View {
        MistSectionCard(title: String(localized: "UUP cache"), systemImage: "folder") {
            HStack {
                Button {
                    refreshCache()
                } label: {
                    Label(String(localized: "Refresh list"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(.bottom, 8)

            if cacheFolders.isEmpty {
                MistEmptyState(
                    systemImage: "folder.badge.questionmark",
                    title: String(localized: "No folders yet"),
                    message: String(localized: "After a UUP download finishes, folders appear here — you can build an ISO from them.")
                )
            } else {
                Table(cacheFolders) {
                    TableColumn(String(localized: "Build")) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cachePrimaryTitle(for: row))
                                .font(WistFont.body(12))
                            Text(cacheSubtitle(for: row))
                                .font(WistFont.caption(10))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                    TableColumn(String(localized: "Size")) { row in
                        Text(ByteCountFormatter.string(fromByteCount: row.totalBytes, countStyle: .file))
                            .font(WistFont.caption(11))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn(String(localized: "Actions")) { row in
                        HStack(spacing: 8) {
                            Button(String(localized: "Build ISO")) {
                                Task { await downloadISOViewModel.convertUUPFolderToISO(uupDirectory: row.url) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(downloadISOViewModel.isConvertingUUP || downloadISOViewModel.isDownloading)
                            Button(String(localized: "Finder")) { revealInFinder(row.url) }
                            Button(String(localized: "Delete"), role: .destructive) { deleteFolder(row.url) }
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }

    private var uupToIsoHelpSection: some View {
        MistSectionCard(title: String(localized: "Build .iso from UUP"), systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 12) {
                if BundledToolLocator.hasEmbeddedUUPToolchain {
                    Label(
                        String(localized: "Embedded toolchain found — Homebrew is not required for conversion."),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        String(localized: "The converter script ships with the app; CLI tools are still required at runtime. Release builds bundle them under Resources/Tools/bin. When building from source, run Scripts/bundle-mac-cli-tools.sh (Homebrew on the dev machine) or install packages manually:")
                    )
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
                    Text(
                        "brew install aria2 cabextract wimlib cdrtools\n" +
                        "brew tap minacle/chntpw && brew install minacle/chntpw/chntpw"
                    )
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                }
                if let p = downloadISOViewModel.lastProducedISOPath {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p)
                            .font(WistFont.caption(11))
                            .textSelection(.enabled)
                            .lineLimit(3)
                        Spacer()
                        Button(String(localized: "Reveal ISO in Finder")) {
                            let parent = (p as NSString).deletingLastPathComponent
                            NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: parent)
                        }
                    }
                }
                if let cErr = downloadISOViewModel.convertLastError {
                    Text(cErr)
                        .foregroundStyle(.red)
                        .font(WistFont.caption(11))
                        .textSelection(.enabled)
                }
                if let url = URL(string: "https://git.uupdump.net/uup-dump/converter") {
                    Link(destination: url) {
                        Label(String(localized: "Converter sources (uup-dump)"), systemImage: "link")
                    }
                    .font(WistFont.body(12))
                }
            }
        }
    }

    private func refreshCache() {
        cacheFolders = WistCache.listUUPFolders()
    }

    private func cachePrimaryTitle(for folder: UUPCacheFolder) -> String {
        if let m = folder.cachedMetadata {
            return m.title
        }
        let key = folder.uupLookupKey
        if let b = downloadISOViewModel.allBuilds.first(where: { $0.uuid == key }) {
            return b.title
        }
        if folder.name.hasSuffix("-iso-build") {
            return String(localized: "ISO build output")
        }
        return String(localized: "UUP cache")
    }

    private func cacheSubtitle(for folder: UUPCacheFolder) -> String {
        if let m = folder.cachedMetadata {
            var parts: [String] = [
                String(format: String(localized: "Build %@"), m.buildNumber),
                m.arch,
            ]
            if let c = m.created {
                parts.append(formattedCatalogDate(c))
            }
            if !m.languageCode.isEmpty {
                parts.append(m.languageCode)
            }
            if !m.editionToken.isEmpty {
                parts.append(m.editionToken)
            }
            return parts.joined(separator: " · ")
        }
        let key = folder.uupLookupKey
        if let b = downloadISOViewModel.allBuilds.first(where: { $0.uuid == key }) {
            var parts: [String] = [
                String(format: String(localized: "Build %@"), b.build),
                b.arch,
            ]
            if let c = b.created {
                parts.append(formattedCatalogDate(c))
            }
            return parts.joined(separator: " · ")
        }
        if folder.name.hasSuffix("-iso-build") {
            return String(localized: "Converter output · \(key)")
        }
        return key
    }

    private func formattedCatalogDate(_ created: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(created))
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    private func deleteFolder(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshCache()
    }
}

private extension UUPCacheFolder {
    /// UUP build id: strips `-iso-build` output suffix for catalog / sidecar lookup.
    var uupLookupKey: String {
        let suffix = "-iso-build"
        if name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}

#Preview {
    DownloadsView(downloadISOViewModel: DownloadISOViewModel())
        .frame(width: 760, height: 620)
}
