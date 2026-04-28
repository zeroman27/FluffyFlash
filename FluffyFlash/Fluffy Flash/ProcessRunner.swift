//
//  ProcessRunner.swift
//  Wist
//
//  Async `Process` execution with cancellation. Pattern inspired by CrystalFetch’s Worker.execv
//  (Turing Software, Apache-2.0 — https://github.com/TuringSoftware/CrystalFetch ).
//

import Foundation

enum ProcessRunnerError: Error {
    case failed(exitCode: Int32, stderr: String)
    case launchFailed(Error)
}

extension ProcessRunnerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failed(let code, let stderr):
            let tail = stderr
                .split(whereSeparator: \.isNewline)
                .filter { !$0.isEmpty }
                .suffix(12)
                .joined(separator: "\n")
            let hint = tail.isEmpty ? "" : "\n\(tail)"
            return String(format: String(localized: "Process exited with code %lld.%@"), Int64(code), hint)
        case .launchFailed(let err):
            return String(format: String(localized: "Could not launch process: %@"), err.localizedDescription)
        }
    }
}

/// Runs a subprocess and waits asynchronously. Use for `wimlib-imagex`, shell scripts, etc.
enum ProcessRunner: Sendable {

    /// Runs `executableURL` with `arguments`, optional working directory and extra `environment` keys (merged with `ProcessInfo.processInfo.environment`).
    nonisolated static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil
    ) async throws {
        try await runCollectingOutput(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            onStdoutLine: nil,
            onStderrLine: nil
        )
    }

    /// Same as `run`, but streams each non-empty line to optional callbacks (handy for progress text from converters).
    nonisolated static func runCollectingOutput(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        onStdoutLine: (@Sendable (String) -> Void)?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        var env = Dictionary(uniqueKeysWithValues: ProcessInfo.processInfo.environment.map { ($0.key, $0.value) })
        environment?.forEach { env[$0.key] = $0.value }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        if let onStdoutLine {
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                Self.emitLines(from: handle.availableData, to: onStdoutLine)
            }
        }
        if let onStderrLine {
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                Self.emitLines(from: handle.availableData, to: onStderrLine)
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { proc in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                    if let onStdoutLine, !restOut.isEmpty {
                        Self.emitLines(from: restOut, to: onStdoutLine)
                    }
                    if let onStderrLine, !restErr.isEmpty {
                        Self.emitLines(from: restErr, to: onStderrLine)
                    }
                    let errText = String(data: restErr, encoding: .utf8) ?? ""
                    if proc.terminationReason == .exit, proc.terminationStatus == 0 {
                        continuation.resume()
                    } else if proc.terminationReason == .uncaughtSignal, proc.terminationStatus == SIGTERM {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        let outText = String(data: restOut, encoding: .utf8) ?? ""
                        let diag: String = {
                            let e = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let o = outText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if e.isEmpty { return outText }
                            if o.isEmpty { return errText }
                            return errText + "\n" + outText
                        }()
                        continuation.resume(throwing: ProcessRunnerError.failed(exitCode: proc.terminationStatus, stderr: diag))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error))
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    nonisolated private static func emitLines(from data: Data, to sink: (String) -> Void) {
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return }
        for line in string.split(whereSeparator: \.isNewline) where !line.isEmpty {
            sink(String(line))
        }
    }
}
