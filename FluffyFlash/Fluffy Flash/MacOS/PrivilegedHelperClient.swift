import Foundation
import ServiceManagement
import Security

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

enum PrivilegedHelperClient {
    static let machServiceName = "com.wist.Wist.PrivilegedHelper"
    private static let installedHelperPath = "/Library/PrivilegedHelperTools/\(machServiceName)"

    static func isInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: installedHelperPath)
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
                // Do not attempt CFError casting here; just print values to avoid compiler CF bridging pitfalls.
                lines.append("  \(k): \(v)")
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("Underlying NSError:")
            lines.append(describeNSError(underlying).split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    private static func describeNSError(_ error: NSError) -> String {
        var lines: [String] = []
        lines.append("NSError domain: \(error.domain)")
        lines.append("NSError code: \(error.code)")
        lines.append("NSError description: \(error.localizedDescription)")
        if let reason = error.localizedFailureReason, !reason.isEmpty {
            lines.append("Failure reason: \(reason)")
        }
        if let suggestion = error.localizedRecoverySuggestion, !suggestion.isEmpty {
            lines.append("Recovery suggestion: \(suggestion)")
        }
        if !error.userInfo.isEmpty {
            lines.append("userInfo:")
            for (k, v) in error.userInfo.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
                lines.append("  \(k): \(v)")
            }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("Underlying NSError:")
            lines.append(describeNSError(underlying).split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    private static func installContextDebug() -> String {
        var lines: [String] = []
        lines.append("machServiceName: \(machServiceName)")
        lines.append("main bundle id: \(Bundle.main.bundleIdentifier ?? "nil")")

        if let dict = Bundle.main.object(forInfoDictionaryKey: "SMPrivilegedExecutables") as? [String: Any] {
            lines.append("SMPrivilegedExecutables:")
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(k): \(v)")
            }
        } else {
            lines.append("SMPrivilegedExecutables: <missing>")
        }

        // What we embedded into the app bundle (useful when debugging dev builds).
        let embeddedHelper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/\(machServiceName)")
        let embeddedPlist = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(machServiceName).plist")

        func describeFile(_ url: URL) -> String {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let size = (attrs[.size] as? NSNumber)?.intValue ?? -1
                return "exists (size=\(size))"
            }
            return "missing"
        }

        lines.append("embedded helper: \(embeddedHelper.path) — \(describeFile(embeddedHelper))")
        lines.append("embedded plist: \(embeddedPlist.path) — \(describeFile(embeddedPlist))")
        lines.append("expected install path: /Library/PrivilegedHelperTools/\(machServiceName)")
        return lines.joined(separator: "\n")
    }

    static func installIfNeeded() throws {
        // Fast path: if helper is already installed, don't prompt again.
        if isInstalled() {
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
        if !ok {
            var parts: [String] = []
            parts.append("SMJobBless returned false.")
            parts.append("")
            parts.append(installContextDebug())
            if let cfErr = error?.takeRetainedValue() {
                parts.append("")
                parts.append(describeCFError(cfErr))
            } else {
                parts.append("")
                parts.append("CFError: <nil>")
            }
            throw PrivilegedHelperClientError.blessFailed(parts.joined(separator: "\n"))
        }
    }

    static func connection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        c.resume()
        return c
    }

    static func runCreateInstallMedia(installerAppPath: String, volumeMountPath: String) async throws -> (Int32, String) {
        try installIfNeeded()
        let c = connection()
        defer { c.invalidate() }

        return try await withCheckedThrowingContinuation { cont in
            guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(throwing: PrivilegedHelperClientError.connectionFailed)
            }) as? PrivilegedHelperProtocol else {
                cont.resume(throwing: PrivilegedHelperClientError.connectionFailed)
                return
            }
            proxy.runCreateInstallMedia(installerAppPath: installerAppPath, volumeMountPath: volumeMountPath) { code, output in
                cont.resume(returning: (code, output))
            }
        }
    }
}

