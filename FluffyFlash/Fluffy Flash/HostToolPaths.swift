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

        env["PATH"] = subprocessPATH(includingProcessPATH: env["PATH"])

        if let lib = BundledToolLocator.bundledToolsLibDirectory()?.path,
           FileManager.default.fileExists(atPath: lib) {
            env["DYLD_LIBRARY_PATH"] = lib
            env["DYLD_FALLBACK_LIBRARY_PATH"] = lib
        }
        return env
    }

    /// Computes the exact `PATH` value that subprocesses (e.g. `convert.sh`) will
    /// see, so diagnostics and the System Status page can display it verbatim.
    static func subprocessPATHForDiagnostics() -> String {
        subprocessPATH(includingProcessPATH: ProcessInfo.processInfo.environment["PATH"])
    }

    private static func subprocessPATH(includingProcessPATH existing: String?) -> String {
        composeSubprocessPATH(
            bundledBin: BundledToolLocator.bundledToolsBinDirectory(),
            processPATH: existing
        )
    }

    /// Pure helper used by both production code and tests. Always prepends the
    /// bundled `Tools/bin` directory so subprocesses find embedded CLI tools
    /// even when the host machine has no Homebrew.
    static func composeSubprocessPATH(bundledBin: URL?, processPATH: String?) -> String {
        var pathParts: [String] = []
        if let bundled = bundledBin?.path {
            pathParts.append(bundled)
        }
        pathParts.append(contentsOf: extendedPATH.split(separator: ":").map(String.init))
        if let processPATH, !processPATH.isEmpty {
            pathParts.append(processPATH)
        }
        return pathParts.joined(separator: ":")
    }
}
