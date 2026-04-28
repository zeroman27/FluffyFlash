//
//  MistPrivilegedShellRunner.swift
//  Fluffy Flash
//
//  mist-cli requires **root** for `mist download` (installer / firmware). GUI apps run as the user,
//  so we run the download via a short shell script executed with AppleScript `with administrator privileges`.
//

import Darwin
import Foundation

enum MistPrivilegedShellRunnerError: LocalizedError {
    case couldNotWriteScript(underlying: Error)
    case userCanceledAdministratorPrompt
    case privilegedCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .couldNotWriteScript(let err):
            return String(format: String(localized: "Could not write temporary script: %@"), err.localizedDescription)
        case .userCanceledAdministratorPrompt:
            return String(localized: "Administrator approval was canceled.")
        case .privilegedCommandFailed(let detail):
            return detail
        }
    }
}

/// Runs a subprocess **as root** (admin password prompt).
enum MistPrivilegedShellRunner: Sendable {
    /// Single-quote for POSIX `sh` / `bash` `export KEY='…'`.
    private static func shellSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Runs `executable` with `arguments` and `environment` under an admin shell (`osascript`).
    /// When `recursiveChownAfterSuccess` is set, after a **successful** command the tree is `chown`’d back to the invoking user (root-created files are otherwise unreadable to the GUI app).
    nonisolated static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        recursiveChownAfterSuccess: URL? = nil,
        pidFileURL: URL? = nil
    ) async throws {
        let fm = FileManager.default
        let scriptURL = fm.temporaryDirectory
            .appendingPathComponent("wist-mist-priv-\(UUID().uuidString).sh", isDirectory: false)

        let runUID = getuid()
        let runGID = getgid()

        var scriptLines: [String] = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export WIST_RUN_UID=\(runUID)",
            "export WIST_RUN_GID=\(runGID)",
        ]

        let exportKeys = environment.keys.sorted()
        for key in exportKeys {
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            guard let value = environment[key] else { continue }
            scriptLines.append("export \(key)=\(shellSingleQuote(value))")
        }

        // Run the command as a child so cancellation can terminate it.
        let argvLiteral = ([executable.path] + arguments).map { shellSingleQuote($0) }.joined(separator: " ")
        scriptLines.append("child_pid=\"\"")
        if let pidFileURL {
            scriptLines.append("pid_file=\(shellSingleQuote(pidFileURL.path))")
            scriptLines.append("/bin/rm -f \"${pid_file}\" 2>/dev/null || true")
        }
        scriptLines.append("cleanup() { if [[ -n \"${child_pid}\" ]]; then kill -TERM \"${child_pid}\" 2>/dev/null || true; fi }")
        scriptLines.append("trap cleanup TERM INT")
        scriptLines.append("\(argvLiteral) &")
        scriptLines.append("child_pid=$!")
        if pidFileURL != nil {
            scriptLines.append("echo \"${child_pid}\" > \"${pid_file}\" || true")
        }
        scriptLines.append("wait \"${child_pid}\"")
        if pidFileURL != nil {
            scriptLines.append("/bin/rm -f \"${pid_file}\" 2>/dev/null || true")
        }
        if let chownRoot = recursiveChownAfterSuccess {
            scriptLines.append("/usr/sbin/chown -R \"${WIST_RUN_UID}:${WIST_RUN_GID}\" \(shellSingleQuote(chownRoot.path))")
        }

        let scriptBody = scriptLines.joined(separator: "\n") + "\n"
        do {
            try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: scriptURL.path)
        } catch {
            throw MistPrivilegedShellRunnerError.couldNotWriteScript(underlying: error)
        }
        defer {
            try? fm.removeItem(at: scriptURL)
        }

        let pathForAppleScript = scriptURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"/bin/bash \" & quoted form of \"\(pathForAppleScript)\" with administrator privileges"

        do {
            try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", appleScript],
                currentDirectoryURL: nil,
                environment: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let err as ProcessRunnerError {
            let detail = err.localizedDescription
            let lower = detail.lowercased()
            if lower.contains("user canceled") || lower.contains("canceled") || detail.contains("-128") {
                throw MistPrivilegedShellRunnerError.userCanceledAdministratorPrompt
            }
            throw MistPrivilegedShellRunnerError.privilegedCommandFailed(detail)
        } catch {
            throw MistPrivilegedShellRunnerError.privilegedCommandFailed(error.localizedDescription)
        }
    }
}
