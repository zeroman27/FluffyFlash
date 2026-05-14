//
//  FluffySystemDoctor.swift
//  Fluffy Flash
//
//  Read-only diagnostics service for the Settings → System status card.
//  Aggregates checks for bundled CLI tools, macOS permissions, the subprocess
//  environment seen by `convert.sh`, and free space on the cache volume.
//
//  Auto-fixes are intentionally limited to safe, user-scoped actions
//  (`PermissionsService.grantFlow`, Reveal in Finder, opening the cache card).
//  This service never modifies the contents of the .app bundle, because doing
//  so would invalidate the codesignature.
//

import AppKit
import Combine
import Darwin
import Foundation

// MARK: - Public types

enum SystemCheckStatus: Equatable, Sendable {
    case ok
    case warning(String)
    case failed(String)
    case info(String)

    var isProblem: Bool {
        switch self {
        case .failed: return true
        case .warning: return true
        case .ok, .info: return false
        }
    }

    /// Severity used to roll-up section status (failed > warning > info > ok).
    var sortKey: Int {
        switch self {
        case .failed: return 3
        case .warning: return 2
        case .info: return 1
        case .ok: return 0
        }
    }
}

/// A safe, user-scoped repair action that the System status card can offer.
enum SystemFixAction: Equatable, Sendable {
    /// Delegate to `PermissionsService.grantFlow(for:)`.
    case grantPermission(PermissionItem)
    /// Reveal the .app bundle in Finder so the user can drag it to /Applications.
    case revealAppBundle
    /// Reveal a specific URL in Finder (e.g. installed helper).
    case revealURL(URL)
    /// Copy a shell command to the clipboard (e.g. `xattr -dr com.apple.quarantine ...`).
    case copyShellCommand(String, label: String)
    /// Open Apple System Settings via deep link.
    case openSystemSettings(URL)
}

struct SystemCheckItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let status: SystemCheckStatus
    let fixAction: SystemFixAction?
    let fixLabel: String?
}

struct SystemStatusSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let items: [SystemCheckItem]

    /// Worst-case status across items in the section.
    var rollupStatus: SystemCheckStatus {
        items.map(\.status).max(by: { $0.sortKey < $1.sortKey }) ?? .ok
    }
}

struct SystemStatusReport: Equatable, Sendable {
    let generatedAt: Date
    let sections: [SystemStatusSection]

