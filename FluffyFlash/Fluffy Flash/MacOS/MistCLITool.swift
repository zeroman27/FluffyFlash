//
//  MistCLITool.swift
//  Wist
//

import Foundation

/// Collects streamed `mist` lines so privileged-download failures aren't opaque `exitCode` only.
private final class MistOutputTailBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines: Int

    init(maxLines: Int = 48) {
        self.maxLines = maxLines
    }

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        let s = lines.joined(separator: "\n")
        lock.unlock()
        return s
    }
}

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

        // Run `mist download installer` through the privileged helper, not `osascript`, so the
        // entire macOS pipeline shares a single approval (the helper install) instead of asking
        // the user for administrator credentials each phase.
        try await PrivilegedHelperClient.prepareSession()
        onOutputLine?(String(localized: "Running mist as root via the privileged helper."))

        let tail = MistOutputTailBuffer()
        let exitCode = try await PrivilegedHelperClient.runCommandStreaming(
            executablePath: exe.path,
            arguments: args,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onLine: { line in
                tail.append(line)
                onOutputLine?(line)
            }
        )
        if exitCode != 0 {
            let detail = tail.joined()
            let hint = detail.isEmpty ? "" : "\n\(detail)\n"
            throw ProcessRunnerError.failed(
                exitCode: exitCode,
                stderr: "\(hint)mist download installer failed (\(exitCode))."
            )
        }

        try await Self.chownOutputDirectoryToInvoker(outputDirectory, onOutputLine: onOutputLine)
        return try parseRawJSONDict(at: exportURL)
    }

    /// Root-owned cache tree → revert to the GUI user (same as after a successful `mist download`).
    static func chownOutputDirectoryToInvoker(_ outputDirectory: URL, onOutputLine: ((String) -> Void)? = nil) async throws {
        let runUID = getuid()
        let runGID = getgid()
        let chownExit = try await PrivilegedHelperClient.runCommandStreaming(
            executablePath: "/usr/sbin/chown",
            arguments: ["-R", "\(runUID):\(runGID)", outputDirectory.path],
            environment: [:],
            onLine: { line in onOutputLine?(line) }
        )
        if chownExit != 0 {
            onOutputLine?("warning: chown returned \(chownExit) for \(outputDirectory.path)")
        }
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

