//
//  ProcessRunnerTests.swift
//  FluffyFlashTests
//
//  Verifies that subprocess failures preserve the streamed stderr in the
//  thrown error description. Before the fix the streaming readability handler
//  drained stderr before the termination handler ran, leaving the error with
//  only "Process exited with code 1." and no actual cause.
//

import Foundation
import Testing
@testable import Wist

struct ProcessRunnerTests {

    @Test("Failed subprocess preserves stderr tail in errorDescription")
    func failedProcessIncludesStderr() async throws {
        var streamed: [String] = []
        let lock = NSLock()

        do {
            try await ProcessRunner.runCollectingOutput(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: ["-c", "echo boom-stderr 1>&2; echo boom-stdout; exit 1"],
                currentDirectoryURL: nil,
                environment: nil,
                onStdoutLine: { line in
                    lock.lock(); streamed.append("OUT:\(line)"); lock.unlock()
                },
                onStderrLine: { line in
                    lock.lock(); streamed.append("ERR:\(line)"); lock.unlock()
                }
            )
            Issue.record("Expected ProcessRunnerError.failed but completed without throwing.")
        } catch let error as ProcessRunnerError {
            switch error {
            case .failed(let code, let stderr):
                #expect(code == 1)
                #expect(stderr.contains("boom-stderr"))
            case .launchFailed(let inner):
                Issue.record("Unexpected launchFailed: \(inner.localizedDescription)")
            }
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
        #expect(streamed.contains(where: { $0.contains("boom-stderr") }))
        #expect(streamed.contains(where: { $0.contains("boom-stdout") }))
    }

    @Test("Successful subprocess does not throw")
    func successfulProcessReturnsCleanly() async throws {
        try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "echo hello"],
            currentDirectoryURL: nil,
            environment: nil
        )
    }
}
