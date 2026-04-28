//
//  DownloadISOViewModel.swift
//  Wist
//

import Combine
import Foundation

/// Orchestrates [UUPDump](https://uupdump.net) metadata, CrystalFetch’s `Downloader`, and the official UUP `convert.sh` (see `ThirdParty/UUPConverter`).
@MainActor
final class DownloadISOViewModel: ObservableObject {

    /// Raw list from API (minus generic “update” rows).
    @Published private(set) var allBuilds: [UUPBuilds.Build] = []

    // MARK: Filters (local)

    @Published var filterSearch: String = "" {
        didSet { scheduleSearchRecompute() }
    }

    @Published var filterProduct: UUPProductFilter = .all {
        didSet { if filterProduct != oldValue { recomputeDisplayedBuilds() } }
    }

    @Published var filterChannel: UUPChannelFilter = .all {
        didSet { if filterChannel != oldValue { recomputeDisplayedBuilds() } }
    }

    @Published var filterArch: UUPArchFilter = .all {
        didSet { if filterArch != oldValue { recomputeDisplayedBuilds() } }
    }

    /// Filtered + sorted list; recomputed when filters change (search is debounced). Avoids re-filtering the full catalog on every `ObservableObject` invalidation.
    @Published private(set) var displayedBuilds: [UUPBuilds.Build] = []

    /// Bumps when `displayedBuilds` changes so the Source screen can sync tentative selection without scanning filters on every keystroke.
    @Published private(set) var displayedBuildsGeneration: UInt = 0

    @Published private(set) var isLoadingBuilds = false
    @Published private(set) var isDownloading = false
    @Published var lastError: String?

    /// Bound to `List` selection (`uuid` of the build).
    @Published var selectedBuildUUID: String?

    var selectedBuild: UUPBuilds.Build? {
        guard let id = selectedBuildUUID else { return nil }
        return displayedBuilds.first { $0.uuid == id } ?? allBuilds.first { $0.uuid == id }
    }

    @Published private(set) var details: UUPDetails?
    @Published private(set) var editions: UUPEditions?
    @Published var selectedLanguageCode: String = "en-us"
    @Published var selectedEditionToken: String = ""

    @Published private(set) var downloadProgress: Double?
    @Published private(set) var downloadStatus: String?
    /// Bytes written / total for the active UUP download (for ETA + rich UI).
    @Published private(set) var downloadBytesWritten: Int64 = 0
    @Published private(set) var downloadBytesTotal: Int64 = 0
    /// Rough ETA from average throughput since download started (e.g. "~2 min left").
    @Published private(set) var downloadEtaFormatted: String?

    private var downloadProgressStartDate: Date?

    /// UUP → ISO (bundled `convert.sh`).
    @Published private(set) var isConvertingUUP = false
    @Published private(set) var convertStatusLine: String?
    @Published private(set) var convertLogLines: [String] = []
    @Published var convertLastError: String?
    @Published private(set) var lastProducedISOPath: String?

    private let api = UUPDumpAPI()
    private var activeDownloader: Downloader?
    private var searchDebounceWorkItem: DispatchWorkItem?

    init() {
        recomputeDisplayedBuilds()
    }

    // MARK: - Filter predicates

    private func passesProductFilter(_ build: UUPBuilds.Build) -> Bool {
        switch filterProduct {
        case .all: return true
        case .windows11: return build.uupProductLine == .windows11
        case .windows10: return build.uupProductLine == .windows10
        case .windowsServer: return build.uupProductLine == .windowsServer
        }
    }

    private func passesChannelFilter(_ build: UUPBuilds.Build) -> Bool {
        switch filterChannel {
        case .all: return true
        case .stable: return !build.uupIsInsiderStyleChannel
        case .insider: return build.uupIsInsiderStyleChannel
        }
    }

    private func passesArchFilter(_ build: UUPBuilds.Build) -> Bool {
        switch filterArch {
        case .all: return true
        case .arm64: return build.arch.lowercased() == "arm64"
        case .amd64: return build.arch.lowercased() == "amd64"
        case .x86: return build.arch.lowercased() == "x86"
        }
    }

    private func filteredBuildUUIDsEqual(_ a: [UUPBuilds.Build], _ b: [UUPBuilds.Build]) -> Bool {
        guard a.count == b.count else { return false }
        for i in a.indices where a[i].uuid != b[i].uuid {
            return false
        }
        return true
    }

