//
//  WistApp.swift
//  Wist
//

import AppKit
import Combine
import SwiftUI

@main
struct WistApp: App {
    @NSApplicationDelegateAdaptor(WistAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppLaunchGateView()
                .onReceive(NotificationCenter.default.publisher(for: .wistOpenISO)) { note in
                    if let url = note.object as? URL {
                        WistOpenISOBridge.shared.lastURL = url
                    }
                }
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…")) {
                    FluffySparkleController.shared.checkForUpdates()
                }
                .disabled(!FluffySparkleController.isConfigured)
                .help(
                    FluffySparkleController.isConfigured
                        ? String(localized: "Download updates published to the Sparkle appcast.")
                        : String(localized: "Add SUPublicEDKey to the app Info.plist (see docs/Sparkle.md).")
                )
            }
        }
    }
}

extension Notification.Name {
    /// Posted when macOS hands the app an `.iso` URL (drop on Dock, double-click, …).
    static let wistOpenISO = Notification.Name("wist.openISO")
}

/// Tiny actor-isolated relay so any view can pull the most recent dropped URL.
@MainActor
final class WistOpenISOBridge: ObservableObject {
    static let shared = WistOpenISOBridge()
    @Published var lastURL: URL?
}

/// Forwards `application(_:open:)` events into a NotificationCenter signal so
/// SwiftUI views can react without coupling to AppKit.
final class WistAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FluffySparkleController.shared.prepareIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "iso" {
            NotificationCenter.default.post(name: .wistOpenISO, object: url)
        }
    }
}
