//
//  AppLaunchSession.swift
//  Fluffy Flash
//
//  Process-scoped launch gate: after the user has left the splash once (or closed
//  the window while the app keeps running), do not show the launch video again
//  until the process exits.
//

import Foundation

enum AppLaunchSession {
    private(set) static var hasPassedLaunchGateThisProcess = false

    static func markPassedLaunchGate() {
        hasPassedLaunchGateThisProcess = true
    }
}
