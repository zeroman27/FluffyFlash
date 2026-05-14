//
//  FluffySparkleController.swift
//  Fluffy Flash
//
//  Wraps Sparkle 2 (SPUStandardUpdaterController). Requires `SUFeedURL` and
//  `SUPublicEDKey` in the app Info.plist — see `docs/Sparkle.md`.
//

import AppKit
import Sparkle

/// Owns Sparkle’s standard updater UI and background checks.
@MainActor
final class FluffySparkleController {
    static let shared = FluffySparkleController()

    /// Both keys must be non-empty for Sparkle to run (see `docs/Sparkle.md`).
    static var isConfigured: Bool {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard let feed, !feed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return true
    }

    private var standardController: SPUStandardUpdaterController?

    private init() {}

    /// Call once after launch so Sparkle can schedule automatic checks.
    func prepareIfNeeded() {
        guard Self.isConfigured else { return }
        guard standardController == nil else { return }
        standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        prepareIfNeeded()
        standardController?.checkForUpdates(nil)
    }
}
