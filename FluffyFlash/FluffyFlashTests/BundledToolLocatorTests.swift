//
//  BundledToolLocatorTests.swift
//  FluffyFlashTests
//
//  Verifies that `BundledToolLocator.detectBundledBinDirectory` correctly
//  resolves both the nested `Tools/bin/` layout and the flat
//  `Contents/Resources/<exe>` layout produced by Xcode's
//  `PBXFileSystemSynchronizedRootGroup`. Without the flat-fallback the
//  bundled CLI tools were not being added to `PATH` for `convert.sh`,
//  which is what caused the ISO build to fail on a Mac without Homebrew.
//

import Foundation
import Testing
@testable import Wist

struct BundledToolLocatorTests {

    @Test("Returns nested Tools/bin when present")
    func nestedToolsBinPreferred() throws {
        let layout = try makeFakeBundle(withNested: true, withFlat: true)
        defer { try? FileManager.default.removeItem(at: layout.appURL) }

        let result = BundledToolLocator.detectBundledBinDirectory(
            resourceURL: layout.resourcesURL,
            bundleURL: layout.appURL
        )
        #expect(result == layout.toolsBinURL)
    }

    @Test("Falls back to flat Resources layout (Xcode synchronized group)")
    func flatLayoutFallback() throws {
        let layout = try makeFakeBundle(withNested: false, withFlat: true)
        defer { try? FileManager.default.removeItem(at: layout.appURL) }

        let result = BundledToolLocator.detectBundledBinDirectory(
            resourceURL: layout.resourcesURL,
            bundleURL: layout.appURL
        )
        #expect(result == layout.resourcesURL)
    }

    @Test("Returns nil when neither layout has tools")
    func emptyBundleReturnsNil() throws {
        let layout = try makeFakeBundle(withNested: false, withFlat: false)
        defer { try? FileManager.default.removeItem(at: layout.appURL) }

        let result = BundledToolLocator.detectBundledBinDirectory(
            resourceURL: layout.resourcesURL,
            bundleURL: layout.appURL
        )
        #expect(result == nil)
    }

    @Test("hasAnyMarkerExecutable detects flat aria2c")
    func detectsMarkerExecutable() throws {
        let layout = try makeFakeBundle(withNested: false, withFlat: true)
        defer { try? FileManager.default.removeItem(at: layout.appURL) }
        #expect(BundledToolLocator.hasAnyMarkerExecutable(in: layout.resourcesURL))
    }

    // MARK: - Helpers

    private struct FakeBundleLayout {
        let appURL: URL
        let resourcesURL: URL
        let toolsBinURL: URL
    }

    private func makeFakeBundle(withNested: Bool, withFlat: Bool) throws -> FakeBundleLayout {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("WistBundleTests-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("FakeApp.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let toolsBin = resources.appendingPathComponent("Tools/bin", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        if withNested {
            try fm.createDirectory(at: toolsBin, withIntermediateDirectories: true)
            try writeExecutable(at: toolsBin.appendingPathComponent("aria2c"))
        }
        if withFlat {
            try writeExecutable(at: resources.appendingPathComponent("aria2c"))
        }
        return FakeBundleLayout(appURL: app, resourcesURL: resources, toolsBinURL: toolsBin)
    }

    private func writeExecutable(at url: URL) throws {
        let fm = FileManager.default
        try Data("#!/bin/sh\necho stub".utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
