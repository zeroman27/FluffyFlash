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

    /// `…/Contents/Resources/Tools/bin` when tools are embedded in the app.
    static func bundledToolsBinDirectory() -> URL? {
        let fm = FileManager.default
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: "bin", withExtension: nil, subdirectory: "Tools"),
            bundle.resourceURL?.appendingPathComponent("Tools/bin"),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/Tools/bin"),
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
