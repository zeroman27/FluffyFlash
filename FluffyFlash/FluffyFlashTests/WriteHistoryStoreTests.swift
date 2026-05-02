//
//  WriteHistoryStoreTests.swift
//  FluffyFlashTests
//

import Foundation
import Testing
@testable import Wist

@MainActor
struct WriteHistoryStoreTests {

    @Test("Appended entry is the newest, append-only with cap")
    func appendCapAndOrdering() {
        let store = WriteHistoryStore(maxEntries: 3)
        store.clear()
        for i in 0 ..< 5 {
            let entry = WriteHistoryEntry(
                id: UUID(),
                dateISO8601: ISO8601DateFormatter().string(from: Date()),
                buildUuid: "u\(i)",
                buildNumber: "\(i)",
                buildTitle: nil,
                arch: "amd64",
                language: "en",
                editionToken: "Pro",
                driveMediaName: "USB Drive",
                driveDeviceIdentifier: "disk\(i)",
                isoPath: nil,
                succeeded: true,
                errorMessage: nil,
                logFileName: nil,
                averageWriteSpeedBytesPerSecond: nil,
                kind: nil,
                durationSeconds: nil,
                installerDisplayName: nil,
                installerMarketingVersion: nil,
                macOSCatalogBuild: nil
            )
            store.append(entry)
        }
        #expect(store.entries.count == 3)
        #expect(store.entries.first?.driveDeviceIdentifier == "disk4")
    }

    @Test("isKnownSlowDrive reflects most recent recorded throughput")
    func slowDriveDetection() {
        let store = WriteHistoryStore(maxEntries: 100)
        store.clear()
        let media = "Slowstick 16GB"
        store.append(WriteHistoryEntry(
            id: UUID(),
            dateISO8601: ISO8601DateFormatter().string(from: Date()),
            buildUuid: "u",
            buildNumber: "1",
            buildTitle: nil,
            arch: "amd64",
            language: "en",
            editionToken: "Pro",
            driveMediaName: media,
            driveDeviceIdentifier: "disk1",
            isoPath: nil,
            succeeded: true,
            errorMessage: nil,
            logFileName: nil,
            averageWriteSpeedBytesPerSecond: 4 * 1024 * 1024,
            kind: nil,
            durationSeconds: nil,
            installerDisplayName: nil,
            installerMarketingVersion: nil,
            macOSCatalogBuild: nil
        ))
        #expect(store.isKnownSlowDrive(mediaName: media) == true)
        #expect(store.isKnownSlowDrive(mediaName: "Other") == false)
    }

    @Test("expectedSpeedRange returns nil for unseen drives and a soft band for known ones")
    func expectedSpeedRangeSoftBand() {
        let store = WriteHistoryStore(maxEntries: 100)
        store.clear()
        #expect(store.expectedSpeedRange(for: "Unknown") == nil)

        let media = "Reliable Stick"
        let speed: Double = 20 * 1024 * 1024
        store.append(WriteHistoryEntry(
            id: UUID(),
            dateISO8601: ISO8601DateFormatter().string(from: Date()),
            buildUuid: "u",
            buildNumber: "1",
            buildTitle: nil,
            arch: "amd64",
            language: "en",
            editionToken: "Pro",
            driveMediaName: media,
            driveDeviceIdentifier: "disk2",
            isoPath: nil,
            succeeded: true,
            errorMessage: nil,
            logFileName: nil,
            averageWriteSpeedBytesPerSecond: speed,
            kind: nil,
            durationSeconds: nil,
            installerDisplayName: nil,
            installerMarketingVersion: nil,
            macOSCatalogBuild: nil
        ))

        let range = try? #require(store.expectedSpeedRange(for: media))
        #expect(range != nil)
        if let range {
            #expect(range.lowMBps < range.highMBps)
            #expect(range.lowMBps < 20)
            #expect(range.highMBps > 20)
        }
    }

