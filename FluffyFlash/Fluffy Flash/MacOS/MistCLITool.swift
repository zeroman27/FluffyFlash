//
//  MistCLITool.swift
//  Wist
//

import Foundation

enum MistCLIToolError: LocalizedError {
    case invalidExportFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidExportFile(let message):
            return message
        }
    }
}

/// Thin wrapper around `mist` (mist-cli). Uses `--export <file>.json` for machine-readable output.
enum MistCLITool: Sendable {
    struct InstallerListItem: Hashable, Sendable {
        let name: String
        let version: String
        let build: String
        let sizeBytes: Int64?
        let releaseDateISO8601: String?
    }

    struct FirmwareListItem: Hashable, Sendable {
        let name: String
        let version: String
        let build: String
        let sizeBytes: Int64?
        let releaseDateISO8601: String?
        let url: String?
    }

    enum InstallerOutputType: String, CaseIterable, Sendable {
        case application
        case image
        case iso
        case package
    }

    enum Catalog: String, CaseIterable, Sendable {
        case standard = "standard"
        case customerSeed = "customer-seed"
        case developerSeed = "developer-seed"
        case publicSeed = "public-seed"
    }

    /// Software Update catalog URLs for `mist … --catalog-url …` (mist-cli 2.x).
    /// `standard` uses mist’s built-in default (no flag). Seed URLs mirror mist-cli’s embedded defaults; Apple may change them over time.
    private static func installerCatalogURL(for catalog: Catalog) -> String? {
        switch catalog {
        case .standard:
            return nil
        case .customerSeed:
            return "https://swscan.apple.com/content/catalogs/others/index-26customerseed-26-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz"
        case .developerSeed:
            return "https://swscan.apple.com/content/catalogs/others/index-26seed-26-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz"
        case .publicSeed:
            return "https://swscan.apple.com/content/catalogs/others/index-26beta-26-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz"
        }
    }

    private static func appendInstallerCatalogURL(to args: inout [String], catalog: Catalog?) {
        guard let catalog else { return }
        guard let url = installerCatalogURL(for: catalog) else { return }
        args += ["--catalog-url", url]
    }

    /// `mist list installer --export file.json`
    static func listInstallers(exportURL: URL, includeBetas: Bool = false, catalog: Catalog? = nil) async throws -> [InstallerListItem] {
        let exe = try BundledToolLocator.mistCLIExecutable()
        let args = listInstallerArgs(exportURL: exportURL, includeBetas: includeBetas, catalog: catalog)
        try await ProcessRunner.runCollectingOutput(
            executableURL: exe,
            arguments: args,
            currentDirectoryURL: nil,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onStdoutLine: nil,
            onStderrLine: nil
        )
        return try parseInstallerListJSON(at: exportURL)
    }

    /// `mist list firmware --export file.json` (no `--catalog-url` in mist-cli 2.x for this subcommand).
    static func listFirmwares(exportURL: URL, includeBetas: Bool = false) async throws -> [FirmwareListItem] {
        let exe = try BundledToolLocator.mistCLIExecutable()
        let args = listFirmwareArgs(exportURL: exportURL, includeBetas: includeBetas)
        try await ProcessRunner.runCollectingOutput(
            executableURL: exe,
            arguments: args,
            currentDirectoryURL: nil,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onStdoutLine: nil,
            onStderrLine: nil
        )
        return try parseFirmwareListJSON(at: exportURL)
    }

