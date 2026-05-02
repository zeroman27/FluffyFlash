//
//  FluffyMacOSUSBMetadataTests.swift
//  FluffyFlashTests
//

import Foundation
import Testing

@testable import Wist

struct FluffyMacOSUSBMetadataTests {
    @Test func roundTripEncodeDecode() throws {
        let original = FluffyMacOSUSBMetadata(
            fluffyAppVersion: "1.2.3",
            fluffyAppBuild: "456",
            installerDisplayName: "Install macOS Test",
            installerShortVersion: "15.0",
            installerBundleVersion: "24A123"
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(original)
        let decoded = try JSONDecoder().decode(FluffyMacOSUSBMetadata.self, from: data)
        #expect(decoded == original)
        #expect(decoded.schemaVersion == FluffyMacOSUSBMetadata.currentSchema)
    }

    @Test func readWritesTempFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let meta = FluffyMacOSUSBMetadata(
            fluffyAppVersion: "2",
            fluffyAppBuild: nil,
            installerDisplayName: "Install macOS X",
            installerShortVersion: "14.1",
            installerBundleVersion: nil
        )
        try meta.write(to: tempDir)
        let read = FluffyMacOSUSBMetadata.read(from: tempDir)
        #expect(read == meta)
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func makeAfterWritePrefersVolumeApp() throws {
        let vol = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = vol.appendingPathComponent("Install macOS Z 26.1-25A100.app")
        let contents = app.appendingPathComponent("Contents")
        let res = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
        // Minimal “createinstallmedia” placeholder (empty file is not executable — use shebang script)
        let cim = res.appendingPathComponent("createinstallmedia")
        try "#!/bin/sh\necho ok\n".data(using: .utf8)!.write(to: cim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cim.path)
        let plist: [String: Any] = [
            "CFBundleDisplayName": "Install macOS Z",
            "CFBundleShortVersionString": "26.1",
            "CFBundleVersion": "25A100",
        ]
        let pData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try pData.write(to: contents.appendingPathComponent("Info.plist"))

        let fallback = vol.appendingPathComponent("Fallback.app")
        try FileManager.default.createDirectory(at: fallback.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: fallback.appendingPathComponent("Contents/Info.plist"))

        let meta = try FluffyMacOSUSBMetadata.makeAfterWrite(volumeRoot: vol, fallbackInstallerAppURL: fallback)
        #expect(meta.installerShortVersion == "26.1")
        #expect(meta.installerBundleVersion == "25A100")
        #expect(meta.installerMarketingVersion == "26.1")
        #expect(meta.installerAppleBuildFromName == "25A100")
        try? FileManager.default.removeItem(at: vol)
    }

    @Test func makePrefersMarketingFromBundleNameOverInternalPlist() throws {
        let vol = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = vol.appendingPathComponent("Install macOS Tahoe 26.4.1-25E253.app")
        let contents = app.appendingPathComponent("Contents")
        let res = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
        let cim = res.appendingPathComponent("createinstallmedia")
        try "#!/bin/sh\necho ok\n".data(using: .utf8)!.write(to: cim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cim.path)
        let plist: [String: Any] = [
            "CFBundleDisplayName": "Install macOS Tahoe",
            "CFBundleShortVersionString": "21.4.01",
            "CFBundleVersion": "21401",
            "DTPlatformVersion": "26.4",
        ]
        let pData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try pData.write(to: contents.appendingPathComponent("Info.plist"))

        let meta = try FluffyMacOSUSBMetadata.makeAfterWrite(
            volumeRoot: vol,
            fallbackInstallerAppURL: app
        )
        #expect(meta.installerShortVersion == "21.4.01")
        #expect(meta.installerBundleVersion == "21401")
        #expect(meta.installerMarketingVersion == "26.4.1")
        #expect(meta.installerAppleBuildFromName == "25E253")
        #expect(meta.installerDTPlatformVersion == "26.4")
        #expect(meta.summarySubtitle.contains("26.4.1"))
        #expect(meta.summarySubtitle.contains("25E253"))
        try? FileManager.default.removeItem(at: vol)
    }

    @Test func preferredVolumePicksInstallerPartition() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-efi")
        let good = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-install")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)

        let app = good.appendingPathComponent("Install macOS Z.app")
        let res = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
        let cim = res.appendingPathComponent("createinstallmedia")
        try "#!/bin/sh\n".data(using: .utf8)!.write(to: cim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cim.path)
        try Data("{}".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))

        let pick = FluffyMacOSUSBMetadata.preferredVolumeRootForInstaller(among: [empty, good])
        #expect(pick?.standardizedFileURL == good.standardizedFileURL)

        try? FileManager.default.removeItem(at: empty)
        try? FileManager.default.removeItem(at: good)
    }
}
