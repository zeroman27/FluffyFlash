//
//  PermissionsService.swift
//  Fluffy Flash
//
//  Aggregates macOS permission state for Settings + welcome checklist (helper, FDA, notifications, removable volumes).
//

import AppKit
import Combine
import Foundation
import UserNotifications

enum PermissionItem: String, CaseIterable, Identifiable, Hashable, Sendable {
    case privilegedHelper
    case fullDiskAccess
    case notifications
    case removableVolumes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privilegedHelper:
            return String(localized: "Privileged helper")
        case .fullDiskAccess:
            return String(localized: "Full Disk Access")
        case .notifications:
            return String(localized: "Notifications")
        case .removableVolumes:
            return String(localized: "Removable volumes")
        }
    }

    var detail: String {
        switch self {
        case .privilegedHelper:
            return String(localized: "Required to erase volumes and run privileged USB workflows.")
        case .fullDiskAccess:
            return String(localized: "Lets the app verify system paths and complete some diagnostics.")
        case .notifications:
            return String(localized: "Optional alerts when a long write finishes.")
        case .removableVolumes:
            return String(localized: "Read installer metadata and apply Finder icons on USB volumes.")
        }
    }
}

enum PermissionStatus: String, Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case unknown

    static func fromNotificationAuthorization(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .provisional:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }
}

@MainActor
final class PermissionsService: ObservableObject {

    /// Test hook: when set, `refresh()` uses this instead of querying `UNUserNotificationCenter`.
    var notificationAuthorizationOverride: (@Sendable () async -> UNAuthorizationStatus)?

    @Published private(set) var statuses: [PermissionItem: PermissionStatus] = [:]
    /// Set when `SMJobBless` / `prepareSession()` fails so Settings can show a short message (cleared on success).
    @Published private(set) var lastPrivilegedHelperInstallError: String?

    init() {}

    func refresh() async {
        var next: [PermissionItem: PermissionStatus] = [:]

        next[.privilegedHelper] = await refreshPrivilegedHelper()
        next[.fullDiskAccess] = refreshFullDiskAccess()
        next[.notifications] = await refreshNotifications()
        next[.removableVolumes] = refreshRemovableVolumes()

        statuses = next
    }

    private func refreshPrivilegedHelper() async -> PermissionStatus {
        guard PrivilegedHelperClient.isInstalled() else { return .denied }

        // Right after SMJobBless, launchd may not accept XPC yet — retry instead of one flaky ping.
        for attempt in 0 ..< 8 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            if await Self.pingPrivilegedHelper() {
                return .granted
            }
        }

        // Binaries and launchd plist are present — treat as OK even if XPC stayed flaky (rare).
        return PrivilegedHelperClient.isInstalled() ? .granted : .denied
    }

    /// Lightweight XPC round-trip. Uses a generous timeout so the first connection after install can complete.
    private static func pingPrivilegedHelper() async -> Bool {
        await withCheckedContinuation { continuation in
            var finished = false
            let lock = NSLock()
            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: value)
            }

            let connection = PrivilegedHelperClient.connection()
            defer { connection.invalidate() }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                finish(false)
            }) as? PrivilegedHelperProtocol else {
                finish(false)
                return
            }

            proxy.runCommand(
                executablePath: "/usr/bin/true",
                arguments: [],
                environment: [:]
            ) { _, _, _ in
                finish(true)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.75) {
                finish(false)
            }
        }
    }

    private func refreshFullDiskAccess() -> PermissionStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"),
        ]
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let fh = try FileHandle(forReadingFrom: url)
                    try? fh.close()
                    return .granted
                } catch {
                    return .denied
                }
            }
        }
        return .unknown
    }

    private func refreshNotifications() async -> PermissionStatus {
        let status: UNAuthorizationStatus
        if let notificationAuthorizationOverride {
            status = await notificationAuthorizationOverride()
        } else {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            status = settings.authorizationStatus
        }
        return PermissionStatus.fromNotificationAuthorization(status)
    }

    private func refreshRemovableVolumes() -> PermissionStatus {
        let path = "/Volumes"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .unknown
        }
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: path)
            if !names.isEmpty {
                return .granted
            }
            // Empty `/Volumes` is unusual on a normal macOS install; treat as uncertain access.
            if FileManager.default.fileExists(atPath: "\(path)/Macintosh HD") {
                return .granted
            }
            return .unknown
        } catch {
            return .denied
        }
    }

    func openSystemSettings(for item: PermissionItem) {
        let urls: [URL] = {
            switch item {
            case .privilegedHelper:
                return [
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?General")!,
                ]
            case .fullDiskAccess:
                return [
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!,
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess")!,
                ]
            case .notifications:
                return [
                    URL(string: "x-apple.systempreferences:com.apple.Notifications")!,
                ]
            case .removableVolumes:
                return [
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_RemovableVolumes")!,
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!,
                ]
            }
        }()
        for url in urls {
            if NSWorkspace.shared.open(url) { break }
        }
    }

    /// Triggers prompts / TCC registration where applicable, then opens the matching pane.
    /// **Privileged helper:** installs via `SMJobBless` (system admin password dialog) — there is no plist toggle in Settings for this.
    func grantFlow(for item: PermissionItem) async {
        switch item {
        case .privilegedHelper:
            lastPrivilegedHelperInstallError = nil
            do {
                try await PrivilegedHelperClient.prepareSession()
                lastPrivilegedHelperInstallError = nil
                // Give launchd a beat to register the Mach service before we ping.
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                lastPrivilegedHelperInstallError = error.localizedDescription
            }
            await refresh()
            return
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .fullDiskAccess:
            _ = refreshFullDiskAccess()
        case .removableVolumes:
            _ = refreshRemovableVolumes()
        }
        openSystemSettings(for: item)
        await refresh()
    }
}