    /// Call after filters change or list reload so selection stays valid.
    func reconcileSelectionWithDisplayedList() {
        let shown = displayedBuilds
        let ids = Set(shown.map(\.uuid))
        if let sel = selectedBuildUUID, ids.contains(sel) { return }
        selectedBuildUUID = shown.first?.uuid
    }

    private func scheduleSearchRecompute() {
        let trimmed = filterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchDebounceWorkItem?.cancel()
            searchDebounceWorkItem = nil
            recomputeDisplayedBuilds()
            return
        }
        searchDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.recomputeDisplayedBuilds()
        }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    /// Rebuilds `displayedBuilds` from `allBuilds` and current filters.
    /// - Parameter skipReconcile: Pass `true` when `loadBuilds()` applies its own selection rules (`preferredBuild`).
    private func recomputeDisplayedBuilds(skipReconcile: Bool = false) {
        let q = filterSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = allBuilds.filter { build in
            if !passesProductFilter(build) { return false }
            if !passesChannelFilter(build) { return false }
            if !passesArchFilter(build) { return false }
            if q.isEmpty { return true }
            return build.title.lowercased().contains(q)
                || build.build.lowercased().contains(q)
                || build.arch.lowercased().contains(q)
                || build.uuid.lowercased().contains(q)
        }
        // Newest first by **build number** (highest version label), not by UUPDump `created` date.
        list.sort { a, b in
            let ra = a.uupBuildVersionRank
            let rb = b.uupBuildVersionRank
            if ra != rb { return ra > rb }
            if a.build != b.build { return a.build > b.build }
            return a.uuid > b.uuid
        }
        // Comparing only UUID order avoids full struct equality over large catalogs.
        if filteredBuildUUIDsEqual(list, displayedBuilds) {
            if !skipReconcile {
                reconcileSelectionWithDisplayedList()
            }
            return
        }
        displayedBuilds = list
        displayedBuildsGeneration += 1
        if !skipReconcile {
            reconcileSelectionWithDisplayedList()
        }
    }

    /// Clears language/edition payloads when the user changes the tentative build before confirming again.
    func clearDetailsAndEditions() {
        details = nil
        editions = nil
    }

    /// Mirrors CrystalFetch `Worker.lookupPossibleLocale` (locale fallbacks for UUP API).
    func resolveLanguage(for details: UUPDetails, preferred: String?) -> String {
        var decision = preferred?.lowercased()
            ?? Locale.preferredLanguages.first?.lowercased()
            ?? "en-us"
        let localeMapper = ["zh-hans-cn": "zh-cn"]
        if let mapped = localeMapper[decision] {
            decision = mapped
        }
        if !details.langList.contains(decision) {
            decision = "en-us"
        }
        if !details.langList.contains(decision) {
            decision = details.langList.first ?? "en-us"
        }
        return decision
    }

    func loadBuilds() async {
        isLoadingBuilds = true
        lastError = nil
        defer { isLoadingBuilds = false }
        do {
            let response = try await api.fetchBuilds(search: nil)
            allBuilds = response.builds.filter { !$0.title.lowercased().contains("update") }
            recomputeDisplayedBuilds(skipReconcile: true)
            let shown = displayedBuilds
            let previous = selectedBuildUUID
            if let prev = previous, shown.contains(where: { $0.uuid == prev }) {
                selectedBuildUUID = prev
            } else if let pref = preferredBuild(from: shown) {
                selectedBuildUUID = pref.uuid
            } else {
                selectedBuildUUID = shown.first?.uuid
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadDetailsAndEditionsForSelection() async {
        guard let uuid = selectedBuild?.uuid else { return }
        lastError = nil
        isLoadingBuilds = true
        defer { isLoadingBuilds = false }
        do {
            let d = try await api.fetchDetails(for: uuid)
            details = d
            let lang = resolveLanguage(for: d, preferred: selectedLanguageCode)
            selectedLanguageCode = lang
            let ed = try await api.fetchEditions(for: uuid, language: lang)
            editions = ed
            if selectedEditionToken.isEmpty || !ed.editionList.contains(selectedEditionToken) {
                selectedEditionToken = ed.editionList.first(
                    where: { $0.lowercased().contains("pro") && !$0.lowercased().contains("enter") }
                ) ?? ed.editionList.first ?? ""
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancelActiveDownload() {
        Task {
            await activeDownloader?.cancelAll()
        }
    }

    /// Whether language/edition are ready to start a UUP download (used by Source sheet + Downloads UI).
    var canStartUUPDownload: Bool {
        guard !isDownloading else { return false }
        guard selectedBuild != nil else { return false }
        guard details != nil, editions != nil else { return false }
        guard !selectedLanguageCode.isEmpty else { return false }
        if let list = editions?.editionList, !list.isEmpty, selectedEditionToken.isEmpty {
            return false
        }
        return true
    }

    /// Cache location where UUP payload lands for the currently-selected build (`nil` until a build is selected).
    var currentUUPDirectory: URL? {
        guard let uuid = selectedBuild?.uuid else { return nil }
        return WistCache.cachesRootDirectory.appendingPathComponent("UUP/\(uuid)", isDirectory: true)
    }

    private func clearDownloadTelemetry() {
        downloadProgress = nil
        downloadStatus = nil
        downloadBytesWritten = 0
        downloadBytesTotal = 0
        downloadEtaFormatted = nil
        downloadProgressStartDate = nil
    }

    private func updateDownloadETA(written: Int64, total: Int64) {
        downloadBytesWritten = written
        downloadBytesTotal = total
        guard let start = downloadProgressStartDate, total > 0, written > 0, written < total else {
            downloadEtaFormatted = nil
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed >= 0.45 else { return }
        let rate = Double(written) / elapsed
        guard rate > 1024 else { return }
        let remaining = Double(total - written) / rate
        guard remaining.isFinite, remaining > 1.5 else {
            downloadEtaFormatted = nil
            return
        }
        downloadEtaFormatted = Self.formatDownloadETA(remainingSeconds: remaining)
    }

    private static func formatDownloadETA(remainingSeconds: Double) -> String {
        let s = Int(remainingSeconds.rounded(.up))
        if s < 90 {
            return String(format: String(localized: "~%lld s left"), Int64(s))
        }
        let minutes = (s + 59) / 60
        if minutes < 120 {
            return String(format: String(localized: "~%lld min left"), Int64(minutes))
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: String(localized: "~%lld h %lld min left"), Int64(hours), Int64(mins))
    }

    /// Downloads UUP payload into the app cache; build `.iso` via Build ISO on the Downloads screen.
    func downloadSelectedPackageToCache() async {
        guard let uuid = selectedBuild?.uuid else {
            lastError = String(localized: "Select a build first.")
            return
        }
        guard details != nil, editions != nil else {
            lastError = String(localized: "Tap Languages & editions first.")
            return
        }
        guard !selectedLanguageCode.isEmpty else {
            lastError = String(localized: "Select a language.")
            return
        }
        if let list = editions?.editionList, !list.isEmpty, selectedEditionToken.isEmpty {
            lastError = String(localized: "Select a Windows edition in the list above.")
            return
        }
        let editionList: [String] = selectedEditionToken.isEmpty ? [] : [selectedEditionToken]
        lastError = nil
        isDownloading = true
        downloadProgress = 0
        downloadBytesWritten = 0
        downloadBytesTotal = 0
        downloadEtaFormatted = nil
        downloadProgressStartDate = nil
        downloadStatus = String(localized: "Requesting file list…")
        defer {
            isDownloading = false
            activeDownloader = nil
            downloadProgressStartDate = nil
        }
        do {
            let package = try await api.fetchPackage(for: uuid, language: selectedLanguageCode, editions: editionList)
            if package.files.isEmpty {
                lastError = String(localized: "The server returned an empty file list. Try another edition or language.")
                clearDownloadTelemetry()
                return
            }
            let base = WistCache.cachesRootDirectory
                .appendingPathComponent("UUP/\(uuid)", isDirectory: true)
            try? FileManager.default.removeItem(at: base)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

            let downloader = Downloader()
            activeDownloader = downloader
            var enqueuedCount = 0
            for (key, value) in package.files {
                guard let url = URL(string: value.url), url.scheme != nil else { continue }
                await downloader.enqueue(downloadUrl: url, to: base.appendingPathComponent(key), size: value.size)
                enqueuedCount += 1
            }
            if enqueuedCount == 0 {
                lastError = String(localized: "No files could be queued (invalid links). Try again later.")
                clearDownloadTelemetry()
                return
            }

            downloadProgressStartDate = Date()
            try await downloader.start { [weak self] written, total in
                guard let self else { return }
                Task { @MainActor in
                    let w = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
                    let t = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                    self.downloadStatus = String(format: String(localized: "Downloading: %@ of %@"), w, t)
                    if total > 0 {
                        self.downloadProgress = min(1, Double(written) / Double(total))
                        self.updateDownloadETA(written: written, total: total)
                    }
                }
            }
            if let build = selectedBuild {
                let meta = UUPCacheMetadata(
                    uuid: build.uuid,
                    title: build.title,
                    buildNumber: build.build,
                    arch: build.arch,
                    created: build.created,
                    languageCode: selectedLanguageCode,
                    editionToken: selectedEditionToken
                )
                try? meta.write(into: base)
            }
            downloadStatus = String(format: String(localized: "Done: files at %@"), base.path)
            downloadProgress = 1
            downloadEtaFormatted = nil
            if downloadBytesTotal > 0 {
                downloadBytesWritten = downloadBytesTotal
            }
        } catch is CancellationError {
            lastError = String(localized: "Download canceled.")
            clearDownloadTelemetry()
        } catch {
            lastError = Self.userFacingDownloadError(error)
            clearDownloadTelemetry()
        }
    }

    func appendConvertLog(_ line: String) {
        convertLogLines.append(line)
        if convertLogLines.count > 400 {
            convertLogLines.removeFirst(convertLogLines.count - 400)
        }
    }

    /// Runs bundled `convert.sh` from `ThirdParty/UUPConverter`. Requires Homebrew tools (see README).
    /// If `destinationFolder` is provided, the finished `.iso` is moved next to it (user-picked
    /// folder via NSOpenPanel). When `nil`, the ISO stays in the cache alongside the UUP folder.
    func convertUUPFolderToISO(uupDirectory: URL, destinationFolder: URL? = nil) async {
        convertLastError = nil
        lastProducedISOPath = nil
        convertLogLines = []
        convertStatusLine = String(localized: "Checking dependencies…")
        isConvertingUUP = true
        defer {
            isConvertingUUP = false
            convertStatusLine = nil
        }
        let folderName = uupDirectory.lastPathComponent
        let outputDir = uupDirectory.deletingLastPathComponent()
            .appendingPathComponent("\(folderName)-iso-build", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: outputDir.path) {
                try FileManager.default.removeItem(at: outputDir)
            }
            let iso = try await UUPISOConverter.convert(
                uupDirectory: uupDirectory,
                outputDirectory: outputDir,
                compression: "wim",
                virtualEditions: false,
                onLine: { [weak self] line in
                    Task { @MainActor in
                        guard let self else { return }
                        self.appendConvertLog(line)
                        self.convertStatusLine = line
                    }
                }
            )
            let finalURL = Self.relocateISOIfNeeded(iso: iso, destinationFolder: destinationFolder)
            lastProducedISOPath = finalURL.path
            appendConvertLog(String(format: String(localized: "— Done: %@"), finalURL.path))
        } catch is CancellationError {
            convertLastError = String(localized: "Conversion canceled.")
        } catch {
            convertLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Moves the finished ISO into the user-picked folder. On any failure falls back to the cache path so the flow keeps working.
    private static func relocateISOIfNeeded(iso: URL, destinationFolder: URL?) -> URL {
        guard let dest = destinationFolder else { return iso }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: dest.path, isDirectory: &isDir) || !isDir.boolValue {
            do {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } catch {
                return iso
            }
        }
        let target = dest.appendingPathComponent(iso.lastPathComponent)
        if fm.fileExists(atPath: target.path) {
            try? fm.removeItem(at: target)
        }
        do {
            try fm.moveItem(at: iso, to: target)
            return target
        } catch {
            return iso
        }
    }

    private static func userFacingDownloadError(_ error: Error) -> String {
        if let e = error as? UUPDumpAPIError {
            switch e {
            case .responseNotFound:
                return String(localized: "Invalid UUPDump response (missing response field). Check the network and try again.")
            case .errorResponse(let message):
                return "UUPDump: \(message)"
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet:
                return String(localized: "No internet connection.")
            case NSURLErrorTimedOut:
                return String(localized: "Network timed out. Try again later.")
            case NSURLErrorCancelled:
                return String(localized: "Download canceled.")
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func preferredBuild(from list: [UUPBuilds.Build]) -> UUPBuilds.Build? {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "amd64"
        #endif
        return list.first { $0.arch == arch && !$0.title.contains("Insider") }
            ?? list.first
    }
}
