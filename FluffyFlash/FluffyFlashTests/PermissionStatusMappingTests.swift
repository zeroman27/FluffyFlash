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
}
