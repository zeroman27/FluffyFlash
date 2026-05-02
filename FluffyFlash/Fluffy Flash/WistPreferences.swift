//
//  WistPreferences.swift
//  Fluffy Flash
//
//  Centralised access to user-tunable preferences that live in `UserDefaults`.
//  SwiftUI views still bind through `@AppStorage`, but everything outside the
//  view layer (pickers, pipelines, helpers) reads/writes through this enum so
//  the keys live in one place.
//

import Foundation

enum WistPreferences {

    enum Keys {
        static let preferredISOFolder = "fluffy.preferredISOFolder"
        static let autoEjectAfterWrite = "fluffy.autoEjectAfterWrite"
        static let notifyOnComplete = "fluffy.notifyOnComplete"
        static let productionLineMode = "fluffy.productionLineMode"
        /// Semver of the app build for which the welcome permissions sheet was dismissed (repeat on version bump).
        static let welcomeShownVersion = "fluffy.welcomeShownVersion"
    }

    /// User-selected default folder for the "Choose ISO…" picker.
    /// `nil` means we fall back to the app cache root (`WistCache.uupRootDirectory`).
    static var preferredISOFolder: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: Keys.preferredISOFolder), !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            if let url = newValue {
                UserDefaults.standard.set(url.path, forKey: Keys.preferredISOFolder)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.preferredISOFolder)
            }
        }
    }

    /// Effective starting directory for ISO pickers.
    static func isoPickerStartingDirectory() -> URL {
        if let custom = preferredISOFolder, FileManager.default.fileExists(atPath: custom.path) {
            return custom
        }
        let cache = WistCache.uupRootDirectory
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return cache
    }

    /// Whether the writer ejects the volume after a successful write.
    static var autoEjectAfterWrite: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoEjectAfterWrite) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoEjectAfterWrite) }
    }

    /// Whether to post a system notification when a write finishes.
    static var notifyOnComplete: Bool {
        get { UserDefaults.standard.object(forKey: Keys.notifyOnComplete) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.notifyOnComplete) }
    }

    /// Whether to auto-flash a freshly inserted blank USB using the last config.
    static var productionLineMode: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.productionLineMode) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.productionLineMode) }
    }
}
