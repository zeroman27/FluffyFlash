import Foundation

private let machServiceName = "com.fluffyflash.FluffyFlash.PrivilegedHelper"

final class PrivilegedHelper: NSObject, PrivilegedHelperProtocol {
    private let stateLock = NSLock()
    private var currentProcess: Process?

    private func installProcessForKill(_ p: Process?) {
        stateLock.lock()
        currentProcess = p
        stateLock.unlock()
    }

    func killCurrentTask(reply: @escaping (Bool) -> Void) {
        stateLock.lock()
        let p = currentProcess
        stateLock.unlock()

        guard let p else {
            reply(false)
            return
        }

        if p.isRunning {
            p.terminate()
            reply(true)
        } else {
            reply(false)
        }
    }

    func removeItem(atPath path: String, reply: @escaping (Int32, String) -> Void) {
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            reply(0, "")
        } catch {
            reply(1, error.localizedDescription)
        }
    }

    func setFileAttributes(
        atPath path: String,
        ownerAccountName: String,
        groupAccountName: String,
        posixPermissions: Int,
        reply: @escaping (Int32, String) -> Void
    ) {
        let attrs: [FileAttributeKey: Any] = [
            .posixPermissions: posixPermissions,
            .ownerAccountName: ownerAccountName,
            .groupOwnerAccountName: groupAccountName,
        ]
        do {
            try FileManager.default.setAttributes(attrs, ofItemAtPath: path)
            reply(0, "")
        } catch {
            reply(1, error.localizedDescription)
        }
    }

    func runCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        reply: @escaping (Int32, String, String) -> Void
    ) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = arguments
        if !environment.isEmpty {
            p.environment = environment
        }

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        do {
            installProcessForKill(p)
            try p.run()
        } catch {
            installProcessForKill(nil)
            reply(127, "", "Could not launch \(executablePath): \(error.localizedDescription)")
            return
        }

        p.waitUntilExit()
        installProcessForKill(nil)

        let outText = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        reply(p.terminationStatus, outText, errText)
    }

    func runCommandStreaming(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        stream: PrivilegedHelperStreamProtocol,
        reply: @escaping (Int32) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executablePath)
            p.arguments = arguments
            if !environment.isEmpty {
                p.environment = environment
            }

            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err

            let outHandle = out.fileHandleForReading
            let errHandle = err.fileHandleForReading

            var outBuf = Data()
            var errBuf = Data()

            func flushLines(from buffer: inout Data, prefix: String) {
                while true {
                    guard let idx = buffer.firstIndex(of: 0x0A) else { break } // \n
                    let lineData = buffer.prefix(upTo: idx)
                    buffer.removeSubrange(...idx)
                    if let s = String(data: lineData, encoding: .utf8) {
                        let t = s.trimmingCharacters(in: .newlines)
                        if !t.isEmpty { stream.onLine("\(prefix)\(t)") }
                    }
                }
            }

            outHandle.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { return }
                outBuf.append(d)
                flushLines(from: &outBuf, prefix: "stdout: ")
            }
            errHandle.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { return }
                errBuf.append(d)
                flushLines(from: &errBuf, prefix: "stderr: ")
            }

            // Intentionally no synthetic heartbeats: keep output identical to the underlying tools.

            do {
                self.installProcessForKill(p)
                try p.run()
            } catch {
                self.installProcessForKill(nil)
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                stream.onLine("stderr: Could not launch \(executablePath): \(error.localizedDescription)")
                reply(127)
                return
            }

            p.waitUntilExit()
            self.installProcessForKill(nil)

            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil

            if !outBuf.isEmpty, let s = String(data: outBuf, encoding: .utf8) {
                for line in s.split(whereSeparator: \.isNewline) {
                    let t = String(line)
                    if !t.isEmpty { stream.onLine("stdout: \(t)") }
                }
            }
            if !errBuf.isEmpty, let s = String(data: errBuf, encoding: .utf8) {
                for line in s.split(whereSeparator: \.isNewline) {
                    let t = String(line)
                    if !t.isEmpty { stream.onLine("stderr: \(t)") }
                }
            }

            reply(p.terminationStatus)
        }
    }

    func runCreateInstallMedia(installerAppPath: String, volumeMountPath: String, reply: @escaping (Int32, String) -> Void) {
        var debug: [String] = []
        debug.append("— helper preflight —")
        debug.append("uid=\(getuid()) euid=\(geteuid()) gid=\(getgid()) egid=\(getegid())")
        debug.append("volumeMountPath=\(volumeMountPath)")

        func runTool(_ toolPath: String, _ args: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: toolPath)
            p.arguments = args
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do {
                try p.run()
            } catch {
                return (127, "Could not launch \(toolPath): \(error.localizedDescription)")
            }
            p.waitUntilExit()
            let outText = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let combined = ([outText, errText].filter { !$0.isEmpty }).joined(separator: "\n")
            return (p.terminationStatus, combined)
        }

        // On some macOS versions, createinstallmedia/bless fails with EPERM when the
        // target external volume has ownership disabled ("Ignore ownership...").
        // Enable ownership explicitly before running createinstallmedia.
        debug.append("diskutil enableOwnership …")
        let (ownCode, ownOut) = runTool("/usr/sbin/diskutil", ["enableOwnership", volumeMountPath])
        debug.append("diskutil exit=\(ownCode)")
        if !ownOut.isEmpty {
            debug.append(ownOut)
        }

        // Preflight write probe: create a tiny temp file at the volume root.
        // If this fails with EPERM, it's very often a TCC/Removable Volumes policy issue
        // for background daemons (as opposed to a classic POSIX permission problem).
        let probeURL = URL(fileURLWithPath: volumeMountPath).appendingPathComponent(".fluffy_write_probe")
        var writeProbeEPERM = false
        do {
            try "probe".data(using: .utf8)?.write(to: probeURL, options: [.atomic])
            try? FileManager.default.removeItem(at: probeURL)
            debug.append("writeProbe=ok")
        } catch {
            debug.append("writeProbe=failed: \(error.localizedDescription)")
            let ns = error as NSError
            debug.append("writeProbe NSError domain=\(ns.domain) code=\(ns.code)")
            if !ns.userInfo.isEmpty {
                debug.append("writeProbe userInfo=\(ns.userInfo)")
            }
            if ns.domain == NSPOSIXErrorDomain, ns.code == 1 {
                writeProbeEPERM = true
            } else if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
                      underlying.domain == NSPOSIXErrorDomain, underlying.code == 1 {
                writeProbeEPERM = true
            }
        }

        // Capture mount line for the target volume (best-effort).
        do {
            let m = Process()
            m.executableURL = URL(fileURLWithPath: "/sbin/mount")
            let p = Pipe()
            m.standardOutput = p
            m.standardError = Pipe()
            try m.run()
            m.waitUntilExit()
            let data = p.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            if let line = text.split(whereSeparator: \.isNewline).first(where: { $0.contains(volumeMountPath) }) {
                debug.append("mountLine=\(line)")
            } else {
                debug.append("mountLine=<not found>")
            }
        } catch {
            debug.append("mountProbe=failed: \(error.localizedDescription)")
        }

        if writeProbeEPERM {
            debug.append("")
            debug.append("❗️Permission denied writing to the USB volume (EPERM).")
            debug.append("This is typically macOS Privacy (TCC) blocking access to Removable Volumes for background daemons.")
            debug.append("Fix: System Settings → Privacy & Security → Files and Folders → enable “Removable Volumes” for Fluffy Flash.")
            debug.append("Then quit and relaunch the app and retry.")
            reply(1, debug.joined(separator: "\n"))
            return
        }

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
            installProcessForKill(process)
            try process.run()
        } catch {
            reply(127, "Could not launch createinstallmedia: \(error.localizedDescription)")
            return
        }

        process.waitUntilExit()
        installProcessForKill(nil)
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""
        let combined = (debug + [outText, errText].filter { !$0.isEmpty }).joined(separator: "\n")
        reply(process.terminationStatus, combined)
    }

    func runCreateInstallMediaStreaming(
        installerAppPath: String,
        volumeMountPath: String,
        stream: PrivilegedHelperStreamProtocol,
        reply: @escaping (Int32) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var debug: [String] = []
            debug.append("— helper preflight —")
            debug.append("uid=\(getuid()) euid=\(geteuid()) gid=\(getgid()) egid=\(getegid())")
            debug.append("volumeMountPath=\(volumeMountPath)")

            func emit(_ s: String) {
                for line in s.split(whereSeparator: \.isNewline) {
                    let t = String(line)
                    if !t.isEmpty { stream.onLine(t) }
                }
            }

            // Emit preflight immediately (so the UI never looks "stuck at start").
            emit(debug.joined(separator: "\n"))

            func runTool(_ toolPath: String, _ args: [String]) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: toolPath)
                p.arguments = args
                let out = Pipe()
                let err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { emit("Could not launch \(toolPath): \(error.localizedDescription)"); return }
                p.waitUntilExit()
                let outText = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if !outText.isEmpty { emit(outText) }
                if !errText.isEmpty { emit(errText) }
            }

            emit("diskutil enableOwnership …")
            runTool("/usr/sbin/diskutil", ["enableOwnership", volumeMountPath])

            // Write probe.
            let probeURL = URL(fileURLWithPath: volumeMountPath).appendingPathComponent(".fluffy_write_probe")
            do {
                try "probe".data(using: .utf8)?.write(to: probeURL, options: [.atomic])
                try? FileManager.default.removeItem(at: probeURL)
                emit("writeProbe=ok")
            } catch {
                emit("writeProbe=failed: \(error.localizedDescription)")
                let ns = error as NSError
                if ns.domain == NSPOSIXErrorDomain, ns.code == 1 ||
                    (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map({ $0.domain == NSPOSIXErrorDomain && $0.code == 1 }) == true {
                    emit("❗️Permission denied writing to the USB volume (EPERM). Enable Removable Volumes for Fluffy Flash in System Settings → Privacy & Security → Files and Folders.")
                    reply(1)
                    return
                }
            }

            let cim = URL(fileURLWithPath: installerAppPath)
                .appendingPathComponent("Contents/Resources/createinstallmedia")

            let process = Process()
            process.executableURL = cim
            process.arguments = ["--volume", volumeMountPath, "--nointeraction"]

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            let outHandle = out.fileHandleForReading
            let errHandle = err.fileHandleForReading

            var outBuf = Data()
            var errBuf = Data()

            func flushLines(from buffer: inout Data) {
                while true {
                    guard let idx = buffer.firstIndex(of: 0x0A) else { break } // \n
                    let lineData = buffer.prefix(upTo: idx)
                    buffer.removeSubrange(...idx)
                    if let s = String(data: lineData, encoding: .utf8) {
                        let t = s.trimmingCharacters(in: .newlines)
                        if !t.isEmpty { stream.onLine(t) }
                    }
                }
            }

            outHandle.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { return }
                outBuf.append(d)
                flushLines(from: &outBuf)
            }
            errHandle.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { return }
                errBuf.append(d)
                flushLines(from: &errBuf)
            }

            // Intentionally no synthetic heartbeats: keep output identical to createinstallmedia.

            do {
                self.installProcessForKill(process)
                try process.run()
            } catch {
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                self.installProcessForKill(nil)
                stream.onLine("Could not launch createinstallmedia: \(error.localizedDescription)")
                reply(127)
                return
            }

            process.waitUntilExit()
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil

            // Flush remaining partial lines (best-effort).
            if !outBuf.isEmpty, let s = String(data: outBuf, encoding: .utf8) { emit(s) }
            if !errBuf.isEmpty, let s = String(data: errBuf, encoding: .utf8) { emit(s) }

            self.installProcessForKill(nil)

            reply(process.terminationStatus)
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
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

        newConnection.exportedInterface = iface
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

