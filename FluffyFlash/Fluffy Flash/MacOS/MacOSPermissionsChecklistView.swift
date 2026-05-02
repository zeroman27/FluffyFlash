import AppKit
import SwiftUI

/// A small diagnostics panel that helps the user grant the required permissions
/// for macOS USB writing (privileged helper + privacy permissions).
struct MacOSPermissionsChecklistView: View {
    @State private var copied = false

    private var embeddedHelperPath: String { PrivilegedHelperClient.embeddedHelperURL.path }
    private var embeddedPlistPath: String { PrivilegedHelperClient.embeddedDaemonPlistURL.path }
    private var installedHelperPath: String { PrivilegedHelperClient.installedHelperURL.path }
    private var installedPlistPath: String { PrivilegedHelperClient.installedLaunchdPlistURL.path }

    var body: some View {
        MistSectionCard(title: String(localized: "Permissions check"), systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Label(String(localized: "Privileged helper"), systemImage: "lock.shield")
                            .font(WistFont.headline(12))
                        Spacer()
                        Text(PrivilegedHelperClient.isInstalled() ? String(localized: "Installed") : String(localized: "Not installed"))
                            .font(WistFont.caption(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(String(localized: "Embedded helper:"))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)

                    Text(embeddedHelperPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    Text(String(localized: "Embedded launchd plist:"))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)

                    Text(embeddedPlistPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    Text(String(localized: "Installed helper (after SMJobBless):"))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)

                    Text(installedHelperPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    Text(String(localized: "Installed launchd plist:"))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)

                    Text(installedPlistPath)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button {
                        PrivilegedHelperClient.openFullDiskAccessPrivacySettings()
                    } label: {
                        Label(String(localized: "Open Full Disk Access"), systemImage: "hand.raised.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        PrivilegedHelperClient.revealInstalledHelperInFinder()
                    } label: {
                        Label(String(localized: "Reveal installed helper"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installedHelperPath, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Label(copied ? String(localized: "Copied") : String(localized: "Copy installed helper path"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                Text(String(localized: "Tip: In Full Disk Access, click “+”, then press Cmd+Shift+G and paste the installed helper path to add it quickly."))
                    .font(WistFont.caption(10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

