//
//  PermissionStatusMappingTests.swift
//  FluffyFlashTests
//

import Testing
import UserNotifications
@testable import Wist

struct PermissionStatusMappingTests {

    @Test("Notification authorization maps to PermissionStatus")
    func notificationAuthorizationMapping() {
        #expect(PermissionStatus.fromNotificationAuthorization(.authorized) == .granted)
        #expect(PermissionStatus.fromNotificationAuthorization(.provisional) == .granted)
        #expect(PermissionStatus.fromNotificationAuthorization(.denied) == .denied)
        #expect(PermissionStatus.fromNotificationAuthorization(.notDetermined) == .notDetermined)
    }

    @Test("PermissionStatus has stable raw values (including outdated)")
    func permissionStatusRawValues() {
        #expect(PermissionStatus.granted.rawValue == "granted")
        #expect(PermissionStatus.outdated.rawValue == "outdated")
        #expect(PermissionStatus.denied.rawValue == "denied")
        #expect(PermissionStatus.notDetermined.rawValue == "notDetermined")
        #expect(PermissionStatus.unknown.rawValue == "unknown")
    }
}
