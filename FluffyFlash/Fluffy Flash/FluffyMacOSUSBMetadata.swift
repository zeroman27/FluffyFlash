//
//  FluffyMacOSUSBMetadata.swift
//  Fluffy Flash
//
//  Sidecar JSON on the macOS installer USB volume (written after createinstallmedia).
//

import Foundation

/// Written to `FluffyFlash.macos.meta.json` at the root of the installer volume.
struct FluffyMacOSUSBMetadata: Codable, Equatable, Hashable, Sendable {
    static let fileName = "FluffyFlash.macos.meta.json"
    static let currentSchema = 1

    var schemaVersion: Int
    /// ISO8601 with fractional seconds.
    var writtenAt: String
    /// Fluffy / host app marketing version.
    var fluffyAppVersion: String
    var fluffyAppBuild: String?
    /// Display name of the installer app (e.g. "Install macOS Sequoia").
    var installerDisplayName: String
    var installerShortVersion: String?
    var installerBundleVersion: String?
    /// User-visible dotted version parsed from the installer `.app` bundle name (e.g. `26.4.1` in `… 26.4.1-25E253.app`).
    /// Apple often leaves `CFBundleShortVersionString` on an older internal train while the folder name matches marketing.
    var installerMarketingVersion: String?
    /// Apple build train parsed from the bundle name suffix (e.g. `25E253`), comparable to Mist’s `build`.
    var installerAppleBuildFromName: String?
    /// `DTPlatformVersion` from `Info.plist` (e.g. `26.4`) — fallback when marketing cannot be parsed from the name.
    var installerDTPlatformVersion: String?

    init(
        writtenAt: Date = Date(),
        fluffyAppVersion: String,
        fluffyAppBuild: String?,
        installerDisplayName: String,
        installerShortVersion: String?,
        installerBundleVersion: String?,
        installerMarketingVersion: String? = nil,
        installerAppleBuildFromName: String? = nil,
        installerDTPlatformVersion: String? = nil
    ) {
        self.schemaVersion = Self.currentSchema
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.writtenAt = f.string(from: writtenAt)
        self.fluffyAppVersion = fluffyAppVersion
        self.fluffyAppBuild = fluffyAppBuild
        self.installerDisplayName = installerDisplayName
        self.installerShortVersion = installerShortVersion
        self.installerBundleVersion = installerBundleVersion
        self.installerMarketingVersion = installerMarketingVersion
        self.installerAppleBuildFromName = installerAppleBuildFromName
        self.installerDTPlatformVersion = installerDTPlatformVersion
    }

    /// Builds metadata after `createinstallmedia` by preferring the **installer `.app` on the USB volume**
    /// (authoritative for version strings). Falls back to the host-cache `installerAppURL` if none found.
    static func makeAfterWrite(volumeRoot: URL, fallbackInstallerAppURL: URL, writtenAt: Date = Date()) throws -> FluffyMacOSUSBMetadata {
        if let onStick = findInstallAssistantAppAtVolumeRoot(volumeRoot) {
            return try make(installerAppURL: onStick, writtenAt: writtenAt)
        }
        return try make(installerAppURL: fallbackInstallerAppURL, writtenAt: writtenAt)
    }

