//
//  FluffyFinderIconAutomation.swift
//  Fluffy Flash
//
//  Centralizes Finder volume icon updates so Settings and post-write hooks stay in sync.
//

import Foundation

@MainActor
enum FluffyFinderIconAutomation {
    private static let applyVolumeIconsKey = "fluffy.applyVolumeIconsToFluffyDrives"
    private static let iconStyleKey = FluffyUSBIconStyle.appStorageKey

    /// Applies the user’s chosen artwork to every connected drive that has Fluffy sidecar metadata,
    /// but only when **Also set this icon in Finder** is enabled (same rule as Settings → Apply now).
    static func applyToConnectedFluffyDrivesIfSettingEnabled() async {
        guard UserDefaults.standard.bool(forKey: applyVolumeIconsKey) else { return }
        let dm = DiskManager()
        await dm.refresh()
        let globalRaw = UserDefaults.standard.string(forKey: iconStyleKey)
        for d in dm.drives where d.hasFluffySidecar {
            guard let mount = d.mountPoint else { continue }
            let overrideRaw = FluffyDriveIconOverrides.overrideStyleRawValue(for: d.deviceIdentifier)
            let raw = overrideRaw ?? globalRaw ?? FluffyUSBIconStyle.defaultStyle.rawValue
            let style = FluffyUSBIconStyle.resolve(rawValue: raw)
            try? FluffyVolumeIconManager.setVolumeIcon(style: style, mountPoint: mount)
        }
    }

    /// Finder often ignores the first `NSWorkspace.setIcon` immediately after `createinstallmedia` or heavy I/O.
    /// Call after a successful USB write so the custom icon reliably appears without asking the user to flash again.
    static func reapplyAfterUSBWriteBestEffort() async {
        guard UserDefaults.standard.bool(forKey: applyVolumeIconsKey) else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await applyToConnectedFluffyDrivesIfSettingEnabled()
    }
}
