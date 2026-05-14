import Foundation
import ServiceManagement
import AppKit
import Security

private func makePrivilegedHelperRemoteInterface() -> NSXPCInterface {
    let iface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
    let streamIface = NSXPCInterface(with: PrivilegedHelperStreamProtocol.self)

    iface.setInterface(
        streamIface,
        for: #selector(PrivilegedHelperProtocol.runCommandStreaming(executablePath:arguments:environment:stream:reply:)),
        argumentIndex: 3,
        ofReply: false
    )
    iface.setInterface(
        streamIface,
        for: #selector(PrivilegedHelperProtocol.runCreateInstallMediaStreaming(installerAppPath:volumeMountPath:stream:reply:)),
        argumentIndex: 2,
        ofReply: false
    )
    return iface
}

enum PrivilegedHelperClientError: LocalizedError {
    case authorizationFailed(OSStatus)
    case blessFailed(String)
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let status):
            return "Authorization failed: \(status)"
        case .blessFailed(let msg):
            return "SMJobBless failed: \(msg)"
        case .connectionFailed:
            return "Could not connect to privileged helper."
        }
    }
}

/// Mist-style privileged helper installation via `SMJobBless`.
///
/// Embedded in the app bundle:
/// - helper: `Contents/Library/LaunchServices/<label>`
/// - launchd plist: `Contents/Library/LaunchDaemons/<label>.plist`
///
/// Installed by the system (after bless):
/// - helper: `/Library/PrivilegedHelperTools/<label>`
/// - launchd plist: `/Library/LaunchDaemons/<label>.plist`
///
/// This style is more stable for USB writing workflows on recent macOS versions.
enum PrivilegedHelperClient {
    static let machServiceName = "com.fluffyflash.FluffyFlash.PrivilegedHelper"
    static let daemonPlistName = "com.fluffyflash.FluffyFlash.PrivilegedHelper.plist"

