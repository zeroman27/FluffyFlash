//
//  WistNotificationCenter.swift
//  Fluffy Flash
//
//  System notifications + Dock badge for finished writes. The whole feature is
//  gated by `WistPreferences.notifyOnComplete` so users can opt out.
//

import AppKit
import Foundation
import UserNotifications

@MainActor
enum WistNotificationCenter {

    private static var permissionRequested = false

    /// Ensure UN authorisation has been requested at least once. Idempotent.
    static func ensurePermissionRequested() {
        guard WistPreferences.notifyOnComplete, !permissionRequested else { return }
        permissionRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyWriteSucceeded(driveCount: Int) {
        guard WistPreferences.notifyOnComplete else { return }
        ensurePermissionRequested()
        let body: String
        if driveCount <= 1 {
            body = String(localized: "Your USB drive is ready.")
        } else {
            body = String(format: String(localized: "%lld drives are ready."), Int64(driveCount))
        }
        post(title: String(localized: "Fluffy Flash — done"), body: body, sound: .default)
    }

    static func notifyWriteFailed(message: String) {
        guard WistPreferences.notifyOnComplete else { return }
        ensurePermissionRequested()
        post(title: String(localized: "Fluffy Flash — failed"), body: message, sound: .defaultCritical)
    }

    /// Sets `n` (or clears when `n == 0`) on the Dock tile so users see active jobs at a glance.
    static func setDockBadge(activeWrites: Int) {
        let tile = NSApp.dockTile
        if activeWrites > 0 {
            tile.badgeLabel = "\(activeWrites)"
        } else {
            tile.badgeLabel = nil
        }
        tile.display()
    }

    private static func post(title: String, body: String, sound: UNNotificationSound) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
