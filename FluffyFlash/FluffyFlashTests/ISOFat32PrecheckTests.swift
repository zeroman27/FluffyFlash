//
//  ISOFat32PrecheckTests.swift
//  FluffyFlashTests
//

import Foundation
import Testing
@testable import Wist

struct ISOFat32PrecheckTests {

    @Test("Empty oversize list passes validation")
    func emptyListPasses() throws {
        try ISOFat32Precheck.validateOnlyInstallImagesAreOversize([])
    }

    @Test("install.wim and install.esd are tolerated as oversize")
    func installImagesAreAllowed() throws {
        let entries = [
            ISOFat32Precheck.OversizeEntry(relativePath: "sources/install.wim", sizeBytes: 5_000_000_000),
            ISOFat32Precheck.OversizeEntry(relativePath: "sources/install.esd", sizeBytes: 4_500_000_000),
            ISOFat32Precheck.OversizeEntry(relativePath: "Sources/Install.WIM", sizeBytes: 5_000_000_000),
        ]
        try ISOFat32Precheck.validateOnlyInstallImagesAreOversize(entries)
    }

    @Test("Other oversize files throw fat32OversizeUnsupported")
    func otherFilesAreRejected() {
        let entries = [
            ISOFat32Precheck.OversizeEntry(relativePath: "movies/big.mkv", sizeBytes: 5_000_000_000),
        ]
        #expect(throws: USBWriterError.self) {
            try ISOFat32Precheck.validateOnlyInstallImagesAreOversize(entries)
        }
    }

    @Test("FAT32 max size constant matches the spec")
    func maxSingleFileBytes() {
        #expect(ISOFat32Precheck.maxSingleFileBytes == 4_294_967_295)
    }
}
