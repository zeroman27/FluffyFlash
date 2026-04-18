//
//  UUPBuildFilters.swift
//  Wist
//

import Foundation

// MARK: - Filter enums (UI)

enum UUPProductFilter: String, CaseIterable, Identifiable {
    case all = "All products"
    case windows11 = "Windows 11"
    case windows10 = "Windows 10"
    case windowsServer = "Windows Server"
    var id: String { rawValue }
}

enum UUPChannelFilter: String, CaseIterable, Identifiable {
    case all = "All channels"
    case stable = "Stable (Retail)"
    case insider = "Insider / Preview"
    var id: String { rawValue }
}

enum UUPArchFilter: String, CaseIterable, Identifiable {
    case all = "Any"
    case arm64 = "arm64"
    case amd64 = "amd64"
    case x86 = "x86"
    var id: String { rawValue }
}

// MARK: - Classification (heuristics on UUPDump `title`)

extension UUPBuilds.Build {

    enum ProductLine {
        case windows11
        case windows10
        case windowsServer
        case other
    }

    var uupProductLine: ProductLine {
        let t = title.lowercased()
        if t.contains("server") { return .windowsServer }
        if t.contains("windows 11") { return .windows11 }
        if t.contains("windows 10") { return .windows10 }
        return .other
    }

    /// Insider / Canary / Dev / Beta / Release Preview rings — not “stable retail” ISO path.
    var uupIsInsiderStyleChannel: Bool {
        let t = title.lowercased()
        if t.contains("insider") { return true }
        if t.contains("canary") { return true }
        if t.contains("dev channel") { return true }
        if t.contains("beta channel") { return true }
        if t.contains("release preview") { return true }
        return false
    }

    /// Sort key: UUPDump `created` (sec since epoch) when present; else parsed build number.
    var uupSortKey: Int64 {
        if let c = created, c > 0 {
            return Int64(c)
        }
        return Self.parseBuildNumberString(build)
    }

    /// Compare dotted build strings (e.g. 26100.1742) for a rough ordering when `created` is missing.
    private static func parseBuildNumberString(_ s: String) -> Int64 {
        let parts = s.split(separator: ".").compactMap { Int64($0) }
        guard !parts.isEmpty else { return 0 }
        let major = parts[0]
        let minor = parts.count > 1 ? parts[1] : 0
        return major * 1_000_000 + min(minor, 999_999)
    }
}
