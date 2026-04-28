//
//  FluffyVolumeIconManager.swift
//  Fluffy Flash
//
//  Finder-level volume icon customization for Fluffy-formatted drives.
//

import AppKit
import Foundation

enum FluffyVolumeIconError: LocalizedError {
    case missingMountPoint
    case missingImageAsset(String)
    case setIconFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingMountPoint:
            return String(localized: "This drive is not mounted, so its icon cannot be changed.")
        case .missingImageAsset(let name):
            return String(format: String(localized: "Missing icon asset: %@"), name)
        case .setIconFailed(let path):
            return String(format: String(localized: "Could not update the Finder icon for %@."), path)
        }
    }
}

/// Applies a custom Finder icon to a mounted volume (or removes it).
///
/// Implementation note: `NSWorkspace.setIcon` sets the `kHasCustomIcon` FinderInfo
/// flag and writes the icon data in a Finder-compatible way. This is the most
/// robust approach without relying on developer-only tools like `SetFile`.
@MainActor
enum FluffyVolumeIconManager {
    static func setVolumeIcon(style: FluffyUSBIconStyle, mountPoint: URL) throws {
        guard let img = NSImage(named: style.assetName) else {
            throw FluffyVolumeIconError.missingImageAsset(style.assetName)
        }
        let ok = NSWorkspace.shared.setIcon(img, forFile: mountPoint.path, options: [])
        guard ok else { throw FluffyVolumeIconError.setIconFailed(mountPoint.path) }
    }

    static func clearVolumeIcon(mountPoint: URL) throws {
        let ok = NSWorkspace.shared.setIcon(nil, forFile: mountPoint.path, options: [])
        guard ok else { throw FluffyVolumeIconError.setIconFailed(mountPoint.path) }
    }
}

// MARK: - Per-drive overrides store

/// Stores per-drive icon overrides by whole-disk id (e.g. `disk7`).
/// Keeps data small and human-readable in `UserDefaults`.
enum FluffyDriveIconOverrides {
    private static let key = "fluffy.driveIconOverrides.v1"

    static func read() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func overrideStyleRawValue(for deviceIdentifier: String) -> String? {
        read()[deviceIdentifier]
    }

    static func setOverride(deviceIdentifier: String, styleRawValue: String) {
        var map = read()
        map[deviceIdentifier] = styleRawValue
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clearOverride(deviceIdentifier: String) {
        var map = read()
        map.removeValue(forKey: deviceIdentifier)
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

