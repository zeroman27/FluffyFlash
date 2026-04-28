import Foundation

@objc(PrivilegedHelperProtocol)
public protocol PrivilegedHelperProtocol {
    func runCreateInstallMedia(installerAppPath: String, volumeMountPath: String, reply: @escaping (Int32, String) -> Void)
}

