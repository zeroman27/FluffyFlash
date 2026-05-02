//
//  MacOSInstallerVersionRank.swift
//  Fluffy Flash
//
//  Compares Mist catalog installers to Fluffy sidecar metadata on USB drives.
//

import Foundation

/// Upgrade row for a USB drive that has `FluffyFlash.macos.meta.json`.
struct MacOSDriveUpgradeOffer: Identifiable, Hashable {
    var id: String { drive.deviceIdentifier }
    let drive: RemovableDriveInfo
    let currentMeta: FluffyMacOSUSBMetadata
    /// Newest matching row from `mist list installer` for the standard catalog probe.
    let latestInstaller: MistCLITool.InstallerListItem
    let isNewer: Bool
}

enum MacOSInstallerVersionRank {
    /// Resolves the catalog row that best corresponds to the USB sidecar, then picks the newest among equivalent rows.
    static func bestMatchingInstaller(list: [MistCLITool.InstallerListItem], meta: FluffyMacOSUSBMetadata) -> MistCLITool.InstallerListItem? {
        let strict = matchingInstallers(list: list, sidecarDisplayName: meta.installerDisplayName)
        if !strict.isEmpty, let top = newestAmongCandidates(strict) {
            return top
        }
        let dn = meta.installerDisplayName.lowercased()
        let loose = list.filter {
            let n = $0.name.lowercased()
            return n.contains(dn) || dn.contains(n)
        }
        return newestAmongCandidates(loose)
    }

    /// Picks catalog rows that describe the same macOS product line as the sidecar (best-effort string match).
    static func matchingInstallers(list: [MistCLITool.InstallerListItem], sidecarDisplayName: String) -> [MistCLITool.InstallerListItem] {
        let key = productLineKey(sidecarDisplayName)
        guard !key.isEmpty else { return [] }
        return list.filter { productLineKey($0.name) == key || $0.name.lowercased().contains(key) || key.contains(productLineKey($0.name)) }
    }

    /// Chooses the newest row among candidates using version then build.
    static func newestAmongCandidates(_ items: [MistCLITool.InstallerListItem]) -> MistCLITool.InstallerListItem? {
        guard !items.isEmpty else { return nil }
        return items.max { a, b in
            compareCatalogItems(a, b) == .orderedAscending
        }
    }

    static func compareCatalogItems(_ a: MistCLITool.InstallerListItem, _ b: MistCLITool.InstallerListItem) -> ComparisonResult {
        let v = compareMarketingVersion(a.version, b.version)
        if v != .orderedSame { return v }
        return compareAppleBuildString(a.build, b.build)
    }

    /// `true` when the catalog’s newest matching installer is strictly newer than what is recorded on the USB.
    static func isLatestStrictlyNewer(latest: MistCLITool.InstallerListItem, current: FluffyMacOSUSBMetadata) -> Bool {
        compareToSidecar(latest: latest, current: current) == .orderedDescending
    }

    static func compareToSidecar(latest: MistCLITool.InstallerListItem, current: FluffyMacOSUSBMetadata) -> ComparisonResult {
        let curVer = effectiveMarketingVersion(for: current)
        if !curVer.isEmpty {
            let v = compareMarketingVersion(latest.version, curVer)
            if v != .orderedSame { return v }
        }
        let curBuild = effectiveBuild(for: current)
        return compareAppleBuildString(latest.build, curBuild)
    }

    /// Prefer marketing / platform strings over `CFBundleShortVersionString`, which Apple often keeps on an older internal train.
    private static func effectiveMarketingVersion(for meta: FluffyMacOSUSBMetadata) -> String {
        if let m = meta.installerMarketingVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            return m
        }
        if let p = meta.installerDTPlatformVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return (meta.installerShortVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prefer build train parsed from the `.app` name (matches Mist) over `CFBundleVersion` when present.
    private static func effectiveBuild(for meta: FluffyMacOSUSBMetadata) -> String {
        if let b = meta.installerAppleBuildFromName?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            return b
        }
        return (meta.installerBundleVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    /// Normalizes "Install macOS Sequoia", "macOS Sequoia 15.2", etc. to a loose product key.
    private static func productLineKey(_ raw: String) -> String {
        var s = raw.lowercased()
        for prefix in ["install macos ", "macos "] {
            if s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop a trailing version-like token (15.2 / 26.0.1) so major releases still match.
        let parts = s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty else { return "" }
        var kept: [String] = []
        for p in parts {
            if p.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil { break }
            kept.append(p)
        }
        let joined = kept.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? s : joined
    }

    private static func compareMarketingVersion(_ a: String, _ b: String) -> ComparisonResult {
        let ca = parseNumericComponents(a)
        let cb = parseNumericComponents(b)
        let n = max(ca.count, cb.count)
        for i in 0 ..< n {
            let va = i < ca.count ? ca[i] : 0
            let vb = i < cb.count ? cb[i] : 0
            if va > vb { return .orderedDescending }
            if va < vb { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func parseNumericComponents(_ s: String) -> [Int] {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ".").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Apple build trains (e.g. `24G84`, `23F79`): compare digit prefix, then letter, then suffix digits.
    private static func compareAppleBuildString(_ a: String, _ b: String) -> ComparisonResult {
        let ta = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let tb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if ta.isEmpty, tb.isEmpty { return .orderedSame }
        if ta.isEmpty { return .orderedAscending }
        if tb.isEmpty { return .orderedDescending }

        let pa = parseAppleBuild(ta)
        let pb = parseAppleBuild(tb)
        if pa.prefix != pb.prefix {
            return pa.prefix > pb.prefix ? .orderedDescending : .orderedAscending
        }
        if pa.letter != pb.letter {
            return pa.letter > pb.letter ? .orderedDescending : .orderedAscending
        }
        if pa.suffix != pb.suffix {
            return pa.suffix > pb.suffix ? .orderedDescending : .orderedAscending
        }
        return ta.localizedStandardCompare(tb)
    }

    private struct AppleBuildParts {
        var prefix: Int
        var letter: UInt32
        var suffix: Int
    }

    private static func parseAppleBuild(_ s: String) -> AppleBuildParts {
        // Leading digits
        var i = s.startIndex
        while i < s.endIndex, s[i].isNumber {
            i = s.index(after: i)
        }
        let prefixStr = String(s[s.startIndex ..< i])
        let prefix = Int(prefixStr) ?? 0

        var letter: UInt32 = 0
        if i < s.endIndex {
            let ch = s[i]
            if ch.isLetter, let sc = ch.unicodeScalars.first {
                letter = sc.value
                i = s.index(after: i)
            }
        }

        var suffix = 0
        while i < s.endIndex, s[i].isNumber {
            let j = s.index(after: i)
            suffix = suffix * 10 + (Int(String(s[i])) ?? 0)
            i = j
        }
        return AppleBuildParts(prefix: prefix, letter: letter, suffix: suffix)
    }
}
