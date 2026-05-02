import Foundation

@objc(PrivilegedHelperStreamProtocol)
public protocol PrivilegedHelperStreamProtocol {
    func onLine(_ line: String)
}

@objc(PrivilegedHelperProtocol)
public protocol PrivilegedHelperProtocol {
    /// Runs `createinstallmedia` for the given installer app and target volume.
    /// - Parameters:
    ///   - installerAppPath: path to `Install macOS … .app`
    ///   - volumeMountPath: path to mounted target volume, e.g. `/Volumes/Untitled`
    ///   - reply: completion with exit code and combined output.
    func runCreateInstallMedia(installerAppPath: String, volumeMountPath: String, reply: @escaping (Int32, String) -> Void)

    /// Runs `createinstallmedia` and streams output lines as they arrive.
    /// - Parameters:
    ///   - onLine: receives stdout/stderr lines (best-effort, newline-delimited).
    ///   - reply: completion with exit code.
    func runCreateInstallMediaStreaming(
        installerAppPath: String,
        volumeMountPath: String,
        stream: PrivilegedHelperStreamProtocol,
        reply: @escaping (Int32) -> Void
    )

    /// Runs an arbitrary executable with arguments as root.
    ///
    /// - Parameters:
    ///   - executablePath: absolute path to executable, e.g. `/usr/sbin/diskutil`
    ///   - arguments: command-line arguments (excluding argv[0])
    ///   - environment: environment variables to pass (best-effort)
    ///   - reply: completion with exit code + captured stdout/stderr
    func runCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        reply: @escaping (Int32, String, String) -> Void
    )

    /// Runs an arbitrary executable and streams output lines as they arrive.
    func runCommandStreaming(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        stream: PrivilegedHelperStreamProtocol,
        reply: @escaping (Int32) -> Void
    )

    /// Removes a file or directory at path (best-effort).
    func removeItem(atPath path: String, reply: @escaping (Int32, String) -> Void)

    /// Sets basic file attributes (permissions + owner) similar to Mist helper.
    func setFileAttributes(
        atPath path: String,
        ownerAccountName: String,
        groupAccountName: String,
        posixPermissions: Int,
        reply: @escaping (Int32, String) -> Void
    )

    /// Best-effort termination of the current long-running task (createinstallmedia).
    func killCurrentTask(reply: @escaping (Bool) -> Void)
}

