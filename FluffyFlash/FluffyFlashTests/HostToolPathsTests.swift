//
//  HostToolPathsTests.swift
//  FluffyFlashTests
//
//  Confirms that the subprocess `PATH` for `convert.sh` always begins with the
//  bundled `Tools/bin` directory when one is available, so the ISO pipeline
//  works on Macs without Homebrew.
//

import Foundation
import Testing
@testable import Wist

struct HostToolPathsTests {

    @Test("Bundled directory is prepended to subprocess PATH")
    func bundledDirIsFirst() {
        let bundled = URL(fileURLWithPath: "/Applications/FakeApp.app/Contents/Resources")
        let path = HostToolPaths.composeSubprocessPATH(
            bundledBin: bundled,
            processPATH: "/usr/bin:/bin"
        )
        #expect(path.hasPrefix(bundled.path + ":"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/usr/local/bin"))
        #expect(path.contains("/usr/bin"))
    }

    @Test("Order: bundled → extendedPATH → process PATH")
    func pathOrderingIsStable() {
        let bundled = URL(fileURLWithPath: "/tmp/bundle/bin")
        let processPath = "/some/extra/path"
        let path = HostToolPaths.composeSubprocessPATH(
            bundledBin: bundled,
            processPATH: processPath
        )
        let bundledIdx = path.range(of: bundled.path)!.lowerBound
        let extendedIdx = path.range(of: "/opt/homebrew/bin")!.lowerBound
        let processIdx = path.range(of: processPath)!.lowerBound
        #expect(bundledIdx < extendedIdx)
        #expect(extendedIdx < processIdx)
    }

    @Test("Empty bundled dir still produces a usable PATH")
    func nilBundledStillWorks() {
        let path = HostToolPaths.composeSubprocessPATH(
            bundledBin: nil,
            processPATH: nil
        )
        #expect(!path.isEmpty)
        #expect(path.contains("/usr/bin"))
        #expect(path.contains("/opt/homebrew/bin"))
    }

    @Test("subprocessPATHForDiagnostics matches composeSubprocessPATH for current process")
    func diagnosticsMatchesProductionPath() {
        let processPath = ProcessInfo.processInfo.environment["PATH"]
        let expected = HostToolPaths.composeSubprocessPATH(
            bundledBin: BundledToolLocator.bundledToolsBinDirectory(),
            processPATH: processPath
        )
        #expect(HostToolPaths.subprocessPATHForDiagnostics() == expected)
    }
}
