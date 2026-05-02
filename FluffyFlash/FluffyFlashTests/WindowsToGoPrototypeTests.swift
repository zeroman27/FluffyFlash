//
//  WindowsToGoPrototypeTests.swift
//  FluffyFlashTests
//
//  Covers the only code that is safe to test offline: BSD-name validation
//  and `diskutil list -plist` parsing. The pipeline itself requires real USB
//  hardware and ntfs-3g, so we keep those out of the test suite.
//

import Foundation
import Testing
@testable import Wist

struct WindowsToGoPrototypeTests {

    // MARK: - validateBsdName

    @Test("Empty BSD name is rejected")
    func emptyBsdNameRejected() {
        #expect(throws: WindowsToGoPrototype.WTGError.self) {
            try WindowsToGoPrototype.validateBsdName("")
        }
    }

    @Test("BSD name must match diskN")
    func malformedBsdNameRejected() {
        #expect(throws: WindowsToGoPrototype.WTGError.self) {
            try WindowsToGoPrototype.validateBsdName("/dev/disk5")
        }
        #expect(throws: WindowsToGoPrototype.WTGError.self) {
            try WindowsToGoPrototype.validateBsdName("disk5s1")
        }
        #expect(throws: WindowsToGoPrototype.WTGError.self) {
            try WindowsToGoPrototype.validateBsdName("disk5; rm -rf /")
        }
    }

    @Test("Boot disk (disk0) is explicitly rejected")
    func bootDiskRejected() {
        #expect(throws: WindowsToGoPrototype.WTGError.self) {
            try WindowsToGoPrototype.validateBsdName("disk0")
        }
    }

    @Test("Well-formed external disk passes")
    func validBsdNameAccepted() throws {
        try WindowsToGoPrototype.validateBsdName("disk5")
        try WindowsToGoPrototype.validateBsdName("disk12")
    }

    // MARK: - parseLayout

    @Test("Parses two-partition GPT layout produced by diskutil partitionDisk")
    func parsesValidPlist() throws {
        let plist: [String: Any] = [
            "AllDisksAndPartitions": [[
                "DeviceIdentifier": "disk5",
                "Partitions": [
                    [
                        "DeviceIdentifier": "disk5s1",
                        "Content": "EFI",
                        "MountPoint": "/Volumes/EFI",
                        "Size": 200_000_000,
                    ],
                    [
                        "DeviceIdentifier": "disk5s2",
                        "Content": "Microsoft Basic Data",
                        "Size": 30_000_000_000,
                    ],
                ],
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let layout = try WindowsToGoPrototype.parseLayout(diskutilListPlist: data, parentDisk: "disk5")
        #expect(layout.espDeviceID == "disk5s1")
        #expect(layout.mainDeviceID == "disk5s2")
        #expect(layout.espMountPoint?.path == "/Volumes/EFI")
    }

    @Test("Throws when the parent disk is absent from the plist")
    func missingParentThrows() throws {
        let plist: [String: Any] = [
            "AllDisksAndPartitions": [[
                "DeviceIdentifier": "disk6",
                "Partitions": [["DeviceIdentifier": "disk6s1"]],
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(throws: WindowsToGoPrototype.WTGError.self) {
            _ = try WindowsToGoPrototype.parseLayout(diskutilListPlist: data, parentDisk: "disk5")
        }
    }

    @Test("Throws when fewer than two partitions are present")
    func tooFewPartitionsThrows() throws {
        let plist: [String: Any] = [
            "AllDisksAndPartitions": [[
                "DeviceIdentifier": "disk5",
                "Partitions": [["DeviceIdentifier": "disk5s1"]],
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(throws: WindowsToGoPrototype.WTGError.self) {
            _ = try WindowsToGoPrototype.parseLayout(diskutilListPlist: data, parentDisk: "disk5")
        }
    }

    @Test("Empty mount point string is treated as nil")
    func emptyMountIsNil() throws {
        let plist: [String: Any] = [
            "AllDisksAndPartitions": [[
                "DeviceIdentifier": "disk5",
                "Partitions": [
                    ["DeviceIdentifier": "disk5s1", "MountPoint": ""],
                    ["DeviceIdentifier": "disk5s2"],
                ],
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let layout = try WindowsToGoPrototype.parseLayout(diskutilListPlist: data, parentDisk: "disk5")
        #expect(layout.espMountPoint == nil)
    }
}