    /// Reads installer `Contents/Info.plist` and host app version from `Bundle.main`.
    static func make(installerAppURL: URL, writtenAt: Date = Date()) throws -> FluffyMacOSUSBMetadata {
        let plistURL = installerAppURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw FluffyMacOSUSBMetadataError.invalidInstallerPlist
        }
        let display =
            plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? installerAppURL.deletingPathExtension().lastPathComponent
        let short = plist["CFBundleShortVersionString"] as? String
        let bundle = plist["CFBundleVersion"] as? String
        let platform = plist["DTPlatformVersion"] as? String
        let parsed = Self.parseMarketingAndBuildFromBundleName(installerAppURL)
        let main = Bundle.main
        let appVer = main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let appBuild = main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return FluffyMacOSUSBMetadata(
            writtenAt: writtenAt,
            fluffyAppVersion: appVer,
            fluffyAppBuild: appBuild,
            installerDisplayName: display,
            installerShortVersion: short,
            installerBundleVersion: bundle,
            installerMarketingVersion: parsed.marketing,
            installerAppleBuildFromName: parsed.appleBuild,
            installerDTPlatformVersion: platform
        )
    }

    /// Parses trailing `(\d+.\d+(.d+)?)-(buildTrain)` from the `.app` folder name (Apple’s convention for recent installers).
    private static func parseMarketingAndBuildFromBundleName(_ installerAppURL: URL) -> (marketing: String?, appleBuild: String?) {
        let base = installerAppURL.deletingPathExtension().lastPathComponent
        guard let re = try? NSRegularExpression(pattern: #"(\d+\.\d+(?:\.\d+)?)-([0-9][0-9A-Z]+)$"#, options: []) else {
            return (nil, nil)
        }
        let range = NSRange(location: 0, length: (base as NSString).length)
        guard let match = re.firstMatch(in: base, options: [], range: range),
              match.numberOfRanges >= 3,
              let r1 = Range(match.range(at: 1), in: base),
              let r2 = Range(match.range(at: 2), in: base)
        else {
            return (nil, nil)
        }
        return (String(base[r1]), String(base[r2]))
    }

    func write(to volumeRoot: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(self)
        let url = volumeRoot.appendingPathComponent(Self.fileName)
        try data.write(to: url, options: .atomic)
    }

    static func read(from volumeRoot: URL) -> FluffyMacOSUSBMetadata? {
        let url = volumeRoot.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FluffyMacOSUSBMetadata.self, from: data)
    }

    /// Locates `*.app` at the volume root that contains `createinstallmedia` (what Apple leaves after `createinstallmedia`).
    static func installAssistantAppBundle(atVolumeRoot volumeRoot: URL) -> URL? {
        findInstallAssistantAppAtVolumeRoot(volumeRoot)
    }

    /// Among several mounts for the same whole disk (EFI vs installer partition), pick the one that holds the installer `.app`.
    static func preferredVolumeRootForInstaller(among mountRoots: [URL]) -> URL? {
        guard !mountRoots.isEmpty else { return nil }
        for root in mountRoots {
            if installAssistantAppBundle(atVolumeRoot: root) != nil {
                return root
            }
        }
        return mountRoots.first
    }

    private static func findInstallAssistantAppAtVolumeRoot(_ volumeRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: volumeRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let apps = urls.filter { $0.pathExtension.lowercased() == "app" }
        let valid = apps.filter {
            fm.isExecutableFile(atPath: $0.appendingPathComponent("Contents/Resources/createinstallmedia").path)
        }
        guard !valid.isEmpty else { return nil }
        if valid.count == 1 { return valid[0] }
        // Multiple matches are unusual; pick the most recently modified bundle.
        return valid.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    /// One-line subtitle for drive lists (Library / Home).
    var summarySubtitle: String {
        let verHead = firstNonEmptyTrimmed(installerMarketingVersion, installerDTPlatformVersion, installerShortVersion)
        let buildTail = firstNonEmptyTrimmed(installerAppleBuildFromName, installerBundleVersion)
        let tail = [verHead, buildTail].compactMap { $0 }.joined(separator: " · ")
        if tail.isEmpty {
            return installerDisplayName
        }
        return "\(installerDisplayName) · \(tail)"
    }

    private func firstNonEmptyTrimmed(_ candidates: String?...) -> String? {
        for c in candidates {
            guard let t = c?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
            return t
        }
        return nil
    }
}

private enum FluffyMacOSUSBMetadataError: LocalizedError {
    case invalidInstallerPlist

    var errorDescription: String? {
        switch self {
        case .invalidInstallerPlist:
            return String(localized: "Could not read the installer app Info.plist.")
        }
    }
}
