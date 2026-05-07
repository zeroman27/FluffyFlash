//
//  BundledToolLocator.swift
//  Wist
//

import Foundation

enum BundledToolError: LocalizedError {
    case wimlibNotFound
    case mistNotFound

    var errorDescription: String? {
        switch self {
        case .wimlibNotFound:
            return String(localized: "wimlib-imagex was not found. Release builds include it under Tools/bin. Otherwise: brew install wimlib")
        case .mistNotFound:
            return String(localized: "mist (mist-cli) was not found. Release builds include it under Tools/bin. Otherwise: brew install mist-cli")
        }
    }
}

enum BundledToolLocator: Sendable {

    /// Marker executables used to detect a "flat" bundle layout: when Xcode's
    /// `PBXFileSystemSynchronizedRootGroup` flattens `Fluffy Flash/Tools/bin/*`
    /// directly into `Contents/Resources/`, the nested directory does not exist
    /// but the executables are still present alongside other resources.
    private static let flatLayoutMarkerExecutables: [String] = [
        "aria2c", "wimlib-imagex", "cabextract", "chntpw", "xorriso",
    ]

    /// Directory containing bundled CLI executables. Returns the nested
    /// `…/Contents/Resources/Tools/bin` when available, or falls back to
    /// `…/Contents/Resources` when Xcode's synchronized group flattened the
    /// `Tools/bin/` files into the resources root (current Xcode 26 behaviour).
    static func bundledToolsBinDirectory() -> URL? {
        detectBundledBinDirectory(
            resourceURL: Bundle.main.resourceURL,
            bundleURL: Bundle.main.bundleURL
        )
    }

    /// Testable variant of `bundledToolsBinDirectory()`. Resolves the bundled
    /// `Tools/bin` directory using the same precedence rules as the
    /// production code, but against any caller-supplied bundle layout.
    static func detectBundledBinDirectory(resourceURL: URL?, bundleURL: URL?) -> URL? {
        let fm = FileManager.default
        let nestedCandidates: [URL?] = [
            resourceURL?.appendingPathComponent("Tools/bin"),
            bundleURL?.appendingPathComponent("Contents/Resources/Tools/bin"),
        ]
        for u in nestedCandidates {
            guard let u, fm.fileExists(atPath: u.path) else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                return u
            }
        }
        if let resources = resourceURL,
           hasAnyMarkerExecutable(in: resources) {
            return resources
        }
        return nil
    }

    /// True when at least one of the marker CLI binaries is executable
    /// directly under `dir` (used to detect the flat resources layout).
    static func hasAnyMarkerExecutable(in dir: URL) -> Bool {
        let fm = FileManager.default
        for name in flatLayoutMarkerExecutables {
            let candidate = dir.appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate.path) {
                return true
            }
        }
        return false
    }

    static func bundledToolsLibDirectory() -> URL? {
        let fm = FileManager.default
        let bundle = Bundle.main
        // Bundled CLI tools use @loader_path/../lib from Contents/Resources/<exe> → Contents/lib
        let contentsLib = URL(fileURLWithPath: bundle.bundlePath).appendingPathComponent("Contents/lib")
        let candidates: [URL?] = [
            contentsLib,
            bundle.url(forResource: "lib", withExtension: nil, subdirectory: "Tools"),
            bundle.resourceURL?.appendingPathComponent("Tools/lib"),
            bundle.resourceURL?.appendingPathComponent("lib"),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/Tools/lib"),
        ]
        for u in candidates {
            guard let u, fm.fileExists(atPath: u.path) else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                return u
            }
        }
        return nil
    }

    /// Executable shipped under `Tools/bin`, or (if the build flattens resources) as `Resources/<name>`.
    static func urlForBundledCLI(named name: String) -> URL? {
        let fm = FileManager.default
        if let bin = bundledToolsBinDirectory() {
            let u = bin.appendingPathComponent(name)
            if fm.isExecutableFile(atPath: u.path) { return u }
        }
        if let res = Bundle.main.resourceURL {
            let flat = res.appendingPathComponent(name)
            if fm.isExecutableFile(atPath: flat.path) { return flat }
        }
        if let u = Bundle.main.url(forResource: name, withExtension: nil),
           fm.isExecutableFile(atPath: u.path) {
            return u
        }
        return nil
    }

    /// True when all converters for `convert.sh` are present under `Tools/bin`.
    static var hasEmbeddedUUPToolchain: Bool {
        let need = ["aria2c", "cabextract", "wimlib-imagex", "chntpw"]
        guard need.allSatisfy({ urlForBundledCLI(named: $0) != nil }) else { return false }
        let iso =
            urlForBundledCLI(named: "mkisofs") != nil
            || urlForBundledCLI(named: "genisoimage") != nil
            || urlForBundledCLI(named: "xorriso") != nil
        return iso
    }

    /// `wimlib-imagex` for splitting `install.wim` onto FAT32 — bundled first, then Homebrew.
    static func wimlibImagexExecutable() throws -> URL {
        if let u = urlForBundledCLI(named: "wimlib-imagex") {
            return u
        }
        let fm = FileManager.default
        let bundle = Bundle.main
        if let u = bundle.url(forAuxiliaryExecutable: "wimlib-imagex"), fm.isExecutableFile(atPath: u.path) {
            return u
        }
        if let u = bundle.url(forResource: "wimlib-imagex", withExtension: nil, subdirectory: "Tools"),
           fm.isExecutableFile(atPath: u.path) {
            return u
        }
        let brewPaths = [
            "/opt/homebrew/bin/wimlib-imagex",
            "/usr/local/bin/wimlib-imagex",
            "/usr/bin/wimlib-imagex",
        ]
        for p in brewPaths where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        throw BundledToolError.wimlibNotFound
    }

    /// `mist` (mist-cli) for downloading macOS installers / IPSWs — bundled first, then Homebrew.
    static func mistCLIExecutable() throws -> URL {
        if let u = urlForBundledCLI(named: "mist") {
            return u
        }
        let fm = FileManager.default
        let brewPaths = [
            "/opt/homebrew/bin/mist",
            "/usr/local/bin/mist",
            "/usr/bin/mist",
        ]
        for p in brewPaths where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        throw BundledToolError.mistNotFound
    }

    static var rsync: URL { URL(fileURLWithPath: "/usr/bin/rsync") }
    static var diskutil: URL { URL(fileURLWithPath: "/usr/sbin/diskutil") }
    static var hdiutil: URL { URL(fileURLWithPath: "/usr/bin/hdiutil") }
}
