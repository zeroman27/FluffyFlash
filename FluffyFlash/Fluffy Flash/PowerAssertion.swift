//
//  PowerAssertion.swift
//  Fluffy Flash
//
//  Thin wrapper around `IOPMAssertionCreateWithName` so long-running pipelines
//  (UUP download → ISO build → USB write) can prevent the system from going to
//  idle sleep. The assertion is released automatically on `release()` or when
//  the instance is deinitialised.
//

import Foundation
import IOKit
import IOKit.pwr_mgt

/// Manages a single `kIOPMAssertionTypeNoIdleSleep` assertion. Re-entrant calls
/// to `acquire(reason:)` are no-ops; the matching `release()` actually clears
/// the assertion. This is intentionally a class so callers can hand the same
/// instance to nested tasks without worrying about copy semantics.
final class PowerAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false
    private let lock = NSLock()

    func acquire(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !isActive else { return }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID
        )
        if result == kIOReturnSuccess {
            assertionID = newID
            isActive = true
        }
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
    }
}
