import Foundation

@objc(PrivilegedHelperProtocol)
public protocol PrivilegedHelperProtocol {
    /// Runs `createinstallmedia` for the given installer app and target volume.
    /// - Parameters:
    ///   - installerAppPath: path to `Install macOS … .app`
    ///   - volumeMountPath: path to mounted target volume, e.g. `/Volumes/Untitled`
    ///   - reply: completion with exit code and combined output.
    func runCreateInstallMedia(installerAppPath: String, volumeMountPath: String, reply: @escaping (Int32, String) -> Void)
}

