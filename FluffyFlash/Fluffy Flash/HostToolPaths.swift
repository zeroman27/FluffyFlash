//
//  HostToolPaths.swift
//  Wist
//

import Foundation

/// PATH for GUI apps: prefer **bundled** `Tools/bin`, then Homebrew/system (CrystalFetch-style).
enum HostToolPaths: Sendable {
    static let extendedPATH =
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Resolve `name` in bundled `Tools/bin` first, then common system locations.
    static func resolvedExecutableURL(named name: String) -> URL? {
        if let u = BundledToolLocator.urlForBundledCLI(named: name) {
            return u
        }
        let fm = FileManager.default
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            let u = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: u.path) { return u }
        }
        return nil
    }

    static func hasExecutable(named name: String) -> Bool {
        resolvedExecutableURL(named: name) != nil
    }

    static func hasMkIsoTool() -> Bool {
        resolvedExecutableURL(named: "genisoimage") != nil
            || resolvedExecutableURL(named: "mkisofs") != nil
            || resolvedExecutableURL(named: "xorriso") != nil
    }

    static func environmentWithExtendedPATH(
        merging base: [String: String]? = nil
    ) -> [String: String] {
        environmentForBundledAndHostCLI(merging: base)
    }

    /// PATH with bundled `Tools/bin` first; optional `DYLD_*` when `Tools/lib` exists (helper for some dylib layouts).
    static func environmentForBundledAndHostCLI(
        merging base: [String: String]? = nil
    ) -> [String: String] {
        var env = Dictionary(uniqueKeysWithValues: ProcessInfo.processInfo.environment.map { ($0.key, $0.value) })
        base?.forEach { env[$0.key] = $0.value }

        var pathParts: [String] = []
        if let bundled = BundledToolLocator.bundledToolsBinDirectory()?.path {
            pathParts.append(bundled)
        }
        pathParts.append(contentsOf: extendedPATH.split(separator: ":").map(String.init))
        if let existing = env["PATH"], !existing.isEmpty {
            pathParts.append(existing)
        }
        env["PATH"] = pathParts.joined(separator: ":")

        if let lib = BundledToolLocator.bundledToolsLibDirectory()?.path,
           FileManager.default.fileExists(atPath: lib) {
            env["DYLD_LIBRARY_PATH"] = lib
            env["DYLD_FALLBACK_LIBRARY_PATH"] = lib
        }
        return env
    }
}
