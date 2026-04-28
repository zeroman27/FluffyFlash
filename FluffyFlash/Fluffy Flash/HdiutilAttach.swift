//
//  HdiutilAttach.swift
//  Wist
//

import Foundation

enum HdiutilError: LocalizedError {
    case noMountPointInPlist
    case parseFailed
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noMountPointInPlist: return String(localized: "hdiutil: no mount point in plist.")
        case .parseFailed: return String(localized: "hdiutil: could not parse output.")
        case .commandFailed(let s): return s
        }
    }
}

enum HdiutilAttach: Sendable {

    /// Attaches a disk image read-only; returns mount point for the Windows ISO volume.
    static func attachISOReadOnly(at isoURL: URL, logLine: @escaping @Sendable (String) -> Void) async throws -> URL {
        let data = try await runHdiutilReturningStdout(
            arguments: ["attach", "-readonly", "-nobrowse", "-plist", isoURL.path],
            logLine: logLine
        )
        return try parseMountPointPlist(data)
    }

    static func detach(mountPoint: URL, logLine: @escaping @Sendable (String) -> Void) async throws {
        let data = try await runHdiutilReturningStdout(
            arguments: ["detach", mountPoint.path],
            logLine: logLine
        )
        if !data.isEmpty, let s = String(data: data, encoding: .utf8) {
            logLine(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func runHdiutilReturningStdout(
        arguments: [String],
        logLine: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        let process = Process()
        process.executableURL = BundledToolLocator.hdiutil
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard let s = String(data: chunk, encoding: .utf8), !s.isEmpty else { return }
            for line in s.split(whereSeparator: \.isNewline) where !line.isEmpty {
                logLine(String(line))
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                process.terminationHandler = { proc in
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if proc.terminationReason == .exit, proc.terminationStatus == 0 {
                        continuation.resume(returning: stdout)
                    } else if proc.terminationReason == .uncaughtSignal, proc.terminationStatus == SIGTERM {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: HdiutilError.commandFailed(stderr.isEmpty ? "hdiutil exit \(proc.terminationStatus)" : stderr))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    private static func parseMountPointPlist(_ data: Data) throws -> URL {
        guard !data.isEmpty else { throw HdiutilError.parseFailed }
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = obj as? [String: Any] else { throw HdiutilError.parseFailed }
        if let entities = root["system-entities"] as? [[String: Any]] {
            for ent in entities {
                if let mp = ent["mount-point"] as? String, !mp.isEmpty {
                    return URL(fileURLWithPath: mp)
                }
            }
        }
        throw HdiutilError.noMountPointInPlist
    }
}
