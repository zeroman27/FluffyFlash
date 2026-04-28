import Foundation

private let machServiceName = "com.wist.Wist.PrivilegedHelper"

final class PrivilegedHelper: NSObject, PrivilegedHelperProtocol {
    func runCreateInstallMedia(installerAppPath: String, volumeMountPath: String, reply: @escaping (Int32, String) -> Void) {
        let cim = URL(fileURLWithPath: installerAppPath)
            .appendingPathComponent("Contents/Resources/createinstallmedia")
        let process = Process()
        process.executableURL = cim
        process.arguments = ["--volume", volumeMountPath, "--nointeraction"]

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            reply(127, "Could not launch createinstallmedia: \(error.localizedDescription)")
            return
        }

        process.waitUntilExit()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""
        let combined = ([outText, errText].filter { !$0.isEmpty }).joined(separator: "\n")
        reply(process.terminationStatus, combined)
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        newConnection.exportedObject = PrivilegedHelper()
        newConnection.resume()
        return true
    }
}

@main
struct PrivilegedHelperMain {
    static func main() {
        let listener = NSXPCListener(machServiceName: machServiceName)
        let delegate = HelperDelegate()
        listener.delegate = delegate
        listener.resume()
        RunLoop.main.run()
    }
}

