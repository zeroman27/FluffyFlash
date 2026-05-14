//
//  WelcomePermissionsSheet.swift
//  Fluffy Flash
//
//  One-time (per app version) non-blocking checklist for macOS permissions after the launch gate.
//

import AppKit
import SwiftUI

struct WelcomePermissionsSheet: View {
    @ObservedObject var permissions: PermissionsService
    @Binding var isPresented: Bool
    /// `CFBundleShortVersionString` — stored when the user dismisses the sheet.
    let currentAppVersion: String

    @AppStorage(WistPreferences.Keys.welcomeShownVersion) private var welcomeShownVersion: String = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        FluffySheetChrome {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Welcome to Fluffy Flash"))
                    .font(WistFont.title(18))
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                Text(String(localized: "Grant the permissions you need now, or skip and open Settings later."))
                    .font(WistFont.caption(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                Divider().opacity(0.35)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(PermissionItem.allCases) { item in
                            welcomeRow(item: item)
                        }
                    }
                    .padding(16)
                }

                Divider().opacity(0.35)

                HStack(spacing: 10) {
                    Button(String(localized: "Skip for now")) {
                        markDismissed()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(String(localized: "Done")) {
                        markDismissed()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .fluffyPillow(cornerRadius: 22)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 480)
        .task {
            await permissions.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await permissions.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permissions.refresh() }
        }
    }

    private func markDismissed() {
        welcomeShownVersion = currentAppVersion
        isPresented = false
    }

    private func welcomeRow(item: PermissionItem) -> some View {
        let st = permissions.statuses[item] ?? .unknown
        return MistSectionCard(
            title: item.title,
            systemImage: statusIcon(st),
            iconTint: st == .granted ? .green : nil,
            iconAnimationValue: st.rawValue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.detail)
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusLabel(st))
                    .font(WistFont.caption(10))
                    .foregroundStyle(.tertiary)
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        Task { await permissions.grantFlow(for: item) }
                    } label: {
                        Text(String(localized: "Grant…"))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private func statusIcon(_ st: PermissionStatus) -> String {
        switch st {
        case .granted: return "checkmark.circle.fill"
        case .outdated: return "exclamationmark.triangle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .unknown: return "ellipsis.circle.fill"
        }
    }

    private func statusLabel(_ st: PermissionStatus) -> String {
        switch st {
        case .granted: return String(localized: "Granted")
        case .outdated: return String(localized: "Outdated")
        case .denied: return String(localized: "Denied or not installed")
        case .notDetermined: return String(localized: "Not determined")
        case .unknown: return String(localized: "Unknown — try Re-check in Settings")
        }
    }
}
