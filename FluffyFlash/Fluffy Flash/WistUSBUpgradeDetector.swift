//
//  WistUSBUpgradeDetector.swift
//  Fluffy Flash
//
//  Watches Fluffy-formatted USB drives (sidecar JSON) and polls UUPDump for newer
//  builds that match (arch, language, edition). Published `offers` drive the Home
//  upgrade hero and sidebar pill.
//

import Combine
import Foundation

/// One drive that can be upgraded to a newer build without user lookup.
struct DriveUpgradeOffer: Identifiable, Hashable {
    var id: String { drive.deviceIdentifier }
    let drive: RemovableDriveInfo
    let currentMeta: WistUSBMetadata
    let latestBuild: UUPBuilds.Build
    /// Whether `latestBuild` really is newer than `currentMeta`.
    let isNewer: Bool
}

/// Cached latest build per (arch, lang, edition) tuple (TTL guard to avoid hammering UUPDump).
private struct LatestCacheEntry: Codable {
    var arch: String
    var language: String
    var editionToken: String
    var buildUuid: String
    var buildNumber: String
    var buildTitle: String
    var fetchedAtEpoch: TimeInterval
}

@MainActor
final class WistUSBUpgradeDetector: ObservableObject {

    @Published private(set) var offers: [DriveUpgradeOffer] = []
    @Published private(set) var isChecking: Bool = false
    @Published private(set) var lastCheckDate: Date?

    /// Cap on freshness. User-tunable via Settings, default 15 min.
    var cacheTTLSeconds: TimeInterval = 15 * 60
    /// Disable network probing (offline / user opt-out). Cached results still surface.
    var isNetworkProbingEnabled: Bool = true

    private let api = UUPDumpAPI()
    private let cacheDefaultsKey = "fluffy.upgradeDetector.latestCache.v1"
    private var latestCache: [String: LatestCacheEntry] = [:]
    private var inflightKeys: Set<String> = []

    private weak var diskManager: DiskManager?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        loadCache()
    }

    /// Wires the detector to a disk manager. Call once from the view `.task` so
    /// the class can stay trivially `@MainActor init()`-able.
    func attach(to diskManager: DiskManager) {
        guard self.diskManager !== diskManager else { return }
        cancellables.removeAll()
        self.diskManager = diskManager
        diskManager.$drives
            .removeDuplicates { a, b in
                a.map(\.deviceIdentifier) == b.map(\.deviceIdentifier)
                    && a.map(\.wistSidecarMeta) == b.map(\.wistSidecarMeta)
            }
            .sink { [weak self] _ in
                Task { [weak self] in await self?.recomputeOffers() }
            }
            .store(in: &cancellables)
        Task { await recomputeOffers() }
    }

    /// Force a fresh check — used by the Home "Check for updates now" affordance.
    func forceCheck() {
        Task {
            latestCache.removeAll()
            saveCache()
            await recomputeOffers()
        }
    }

    func recomputeOffers() async {
        guard let manager = diskManager else { return }
        let drivesWithMeta = manager.drives.compactMap { d -> (RemovableDriveInfo, WistUSBMetadata)? in
            guard let m = d.wistSidecarMeta else { return nil }
            return (d, m)
        }
        guard !drivesWithMeta.isEmpty else {
            offers = []
            return
        }
        isChecking = true
        defer {
            isChecking = false
            lastCheckDate = Date()
        }

        let tuples = Set(drivesWithMeta.map { (_, m) in
            cacheKey(arch: m.arch, language: m.language, edition: m.editionToken)
        })
        for key in tuples {
            if needsRefresh(for: key) {
                await refreshLatest(forKey: key)
            }
        }

        var result: [DriveUpgradeOffer] = []
        for (drive, meta) in drivesWithMeta {
            let key = cacheKey(arch: meta.arch, language: meta.language, edition: meta.editionToken)
            guard let entry = latestCache[key] else { continue }
            let synthetic = UUPBuilds.Build.make(
                uuid: entry.buildUuid,
                title: entry.buildTitle,
                build: entry.buildNumber,
                arch: entry.arch
            )
            let newer = Self.isBuildStrictlyNewer(latestBuild: entry.buildNumber, currentBuild: meta.buildNumber)
            result.append(
                DriveUpgradeOffer(
                    drive: drive,
                    currentMeta: meta,
                    latestBuild: synthetic,
                    isNewer: newer
                )
            )
        }
        offers = result
    }

    private func cacheKey(arch: String, language: String, edition: String) -> String {
        "\(arch.lowercased())|\(language.lowercased())|\(edition.lowercased())"
    }

    private func needsRefresh(for key: String) -> Bool {
        guard let entry = latestCache[key] else { return true }
        let age = Date().timeIntervalSince1970 - entry.fetchedAtEpoch
        return age > cacheTTLSeconds
    }

    private func refreshLatest(forKey key: String) async {
        guard isNetworkProbingEnabled else { return }
        guard !inflightKeys.contains(key) else { return }
        inflightKeys.insert(key)
        defer { inflightKeys.remove(key) }

        let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return }
        let arch = String(parts[0])
        let language = String(parts[1])
        let edition = String(parts[2])

        do {
            let response = try await api.fetchBuilds(search: nil)
            let filtered = response.builds
                .filter { !$0.title.lowercased().contains("update") }
                .filter { !$0.uupIsInsiderStyleChannel }
                .filter { $0.arch.lowercased() == arch }
            let newest = filtered.max(by: { a, b in
                a.uupBuildVersionRank < b.uupBuildVersionRank
            })
            guard let build = newest else { return }
            let entry = LatestCacheEntry(
                arch: arch,
                language: language,
                editionToken: edition,
                buildUuid: build.uuid,
                buildNumber: build.build,
                buildTitle: build.title,
                fetchedAtEpoch: Date().timeIntervalSince1970
            )
            latestCache[key] = entry
            saveCache()
        } catch {
            // Silent on network errors — we still expose a cached entry if present.
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheDefaultsKey),
              let rows = try? JSONDecoder().decode([LatestCacheEntry].self, from: data)
        else {
            latestCache = [:]
            return
        }
        var map: [String: LatestCacheEntry] = [:]
        for row in rows {
            let key = cacheKey(arch: row.arch, language: row.language, edition: row.editionToken)
            map[key] = row
        }
        latestCache = map
    }

    private func saveCache() {
        let rows = Array(latestCache.values)
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: cacheDefaultsKey)
    }

    /// Compares dotted Windows build strings (e.g. `22631.4460`) numerically.
    static func isBuildStrictlyNewer(latestBuild: String, currentBuild: String) -> Bool {
        let parse: (String) -> [Int64] = { s in
            s.split(separator: ".").compactMap { Int64($0) }
        }
        let l = parse(latestBuild)
        let c = parse(currentBuild)
        let maxLen = max(l.count, c.count)
        for i in 0 ..< maxLen {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }
}

private extension UUPBuilds.Build {
    /// Manual initializer for synthetic cache-backed builds (since the generated one is `Decoder`-only).
    static func make(uuid: String, title: String, build: String, arch: String) -> UUPBuilds.Build {
        let json: [String: Any] = [
            "uuid": uuid,
            "title": title,
            "build": build,
            "arch": arch,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(UUPBuilds.Build.self, from: data)
    }
}
