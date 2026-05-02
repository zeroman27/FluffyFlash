//
//  WistUSBMetadataTests.swift
//  FluffyFlashTests
//

import Foundation
import Testing
@testable import Wist

struct WistUSBMetadataTests {

    @Test("Round-trip: JSON encode then decode preserves all fields")
    func roundTripPreservesFields() throws {
        let chunks = [
            SplitChunkInfo(fileName: "install.swm", sizeBytes: 1234, sha256: "deadbeef"),
            SplitChunkInfo(fileName: "install.swm2", sizeBytes: 5678, sha256: "feedface"),
        ]
        let original = WistUSBMetadata(
            buildUuid: "uuid-1",
            buildNumber: "26100.1742",
            arch: "amd64",
            language: "en-us",
            editionToken: "Pro",
            buildTitle: "Windows 11",
            sourceIsoPath: "/tmp/win.iso",
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceIsoSHA256: "abcd",
            splitChunks: chunks
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WistUSBMetadata.self, from: data)

        #expect(decoded.buildUuid == "uuid-1")
        #expect(decoded.buildNumber == "26100.1742")
        #expect(decoded.arch == "amd64")
        #expect(decoded.editionToken == "Pro")
        #expect(decoded.sourceIsoSHA256 == "abcd")
        #expect(decoded.splitChunks?.count == 2)
        #expect(decoded.splitChunks?[1].fileName == "install.swm2")
        #expect(decoded.schemaVersion == WistUSBMetadata.currentSchema)
    }

    @Test("v1 metadata without sourceIsoSHA256/splitChunks still decodes")
    func decodesV1Metadata() throws {
        let v1JSON = """
        {
            "schemaVersion": 1,
            "buildUuid": "uuid-1",
            "buildNumber": "22631.123",
            "arch": "arm64",
            "language": "ru-ru",
            "editionToken": "Home",
            "writtenAt": "2025-01-01T00:00:00Z"
        }
        """
        let data = Data(v1JSON.utf8)
        let decoded = try JSONDecoder().decode(WistUSBMetadata.self, from: data)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.sourceIsoSHA256 == nil)
        #expect(decoded.splitChunks == nil)
        #expect(decoded.buildUuid == "uuid-1")
    }

    @Test("read(from:) finds the new fileName first, then falls back to legacy names")
    func readsLegacyFileName() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WistMetaTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let legacyJSON = #"{"schemaVersion":1,"buildUuid":"legacy","buildNumber":"1","arch":"amd64","language":"en","editionToken":"Pro","writtenAt":"2025-01-01T00:00:00Z"}"#
        let legacyURL = tempDir.appendingPathComponent("WinForge.meta.json")
        try Data(legacyJSON.utf8).write(to: legacyURL)

        let result = WistUSBMetadata.read(from: tempDir)
        #expect(result?.buildUuid == "legacy")
    }
}
