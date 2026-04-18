//
//  UUPISOConverter.swift
//  Wist
//
//  Runs the official [uup-dump/converter](https://git.uupdump.net/uup-dump/converter) `convert.sh`
//  (same script CrystalFetch uses via submodule). Output `.iso` is created in the working directory.
//

import Foundation

enum UUPISOConverterError: LocalizedError {
    case scriptMissing
    case missingDependencies([String])
    case isoNotFoundAfterConversion

    var errorDescription: String? {
        switch self {
        case .scriptMissing:
            return String(localized: "convert.sh was not found in the app bundle.")
        case .missingDependencies(let names):
            return String(
                format: String(localized: "Missing tools: %@. Release builds bundle them under Resources/Tools/bin. Or install manually: brew install aria2 cabextract wimlib cdrtools and chntpw (see README)."),
                names.joined(separator: ", ")
            )
        case .isoNotFoundAfterConversion:
            return String(localized: "The script finished, but no .iso was found in the output folder.")
        }
    }
}

enum UUPISOConverter: Sendable {

    /// Same checks as `convert.sh` (aria2c is required even when files are already downloaded).
    static func missingDependencyDescriptions() -> [String] {
        var out: [String] = []
        if !HostToolPaths.hasExecutable(named: "aria2c") { out.append(String(localized: "aria2 (aria2c)")) }
        if !HostToolPaths.hasExecutable(named: "cabextract") { out.append(String(localized: "cabextract")) }
        if !HostToolPaths.hasExecutable(named: "wimlib-imagex") { out.append(String(localized: "wimlib (wimlib-imagex)")) }
        if !HostToolPaths.hasExecutable(named: "chntpw") { out.append(String(localized: "chntpw (Apple Silicon: brew tap minacle/chntpw && brew install minacle/chntpw/chntpw)")) }
        if !HostToolPaths.hasMkIsoTool() { out.append(String(localized: "cdrtools (mkisofs) or genisoimage")) }
        return out
    }

    static func bundledConvertScriptURL() throws -> URL {
        let bundle = Bundle.main
        let manualNested = bundle.bundleURL.appendingPathComponent("Contents/Resources/ThirdParty/UUPConverter/convert.sh")
        let candidates: [URL?] = [
            bundle.url(forResource: "convert", withExtension: "sh", subdirectory: "ThirdParty/UUPConverter"),
            bundle.url(forResource: "convert", withExtension: "sh"),
            FileManager.default.isReadableFile(atPath: manualNested.path) ? manualNested : nil,
        ]
        for u in candidates {
            if let u, FileManager.default.isReadableFile(atPath: u.path) {
                return u
            }
        }
        throw UUPISOConverterError.scriptMissing
    }

    /// - Parameters:
    ///   - uupDirectory: Folder with downloaded UUP files (e.g. `…/UUP/<uuid>`).
    ///   - outputDirectory: Working directory for the script; `.iso` and temp `ISODIR` are created here.
    ///   - compression: `wim` or `esd` (passed to `convert.sh`).
    static func convert(
        uupDirectory: URL,
        outputDirectory: URL,
        compression: String = "wim",
        virtualEditions: Bool = false,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let missing = missingDependencyDescriptions()
        if !missing.isEmpty {
            throw UUPISOConverterError.missingDependencies(missing)
        }
        let comp = compression.lowercased() == "esd" ? "esd" : "wim"

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let beforeISOs = Set(isoFiles(in: outputDirectory))
        let script = try bundledConvertScriptURL()

        let env = HostToolPaths.environmentForBundledAndHostCLI()

        try await ProcessRunner.runCollectingOutput(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: [
                script.path,
                comp,
                uupDirectory.path,
                virtualEditions ? "1" : "0",
            ],
            currentDirectoryURL: outputDirectory,
            environment: env,
            onStdoutLine: onLine,
            onStderrLine: onLine
        )

        let after = isoFiles(in: outputDirectory)
        let newOnes = after.filter { !beforeISOs.contains($0) }
        if let iso = newOnes.max(by: { modDate($0) < modDate($1) }) {
            return iso
        }
        if let iso = after.max(by: { modDate($0) < modDate($1) }) {
            return iso
        }
        throw UUPISOConverterError.isoNotFoundAfterConversion
    }

    private static func isoFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?
            .filter { $0.pathExtension.lowercased() == "iso" } ?? []
    }

    private static func modDate(_ url: URL) -> Date {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return v?.contentModificationDate ?? .distantPast
    }
}
