//
//  MacOSInstallerVersionRankTests.swift
//  FluffyFlashTests
//

import Foundation
import Testing

@testable import Wist

struct MacOSInstallerVersionRankTests {
    @Test func marketingVersionNewer() {
        let m = FluffyMacOSUSBMetadata(
            fluffyAppVersion: "1",
            fluffyAppBuild: "1",
            installerDisplayName: "Install macOS X",
            installerShortVersion: "15.0",
            installerBundleVersion: "24A123"
        )
        let item = MistCLITool.InstallerListItem(
            name: "Install macOS X",
            version: "15.1",
            build: "24B100",
            sizeBytes: nil,
            releaseDateISO8601: nil
        )
        #expect(MacOSInstallerVersionRank.isLatestStrictlyNewer(latest: item, current: m))
    }

    @Test func sameVersionBuildCompare() {
        let m = FluffyMacOSUSBMetadata(
            fluffyAppVersion: "1",
            fluffyAppBuild: "1",
            installerDisplayName: "Install macOS X",
            installerShortVersion: "15.1",
            installerBundleVersion: "24A1"
        )
        let item = MistCLITool.InstallerListItem(
            name: "Install macOS X",
            version: "15.1",
            build: "24B1",
            sizeBytes: nil,
            releaseDateISO8601: nil
        )
        #expect(MacOSInstallerVersionRank.isLatestStrictlyNewer(latest: item, current: m))
    }

    @Test func catalogMatchesMarketingFromBundleDespiteInternalPlist() {
        let m = FluffyMacOSUSBMetadata(
            fluffyAppVersion: "1",
            fluffyAppBuild: "1",
            installerDisplayName: "Install macOS Tahoe",
            installerShortVersion: "21.4.01",
            installerBundleVersion: "21401",
            installerMarketingVersion: "26.4.1",
            installerAppleBuildFromName: "25E253",
            installerDTPlatformVersion: "26.4"
        )
        let same = MistCLITool.InstallerListItem(
            name: "Install macOS Tahoe",
            version: "26.4.1",
            build: "25E253",
            sizeBytes: nil,
            releaseDateISO8601: nil
        )
        #expect(!MacOSInstallerVersionRank.isLatestStrictlyNewer(latest: same, current: m))

        let newer = MistCLITool.InstallerListItem(
            name: "Install macOS Tahoe",
            version: "26.5",
            build: "25F1",
            sizeBytes: nil,
            releaseDateISO8601: nil
        )
        #expect(MacOSInstallerVersionRank.isLatestStrictlyNewer(latest: newer, current: m))
    }
}