    func plainTextReport() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        var lines: [String] = []
        lines.append("Fluffy Flash — System status (\(formatter.string(from: generatedAt)))")
        for section in sections {
            lines.append("")
            lines.append("[\(section.title)] — \(SystemStatusReport.tag(for: section.rollupStatus))")
            for item in section.items {
                lines.append("  \(SystemStatusReport.tag(for: item.status)) \(item.title)")
                if let d = item.detail, !d.isEmpty {
                    lines.append("      \(d)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func tag(for status: SystemCheckStatus) -> String {
        switch status {
        case .ok: return "[ ok ]"
        case .warning(let m): return "[warn] \(m)"
        case .failed(let m): return "[fail] \(m)"
        case .info(let m): return "[info] \(m)"
        }
    }
}

// MARK: - Service

@MainActor
final class FluffySystemDoctor: ObservableObject {

    @Published private(set) var report: SystemStatusReport?
    @Published private(set) var isRunning = false

    let permissions: PermissionsService

    init(permissions: PermissionsService? = nil) {
        self.permissions = permissions ?? PermissionsService()
    }

    /// Executes every check sequentially. Idempotent — calling twice replaces
    /// the previous report.
    func runDiagnostics() async {
        if isRunning { return }
        isRunning = true
        defer { isRunning = false }

        await permissions.refresh()

        let bundled = await collectBundledToolsSection()
        let perms = collectPermissionsSection()
        let environment = collectEnvironmentSection()
        let storage = collectStorageSection()

        report = SystemStatusReport(
            generatedAt: Date(),
            sections: [bundled, perms, environment, storage]
        )
    }

    /// Performs the safe portion of a fix action. Permission-grant flows route
    /// through `PermissionsService.grantFlow(for:)` (which itself opens System
    /// Settings or invokes SMJobBless). Returns `true` when something happened.
    @discardableResult
    func performFix(_ action: SystemFixAction) async -> Bool {
        switch action {
        case .grantPermission(let item):
            await permissions.grantFlow(for: item)
            return true
        case .revealAppBundle:
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            return true
        case .revealURL(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        case .copyShellCommand(let command, _):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(command, forType: .string)
            return true
        case .openSystemSettings(let url):
            NSWorkspace.shared.open(url)
            return true
        }
    }

    // MARK: - Sections

    private struct BundledToolSpec {
        let name: String
        let symbol: String
        let title: String
        let isCritical: Bool
    }

    private static let bundledToolSpecs: [BundledToolSpec] = [
        BundledToolSpec(name: "aria2c", symbol: "arrow.down.circle", title: "aria2c (UUP downloader)", isCritical: true),
        BundledToolSpec(name: "cabextract", symbol: "shippingbox", title: "cabextract", isCritical: true),
        BundledToolSpec(name: "wimlib-imagex", symbol: "doc.zipper", title: "wimlib-imagex", isCritical: true),
        BundledToolSpec(name: "chntpw", symbol: "person.badge.key", title: "chntpw", isCritical: true),
        BundledToolSpec(name: "xorriso", symbol: "opticaldisc", title: "xorriso", isCritical: true),
        BundledToolSpec(name: "mkisofs", symbol: "opticaldisc.fill", title: "mkisofs (xorriso wrapper)", isCritical: false),
        BundledToolSpec(name: "genisoimage", symbol: "opticaldisc.fill", title: "genisoimage (xorriso wrapper)", isCritical: false),
        BundledToolSpec(name: "mist", symbol: "macbook", title: "mist (macOS installer downloader)", isCritical: false),
    ]

    private func collectBundledToolsSection() async -> SystemStatusSection {
        var items: [SystemCheckItem] = []
        for spec in Self.bundledToolSpecs {
            items.append(checkBundledTool(spec))
        }
        items.append(checkConvertScript())
        items.append(checkBundledLibDirectory())

        return SystemStatusSection(
            id: "bundled-tools",
            title: String(localized: "Bundled CLI tools"),
            symbol: "shippingbox.fill",
            items: items
        )
    }

    private func checkBundledTool(_ spec: BundledToolSpec) -> SystemCheckItem {
        let fm = FileManager.default
        guard let url = BundledToolLocator.urlForBundledCLI(named: spec.name) else {
            return SystemCheckItem(
                id: "tool.\(spec.name)",
                title: spec.title,
                detail: String(localized: "Not found in app bundle."),
                status: spec.isCritical
                    ? .failed(String(localized: "Missing"))
                    : .warning(String(localized: "Missing")),
                fixAction: .revealAppBundle,
                fixLabel: String(localized: "Reveal app bundle")
            )
        }
        if !fm.isExecutableFile(atPath: url.path) {
            let cmd = "chmod +x \"\(url.path)\""
            return SystemCheckItem(
                id: "tool.\(spec.name)",
                title: spec.title,
                detail: String(format: String(localized: "Not executable: %@"), url.path),
                status: .failed(String(localized: "Not executable")),
                fixAction: .copyShellCommand(cmd, label: String(localized: "Copy chmod command")),
                fixLabel: String(localized: "Copy fix command")
            )
        }
        if hasQuarantineAttribute(at: url) {
            let cmd = "xattr -dr com.apple.quarantine \"\(Bundle.main.bundleURL.path)\""
            return SystemCheckItem(
                id: "tool.\(spec.name)",
                title: spec.title,
                detail: String(localized: "Gatekeeper quarantine attribute present. Move the app to /Applications and re-launch, or run the command on the right."),
                status: .warning(String(localized: "Quarantined")),
                fixAction: .copyShellCommand(cmd, label: String(localized: "Copy xattr fix")),
                fixLabel: String(localized: "Copy fix command")
            )
        }
        return SystemCheckItem(
            id: "tool.\(spec.name)",
            title: spec.title,
            detail: url.path,
            status: .ok,
            fixAction: nil,
            fixLabel: nil
        )
    }

    private func checkConvertScript() -> SystemCheckItem {
        let url = Bundle.main.url(forResource: "convert", withExtension: "sh", subdirectory: "ThirdParty/UUPConverter")
            ?? Bundle.main.url(forResource: "convert", withExtension: "sh")
        guard let url, FileManager.default.isReadableFile(atPath: url.path) else {
            return SystemCheckItem(
                id: "tool.convert.sh",
                title: String(localized: "convert.sh (UUP → ISO)"),
                detail: String(localized: "Not found in app bundle."),
                status: .failed(String(localized: "Missing")),
                fixAction: .revealAppBundle,
                fixLabel: String(localized: "Reveal app bundle")
            )
        }
        return SystemCheckItem(
            id: "tool.convert.sh",
            title: String(localized: "convert.sh (UUP → ISO)"),
            detail: url.path,
            status: .ok,
            fixAction: nil,
            fixLabel: nil
        )
    }

    private func checkBundledLibDirectory() -> SystemCheckItem {
        guard let lib = BundledToolLocator.bundledToolsLibDirectory() else {
            return SystemCheckItem(
                id: "tool.lib",
                title: String(localized: "Embedded dylibs"),
                detail: String(localized: "lib directory missing — bundled tools may fail to launch."),
                status: .warning(String(localized: "Missing")),
                fixAction: .revealAppBundle,
                fixLabel: String(localized: "Reveal app bundle")
            )
        }
        let count = (try? FileManager.default.contentsOfDirectory(atPath: lib.path).count) ?? 0
        return SystemCheckItem(
            id: "tool.lib",
            title: String(localized: "Embedded dylibs"),
            detail: String(format: String(localized: "%lld file(s) at %@"), Int64(count), lib.path),
            status: .ok,
            fixAction: nil,
            fixLabel: nil
        )
    }

    private func hasQuarantineAttribute(at url: URL) -> Bool {
        let path = url.path
        let attrName = "com.apple.quarantine"
        // Allocate small buffer; quarantine xattr is typically <128B.
        let length = getxattr(path, attrName, nil, 0, 0, XATTR_NOFOLLOW)
        return length > 0
    }

    private func collectPermissionsSection() -> SystemStatusSection {
        var items: [SystemCheckItem] = []
        for permission in PermissionItem.allCases {
            let st = permissions.statuses[permission] ?? .unknown
            let mapped: SystemCheckStatus
            switch st {
            case .granted:
                mapped = .ok
            case .outdated:
                mapped = .warning(String(localized: "Outdated"))
            case .denied:
                mapped = .failed(String(localized: "Not granted"))
            case .notDetermined:
                mapped = .warning(String(localized: "Not yet decided"))
            case .unknown:
                mapped = .info(String(localized: "Unknown"))
            }
            items.append(
                SystemCheckItem(
                    id: "perm.\(permission.rawValue)",
                    title: permission.title,
                    detail: permission.detail,
                    status: mapped,
                    fixAction: .grantPermission(permission),
                    fixLabel: permission == .privilegedHelper
                        ? String(localized: st == .outdated ? "Update helper…" : "Install helper…")
                        : String(localized: "Open")
                )
            )
        }
        if let helperErr = permissions.lastPrivilegedHelperInstallError, !helperErr.isEmpty {
            items.append(
                SystemCheckItem(
                    id: "perm.helperLastError",
                    title: String(localized: "Last helper install error"),
                    detail: helperErr,
                    status: .warning(String(localized: "See details")),
                    fixAction: nil,
                    fixLabel: nil
                )
            )
        }
        return SystemStatusSection(
            id: "permissions",
            title: String(localized: "Permissions"),
            symbol: "hand.raised.fill",
            items: items
        )
    }

    private func collectEnvironmentSection() -> SystemStatusSection {
        var items: [SystemCheckItem] = []

        let osv = ProcessInfo.processInfo.operatingSystemVersion
        let macVersion = "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
        let macStatus: SystemCheckStatus = osv.majorVersion >= 13 ? .ok : .warning(String(localized: "Older than tested baseline (macOS 13)"))
        items.append(
            SystemCheckItem(
                id: "env.macOS",
                title: String(localized: "macOS version"),
                detail: macVersion,
                status: macStatus,
                fixAction: nil,
                fixLabel: nil
            )
        )

        #if arch(arm64)
        let archDescription = "arm64"
        #elseif arch(x86_64)
        let archDescription = "x86_64"
        #else
        let archDescription = "unknown"
        #endif
        items.append(
            SystemCheckItem(
                id: "env.arch",
                title: String(localized: "Process architecture"),
                detail: archDescription,
                status: .info(archDescription),
                fixAction: nil,
                fixLabel: nil
            )
        )

        items.append(
            SystemCheckItem(
                id: "env.bundle",
                title: String(localized: "App bundle"),
                detail: Bundle.main.bundleURL.path,
                status: .info(Bundle.main.bundleURL.path),
                fixAction: .revealAppBundle,
                fixLabel: String(localized: "Reveal in Finder")
            )
        )

        let bundledBin = BundledToolLocator.bundledToolsBinDirectory()?.path
        let bundledStatus: SystemCheckStatus = bundledBin == nil
            ? .failed(String(localized: "Bundled Tools/bin directory not found"))
            : .ok
        items.append(
            SystemCheckItem(
                id: "env.bundledBin",
                title: String(localized: "Bundled Tools/bin directory"),
                detail: bundledBin ?? String(localized: "Missing"),
                status: bundledStatus,
                fixAction: bundledBin == nil ? .revealAppBundle : nil,
                fixLabel: bundledBin == nil ? String(localized: "Reveal app bundle") : nil
            )
        )

        let toolchainOK = BundledToolLocator.hasEmbeddedUUPToolchain
        items.append(
            SystemCheckItem(
                id: "env.uupToolchain",
                title: String(localized: "Embedded UUP toolchain"),
                detail: toolchainOK
                    ? String(localized: "All converters (aria2c, cabextract, wimlib-imagex, chntpw, xorriso) located.")
                    : String(localized: "One or more converters are missing — ISO build will fail."),
                status: toolchainOK ? .ok : .failed(String(localized: "Missing tools")),
                fixAction: toolchainOK ? nil : .revealAppBundle,
                fixLabel: toolchainOK ? nil : String(localized: "Reveal app bundle")
            )
        )

        items.append(
            SystemCheckItem(
                id: "env.subprocessPATH",
                title: String(localized: "Subprocess PATH"),
                detail: HostToolPaths.subprocessPATHForDiagnostics(),
                status: .info(String(localized: "Used by convert.sh and other CLI helpers")),
                fixAction: nil,
                fixLabel: nil
            )
        )

        if hasQuarantineAttribute(at: Bundle.main.bundleURL) {
            let cmd = "xattr -dr com.apple.quarantine \"\(Bundle.main.bundleURL.path)\""
            items.append(
                SystemCheckItem(
                    id: "env.quarantine",
                    title: String(localized: "App quarantine"),
                    detail: String(localized: "Gatekeeper marked the app as quarantined. Move it to /Applications and re-launch, or run the command on the right."),
                    status: .warning(String(localized: "Quarantined")),
                    fixAction: .copyShellCommand(cmd, label: String(localized: "Copy xattr fix")),
                    fixLabel: String(localized: "Copy fix command")
                )
            )
        }

        return SystemStatusSection(
            id: "environment",
            title: String(localized: "Environment"),
            symbol: "gearshape.2.fill",
            items: items
        )
    }

    private func collectStorageSection() -> SystemStatusSection {
        let cacheURL = WistCache.cachesRootDirectory
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        var items: [SystemCheckItem] = []
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file

        var freeBytes: Int64 = -1
        if let values = try? cacheURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            freeBytes = bytes
        } else if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: cacheURL.path),
                  let n = attrs[.systemFreeSize] as? NSNumber {
            freeBytes = n.int64Value
        }

        let freeText = freeBytes >= 0 ? formatter.string(fromByteCount: freeBytes) : String(localized: "unknown")
        // 8 GB is roughly the ISO + UUP staging footprint for a single Windows build.
        let freeStatus: SystemCheckStatus
        if freeBytes < 0 {
            freeStatus = .info(String(localized: "Could not query free space."))
        } else if freeBytes < 8_000_000_000 {
            freeStatus = .warning(String(localized: "Less than 8 GB free — ISO build may fail."))
        } else {
            freeStatus = .ok
        }
        items.append(
            SystemCheckItem(
                id: "storage.free",
                title: String(localized: "Cache volume free space"),
                detail: String(format: String(localized: "%@ available at %@"), freeText, cacheURL.path),
                status: freeStatus,
                fixAction: .revealURL(cacheURL),
                fixLabel: String(localized: "Reveal cache")
            )
        )

        return SystemStatusSection(
            id: "storage",
            title: String(localized: "Storage"),
            symbol: "internaldrive",
            items: items
        )
    }
}