    /// `mist download installer "<search>" <output-type>... --output-directory ... --export file.json`
    ///
    /// Returns the export JSON (raw dictionary) for now; higher-level code can map it to file URLs.
    static func downloadInstaller(
        search: String,
        outputTypes: [InstallerOutputType],
        outputDirectory: URL,
        exportURL: URL,
        catalog: Catalog? = nil,
        includeBetas: Bool = false,
        forceOverwrite: Bool = false,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> [String: Any] {
        // `mist download installer` validates that the real user is root (mist-cli 2.x). Run via admin shell.
        let exe = try mistExecutableForPrivilegedDownloads()
        var args: [String] = ["download", "installer"]
        appendInstallerCatalogURL(to: &args, catalog: catalog)
        if includeBetas {
            args.append("--include-betas")
        }
        if forceOverwrite {
            args.append("--force")
        }
        // Place temp downloads inside our cache so the UI can observe growth & avoid /private/tmp permissions quirks.
        let tempDir = outputDirectory.appendingPathComponent("mist-tmp", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        args += ["--temporary-directory", tempDir.path]
        args += ["--export", exportURL.path]
        args += ["--output-directory", outputDirectory.path]
        args.append(search)
        args.append(contentsOf: outputTypes.map(\.rawValue))

        onOutputLine?(String(localized: "Administrator password required — mist downloads installers as root."))
        let pidFile = outputDirectory.appendingPathComponent("mist-download.pid")
        try await MistPrivilegedShellRunner.run(
            executable: exe,
            arguments: args,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            recursiveChownAfterSuccess: outputDirectory,
            pidFileURL: pidFile
        )
        return try parseRawJSONDict(at: exportURL)
    }

    /// `mist download firmware "<search>" --output-directory ... --export file.json`
    static func downloadFirmwareIPSW(
        search: String,
        outputDirectory: URL,
        exportURL: URL,
        includeBetas: Bool = false,
        forceOverwrite: Bool = false,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> [String: Any] {
        let exe = try BundledToolLocator.mistCLIExecutable()
        var args: [String] = ["download", "firmware"]
        if includeBetas {
            args.append("--include-betas")
        }
        if forceOverwrite {
            args.append("--force")
        }
        args += ["--export", exportURL.path]
        args += ["--output-directory", outputDirectory.path]
        args.append(search)

        try await ProcessRunner.runCollectingOutput(
            executableURL: exe,
            arguments: args,
            currentDirectoryURL: nil,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onStdoutLine: onOutputLine,
            onStderrLine: onOutputLine
        )
        return try parseRawJSONDict(at: exportURL)
    }

    // MARK: - Helpers

    /// Prefer Homebrew `mist` for privileged downloads (clean Swift rpaths); fall back to bundled binary.
    private static func mistExecutableForPrivilegedDownloads() throws -> URL {
        let candidates = ["/opt/homebrew/bin/mist", "/usr/local/bin/mist"]
        for path in candidates {
            let u = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: u.path) {
                return u
            }
        }
        return try BundledToolLocator.mistCLIExecutable()
    }

    private static func listInstallerArgs(exportURL: URL, includeBetas: Bool, catalog: Catalog?) -> [String] {
        var args: [String] = ["list", "installer", "--export", exportURL.path]
        appendInstallerCatalogURL(to: &args, catalog: catalog)
        if includeBetas {
            args.append("--include-betas")
        }
        return args
    }

    private static func listFirmwareArgs(exportURL: URL, includeBetas: Bool) -> [String] {
        var args: [String] = ["list", "firmware", "--export", exportURL.path]
        if includeBetas {
            args.append("--include-betas")
        }
        return args
    }

    private static func parseInstallerListJSON(at url: URL) throws -> [InstallerListItem] {
        let dict = try parseRawJSONDict(at: url)
        // Mist-cli JSON export shape may vary between versions. We do best-effort extraction.
        let array = (dict["installers"] as? [[String: Any]])
            ?? (dict["results"] as? [[String: Any]])
            ?? []
        return array.map { row in
            InstallerListItem(
                name: (row["name"] as? String) ?? (row["displayName"] as? String) ?? "macOS",
                version: (row["version"] as? String) ?? "",
                build: (row["build"] as? String) ?? "",
                sizeBytes: numberLike(row["size"] ?? row["sizeBytes"] ?? row["downloadSize"])?.int64Value,
                releaseDateISO8601: (row["releaseDate"] as? String) ?? (row["released"] as? String)
            )
        }
    }

    private static func parseFirmwareListJSON(at url: URL) throws -> [FirmwareListItem] {
        let dict = try parseRawJSONDict(at: url)
        let array = (dict["firmwares"] as? [[String: Any]])
            ?? (dict["ipsws"] as? [[String: Any]])
            ?? (dict["results"] as? [[String: Any]])
            ?? []
        return array.map { row in
            FirmwareListItem(
                name: (row["name"] as? String) ?? (row["displayName"] as? String) ?? "macOS",
                version: (row["version"] as? String) ?? "",
                build: (row["build"] as? String) ?? "",
                sizeBytes: numberLike(row["size"] ?? row["sizeBytes"] ?? row["downloadSize"])?.int64Value,
                releaseDateISO8601: (row["releaseDate"] as? String) ?? (row["released"] as? String),
                url: (row["url"] as? String) ?? (row["firmwareURL"] as? String)
            )
        }
    }

    private static func parseRawJSONDict(at url: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MistCLIToolError.invalidExportFile("mist export file missing or unreadable: \(url.path)")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw MistCLIToolError.invalidExportFile("mist export file is not valid JSON: \(url.lastPathComponent)")
        }
        if let dict = obj as? [String: Any] {
            return dict
        }
        // Some exports may be an array at top-level. Wrap it.
        if let arr = obj as? [[String: Any]] {
            return ["results": arr]
        }
        throw MistCLIToolError.invalidExportFile("mist export JSON has an unexpected shape: \(url.lastPathComponent)")
    }

    private static func numberLike(_ any: Any?) -> NSNumber? {
        if let n = any as? NSNumber { return n }
        if let s = any as? String, let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return NSNumber(value: d)
        }
        return nil
    }
}