    @Test("expectedDurationRangeSeconds is nil without history and produces a sane range otherwise")
    func expectedDurationRange() {
        let store = WriteHistoryStore(maxEntries: 100)
        store.clear()
        let media = "Average Stick"
        let speed: Double = 10 * 1024 * 1024
        store.append(WriteHistoryEntry(
            id: UUID(),
            dateISO8601: ISO8601DateFormatter().string(from: Date()),
            buildUuid: "u",
            buildNumber: "1",
            buildTitle: nil,
            arch: "amd64",
            language: "en",
            editionToken: "Pro",
            driveMediaName: media,
            driveDeviceIdentifier: "disk3",
            isoPath: nil,
            succeeded: true,
            errorMessage: nil,
            logFileName: nil,
            averageWriteSpeedBytesPerSecond: speed,
            kind: nil,
            durationSeconds: nil,
            installerDisplayName: nil,
            installerMarketingVersion: nil,
            macOSCatalogBuild: nil
        ))

        #expect(store.expectedDurationRangeSeconds(for: "Unknown", payloadBytes: 1 << 30) == nil)

        // 5 GiB payload at ~10 MB/s should land roughly between 7 and 11 minutes.
        let payload: UInt64 = 5 * 1024 * 1024 * 1024
        let duration = store.expectedDurationRangeSeconds(for: media, payloadBytes: payload)
        #expect(duration != nil)
        if let duration {
            #expect(duration.lowerBound > 5 * 60)
            #expect(duration.upperBound < 20 * 60)
        }
    }

    @Test("Legacy JSON without new history fields still decodes")
    func decodesLegacyWriteHistoryEntryJSON() throws {
        let json = """
        [{"id":"550E8400-E29B-41D4-A716-446655440000","dateISO8601":"2020-01-01T00:00:00Z","buildUuid":"u","buildNumber":"1","buildTitle":null,"arch":"amd64","language":"en","editionToken":"Pro","driveMediaName":"X","driveDeviceIdentifier":"disk1","isoPath":null,"succeeded":true,"errorMessage":null,"logFileName":null,"averageWriteSpeedBytesPerSecond":null}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([WriteHistoryEntry].self, from: json)
        #expect(decoded.count == 1)
        #expect(decoded[0].resolvedKind == .windowsUUP)
        #expect(decoded[0].kind == nil)
        #expect(decoded[0].durationSeconds == nil)
    }

    @Test("recordMacOSInstallerRun sets macOS kind and duration")
    func recordMacOSInstallerRunStoresKindAndDuration() throws {
        let store = WriteHistoryStore(maxEntries: 50)
        store.clear()
        let drive = RemovableDriveInfo(
            deviceIdentifier: "diskZ",
            mediaName: "Stick",
            totalSizeBytes: 16_000_000_000,
            wistSidecarMeta: nil,
            fluffyMacOSSidecarMeta: nil,
            mountPoint: nil
        )
        let start = Date().addingTimeInterval(-125)
        let end = Date()
        store.recordMacOSInstallerRun(
            drives: [drive],
            succeeded: true,
            errorMessage: nil,
            fullLogText: nil,
            catalogBuild: "22G120",
            catalogInstallerName: "macOS Ventura",
            startedAt: start,
            endedAt: end,
            speedsByDeviceId: [:]
        )
        let e = try #require(store.entries.first)
        #expect(e.resolvedKind == .macOSInstaller)
        #expect(e.durationSeconds != nil)
        #expect((e.durationSeconds ?? 0) > 120)
        #expect(e.buildNumber == "22G120")
    }

    @Test("record stores Windows historyKind and duration")
    func windowsRecordStoresKindAndDuration() throws {
        let store = WriteHistoryStore(maxEntries: 10)
        store.clear()
        let drive = RemovableDriveInfo(
            deviceIdentifier: "diskW",
            mediaName: "W",
            totalSizeBytes: 8,
            wistSidecarMeta: nil,
            fluffyMacOSSidecarMeta: nil,
            mountPoint: nil
        )
        let meta = WistUSBMetadata(
            buildUuid: "uuid",
            buildNumber: "22621",
            arch: "amd64",
            language: "en",
            editionToken: "Pro",
            buildTitle: "Test",
            sourceIsoPath: nil
        )
        store.record(
            build: nil,
            metadata: meta,
            drives: [drive],
            isoPath: "/tmp/x.iso",
            succeeded: true,
            historyKind: .windowsExistingISO,
            durationSeconds: 42.5
        )
        let e = try #require(store.entries.first)
        #expect(e.resolvedKind == .windowsExistingISO)
        #expect(e.durationSeconds == 42.5)
    }
}
