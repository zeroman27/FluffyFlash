//
//  UUPBuildFiltersTests.swift
//  FluffyFlashTests
//

import Foundation
import Testing
@testable import Wist

struct UUPBuildFiltersTests {

    private func makeBuild(title: String, build: String = "26100.1", arch: String = "amd64") throws -> UUPBuilds.Build {
        let json = """
        { "title": "\(title)", "build": "\(build)", "arch": "\(arch)", "created": 0, "uuid": "u" }
        """
        return try JSONDecoder().decode(UUPBuilds.Build.self, from: Data(json.utf8))
    }

    @Test("uupProductLine recognises Windows 10/11/Server")
    func productLineHeuristics() throws {
        #expect(try makeBuild(title: "Windows 11 26100").uupProductLine == .windows11)
        #expect(try makeBuild(title: "Windows 10 19045").uupProductLine == .windows10)
        #expect(try makeBuild(title: "Windows Server 2025").uupProductLine == .windowsServer)
        #expect(try makeBuild(title: "Some Random ISO").uupProductLine == .other)
    }

    @Test("uupIsInsiderStyleChannel covers Insider/Canary/Dev/Beta/Release Preview")
    func insiderHeuristics() throws {
        #expect(try makeBuild(title: "Windows 11 Insider 26100").uupIsInsiderStyleChannel == true)
        #expect(try makeBuild(title: "Windows 11 Canary 27000").uupIsInsiderStyleChannel == true)
        #expect(try makeBuild(title: "Dev Channel build").uupIsInsiderStyleChannel == true)
        #expect(try makeBuild(title: "Beta Channel build").uupIsInsiderStyleChannel == true)
        #expect(try makeBuild(title: "Release Preview").uupIsInsiderStyleChannel == true)
        #expect(try makeBuild(title: "Windows 11 26100").uupIsInsiderStyleChannel == false)
    }

    @Test("uupBuildVersionRank parses dotted build strings")
    func buildVersionRank() throws {
        let high = try makeBuild(title: "x", build: "26100.1742")
        let low = try makeBuild(title: "x", build: "22631.123")
        #expect(high.uupBuildVersionRank > low.uupBuildVersionRank)
    }
}