    static var embeddedHelperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(machServiceName)")
    }

    static var embeddedDaemonPlistURL: URL {
        // With SMJobBless, the launchd plist is embedded in the helper tool (LAUNCHDPLIST_FILE),
        // and the installed copy lands in /Library/LaunchDaemons/.
        // The app bundle itself should not ship Contents/Library/LaunchDaemons/.
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/\(daemonPlistName)")
    }

    static var installedHelperURL: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(machServiceName)")
    }

    static var installedLaunchdPlistURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(daemonPlistName)")
    }

    static func isInstalled() -> Bool {
        let helperPath = installedHelperURL.path
        let plistPath = installedLaunchdPlistURL.path
        guard FileManager.default.fileExists(atPath: plistPath) else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: helperPath, isDirectory: &isDir),
              !isDir.boolValue else {
            return false
        }
        // Do not use `isExecutableFile`: launchd-installed helpers are often mode 0544 (root-only +x),
        // so the GUI user gets `false` even when SMJobBless succeeded.
        return true
    }

    static func openFullDiskAccessPrivacySettings() {
        // Apple does not guarantee these deep-links, but this works on many macOS versions.
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess",
        ]
        for s in candidates {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                break
            }
        }
    }

    static func revealEmbeddedHelperInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([embeddedHelperURL])
    }

    static func revealInstalledHelperInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([installedHelperURL])
    }

    private static func describeFile(_ url: URL) -> String {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let size = (attrs[.size] as? NSNumber)?.intValue ?? -1
            return "exists (size=\(size))"
        }
        return "missing"
    }

    private static func designatedRequirementString(forBinaryAt url: URL) -> String? {
        var staticCode: SecStaticCode?
        let codeStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard codeStatus == errSecSuccess, let staticCode else {
            return "SecStaticCodeCreateWithPath failed: \(codeStatus)"
        }

        var req: SecRequirement?
        let reqStatus = SecCodeCopyDesignatedRequirement(staticCode, [], &req)
        guard reqStatus == errSecSuccess, let req else {
            return "SecCodeCopyDesignatedRequirement failed: \(reqStatus)"
        }

        var reqString: CFString?
        let strStatus = SecRequirementCopyString(req, [], &reqString)
        guard strStatus == errSecSuccess, let reqString else {
            return "SecRequirementCopyString failed: \(strStatus)"
        }
        return reqString as String
    }

    private static func smPrivilegedExecutablesRequirementString() -> String? {
        guard let dict = Bundle.main.object(forInfoDictionaryKey: "SMPrivilegedExecutables") as? [String: Any] else {
            return nil
        }
        return dict[machServiceName] as? String
    }

    private static func installContextDebug() -> String {
        var lines: [String] = []
        lines.append("machServiceName: \(machServiceName)")
        lines.append("main bundle id: \(Bundle.main.bundleIdentifier ?? "nil")")
        lines.append("embedded helper: \(embeddedHelperURL.path) — \(describeFile(embeddedHelperURL))")
        lines.append("embedded plist: \(embeddedDaemonPlistURL.path) — \(describeFile(embeddedDaemonPlistURL))")
        lines.append("installed helper: \(installedHelperURL.path) — \(describeFile(installedHelperURL))")
        lines.append("installed plist: \(installedLaunchdPlistURL.path) — \(describeFile(installedLaunchdPlistURL))")

        if let smReq = smPrivilegedExecutablesRequirementString() {
            lines.append("")
            lines.append("SMPrivilegedExecutables[\(machServiceName)]:")
            lines.append("  \(smReq)")
        } else {
            lines.append("")
            lines.append("SMPrivilegedExecutables[\(machServiceName)]: <missing>")
        }

        lines.append("")
        lines.append("Host designated requirement:")
        lines.append("  \(designatedRequirementString(forBinaryAt: Bundle.main.bundleURL) ?? "<nil>")")

        lines.append("")
        lines.append("Helper designated requirement:")
        lines.append("  \(designatedRequirementString(forBinaryAt: embeddedHelperURL) ?? "<nil>")")

        return lines.joined(separator: "\n")
    }

    private static func describeCFError(_ error: CFError) -> String {
        var lines: [String] = []
        lines.append("CFError domain: \(CFErrorGetDomain(error) as String)")
        lines.append("CFError code: \(CFErrorGetCode(error))")
        lines.append("CFError description: \(error.localizedDescription)")

        let ns = error as Error as NSError
        if let reason = ns.localizedFailureReason, !reason.isEmpty {
            lines.append("Failure reason: \(reason)")
        }
        if let suggestion = ns.localizedRecoverySuggestion, !suggestion.isEmpty {
            lines.append("Recovery suggestion: \(suggestion)")
        }
        if !ns.userInfo.isEmpty {
            lines.append("userInfo:")
            for (k, v) in ns.userInfo.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
                lines.append("  \(k): \(v)")
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("Underlying NSError:")
            lines.append("  domain=\(underlying.domain) code=\(underlying.code) desc=\(underlying.localizedDescription)")
            if !underlying.userInfo.isEmpty {
                lines.append("  userInfo=\(underlying.userInfo)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func isLaunchdConflictError(_ error: CFError) -> Bool {
        (CFErrorGetDomain(error) as String) == "CFErrorDomainLaunchd" && CFErrorGetCode(error) == 8
    }

    private static func smJobRemove(authRef: AuthorizationRef) -> String? {
        var err: Unmanaged<CFError>?
        let ok = SMJobRemove(kSMDomainSystemLaunchd, machServiceName as CFString, authRef, true, &err)
        if ok { return nil }
        if let cfErr = err?.takeRetainedValue() {
            return describeCFError(cfErr)
        }
        return "CFError: <nil>"
    }

    /// Process-wide latch that remembers we already saw a successful `SMJobBless` (or that
    /// `isInstalled()` is reliably true). Subsequent operations within the same launch reuse the
    /// installed helper and skip `installIfNeeded()` entirely, so the user is not prompted again.
    private static let installLatch = InstallLatch()

    private final class InstallLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var blessedThisSession = false

        func markBlessed() {
            lock.lock()
            defer { lock.unlock() }
            blessedThisSession = true
        }

        func wasBlessedThisSession() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return blessedThisSession
        }
    }

    /// Ensures the privileged helper is installed and connectable for the current app session.
    ///
    /// Designed to be called once per user-initiated workflow before any helper-backed work
    /// kicks off. Internally collapses to a no-op when the helper is already installed or
    /// when a previous successful bless happened during this app launch, so the user sees at
    /// most a single "install helper" prompt per session.
    static func prepareSession() async throws {
        if installLatch.wasBlessedThisSession() { return }
        if isInstalled() {
            // If the helper is installed but does not match the embedded helper shipped with
            // this app build, proactively reinstall so users never have to manually delete it.
            // This avoids confusing cases where a new app version keeps using an older helper
            // until the user performs an explicit reinstall.
            if await embeddedHelperMatchesInstalled() {
                installLatch.markBlessed()
                return
            }
            try await MainActor.run {
                try install(forceReinstall: true)
            }
            return
        }
        try await MainActor.run {
            try install(forceReinstall: false)
        }
    }

    /// Installs (or reinstalls) the privileged helper via SMJobBless.
    /// - Parameter forceReinstall: when true, performs SMJobBless even if `isInstalled()` is true.
    static func install(forceReinstall: Bool) throws {
        if !forceReinstall, isInstalled() {
            installLatch.markBlessed()
            return
        }

        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [.interactionAllowed, .extendRights, .preAuthorize], &authRef)
        guard status == errAuthorizationSuccess, let authRef else {
            throw PrivilegedHelperClientError.authorizationFailed(status)
        }
        defer { AuthorizationFree(authRef, []) }

        var error: Unmanaged<CFError>?
        let ok = SMJobBless(kSMDomainSystemLaunchd, machServiceName as CFString, authRef, &error)
        if ok {
            installLatch.markBlessed()
            return
        }

        let cfErr = error?.takeRetainedValue()
        if let cfErr, isLaunchdConflictError(cfErr) {
            var retryParts: [String] = []
            retryParts.append("SMJobBless returned false (launchd conflict). Attempting SMJobRemove + retry…")
            if let removeErr = smJobRemove(authRef: authRef) {
                retryParts.append("SMJobRemove failed:")
                retryParts.append(removeErr)
            } else {
                retryParts.append("SMJobRemove ok.")
            }

            var retryErr: Unmanaged<CFError>?
            let retryOk = SMJobBless(kSMDomainSystemLaunchd, machServiceName as CFString, authRef, &retryErr)
            if retryOk {
                installLatch.markBlessed()
                return
            }

            var parts: [String] = []
            parts.append("SMJobBless returned false (after SMJobRemove retry).")
            parts.append("")
            parts.append(installContextDebug())
            parts.append("")
            parts.append("Original CFError:")
            parts.append(describeCFError(cfErr))
            if let retryCf = retryErr?.takeRetainedValue() {
                parts.append("")
                parts.append("Retry CFError:")
                parts.append(describeCFError(retryCf))
            } else {
                parts.append("")
                parts.append("Retry CFError: <nil>")
            }
            throw PrivilegedHelperClientError.blessFailed((retryParts + [""] + parts).joined(separator: "\n"))
        }

        var parts: [String] = []
        parts.append("SMJobBless returned false.")
        parts.append("")
        parts.append(installContextDebug())
        if let cfErr {
            parts.append("")
            parts.append(describeCFError(cfErr))
        } else {
            parts.append("")
            parts.append("CFError: <nil>")
        }
        throw PrivilegedHelperClientError.blessFailed(parts.joined(separator: "\n"))
    }

    /// Compares the embedded helper tool shipped inside the app bundle against the
    /// installed helper in `/Library/PrivilegedHelperTools/` by SHA-256.
    /// Returns `true` on match or when hashing is unavailable (best-effort).
    private static func embeddedHelperMatchesInstalled() async -> Bool {
        let embedded = embeddedHelperURL
        let installed = installedHelperURL
        guard FileManager.default.fileExists(atPath: embedded.path),
              FileManager.default.fileExists(atPath: installed.path) else {
            return false
        }
        async let embeddedHash = SHA256Hasher.hashFileBestEffort(at: embedded)
        async let installedHash = SHA256Hasher.hashFileBestEffort(at: installed)
        let (e, i) = await (embeddedHash, installedHash)
        guard let e, let i else {
            // Hashing failed (e.g. permissions) — do not prompt the user unnecessarily.
            return true
        }
        return e == i
    }

    static func connection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        c.remoteObjectInterface = makePrivilegedHelperRemoteInterface()
        c.resume()
        return c
    }

    private final class StreamSink: NSObject, PrivilegedHelperStreamProtocol {
        private let onLine: (String) -> Void
        init(onLine: @escaping (String) -> Void) { self.onLine = onLine }
        func onLine(_ line: String) { onLine(line) }
    }

    private final class Once {
        private let lock = NSLock()
        private var done = false

        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }

    static func killCurrentTask() async -> Bool {
        let c = connection()
        defer { c.invalidate() }

        return await withCheckedContinuation { cont in
            let once = Once()
            guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in
                once.run { cont.resume(returning: false) }
            }) as? PrivilegedHelperProtocol else {
                once.run { cont.resume(returning: false) }
                return
            }
            proxy.killCurrentTask { ok in
                once.run { cont.resume(returning: ok) }
            }
        }
    }

    static func removeItem(atPath path: String) async -> (Int32, String) {
        let c = connection()
        defer { c.invalidate() }

        return await withCheckedContinuation { cont in
            let once = Once()
            guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in
                once.run { cont.resume(returning: (1, "XPC error")) }
            }) as? PrivilegedHelperProtocol else {
                once.run { cont.resume(returning: (1, "XPC error")) }
                return
            }
            proxy.removeItem(atPath: path) { code, msg in
                once.run { cont.resume(returning: (code, msg)) }
            }
        }
    }

    static func setFileAttributes(
        atPath path: String,
        ownerAccountName: String,
        groupAccountName: String = "wheel",
        posixPermissions: Int = 0o755
    ) async -> (Int32, String) {
        let c = connection()
        defer { c.invalidate() }

        return await withCheckedContinuation { cont in
            let once = Once()
            guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in
                once.run { cont.resume(returning: (1, "XPC error")) }
            }) as? PrivilegedHelperProtocol else {
                once.run { cont.resume(returning: (1, "XPC error")) }
                return
            }
            proxy.setFileAttributes(
                atPath: path,
                ownerAccountName: ownerAccountName,
                groupAccountName: groupAccountName,
                posixPermissions: posixPermissions
            ) { code, msg in
                once.run { cont.resume(returning: (code, msg)) }
            }
        }
    }

    static func runCommandStreaming(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        onLine: @escaping (String) -> Void
    ) async throws -> Int32 {
        // Caller must have invoked `prepareSession()` once per workflow. We deliberately do not
        // call `installIfNeeded()` here, otherwise every helper-backed command would risk
        // triggering a fresh "install helper" prompt when launchd is briefly out of sync.
        let c = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        let sink = StreamSink(onLine: onLine)
        c.exportedInterface = NSXPCInterface(with: PrivilegedHelperStreamProtocol.self)
        c.exportedObject = sink
        c.remoteObjectInterface = makePrivilegedHelperRemoteInterface()
        c.resume()
        defer { c.invalidate() }

        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in
                once.run { cont.resume(throwing: PrivilegedHelperClientError.connectionFailed) }
            }) as? PrivilegedHelperProtocol else {
                once.run { cont.resume(throwing: PrivilegedHelperClientError.connectionFailed) }
                return
            }

            proxy.runCommandStreaming(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                stream: sink,
                reply: { code in once.run { cont.resume(returning: code) } }
            )
        }
    }

    static func runCreateInstallMediaStreaming(
        installerAppPath: String,
        volumeMountPath: String,
        onLine: @escaping (String) -> Void
    ) async throws -> Int32 {
        // See `runCommandStreaming` above: install is owned by `prepareSession()`.
        let c = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        let sink = StreamSink(onLine: onLine)
        c.exportedInterface = NSXPCInterface(with: PrivilegedHelperStreamProtocol.self)
        c.exportedObject = sink
        c.remoteObjectInterface = makePrivilegedHelperRemoteInterface()
        c.resume()
        defer { c.invalidate() }

        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in
                once.run { cont.resume(throwing: PrivilegedHelperClientError.connectionFailed) }
            }) as? PrivilegedHelperProtocol else {
                once.run { cont.resume(throwing: PrivilegedHelperClientError.connectionFailed) }
                return
            }

            proxy.runCreateInstallMediaStreaming(
                installerAppPath: installerAppPath,
                volumeMountPath: volumeMountPath,
                stream: sink,
                reply: { code in once.run { cont.resume(returning: code) } }
            )
        }
    }
}
