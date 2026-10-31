import XCTest
@testable import RuleEngine

final class PINPolicyTests: XCTestCase {
    func testAcceptsValidPINs() {
        for pin in ["483920", "2749163", "90317465"] {
            XCTAssertEqual(PINPolicy.validate(pin), [], pin)
        }
    }

    func testLengthBoundaries() {
        XCTAssertEqual(PINPolicy.validate("48392"), [.wrongLength(count: 5)])
        XCTAssertEqual(PINPolicy.validate("483920"), [])
        XCTAssertEqual(PINPolicy.validate("48392017"), [])
        XCTAssertEqual(PINPolicy.validate("483920175"), [.wrongLength(count: 9)])
        XCTAssertEqual(PINPolicy.validate(""), [.wrongLength(count: 0)])
    }

    func testOnlyASCIIDigits() {
        XCTAssertEqual(PINPolicy.validate("48392a"), [.notDigits])
        XCTAssertEqual(PINPolicy.validate("483 20"), [.notDigits])
        // Cifre arabo-indiane: Character.isNumber le accetterebbe.
        XCTAssertEqual(PINPolicy.validate("٤٨٣٩٢٠"), [.notDigits])
    }

    func testRejectsRepeatedDigits() {
        for pin in ["000000", "111111", "99999999"] {
            XCTAssertEqual(PINPolicy.validate(pin), [.trivial], pin)
        }
    }

    func testRejectsSequences() {
        for pin in ["123456", "654321", "12345678", "87654321", "012345", "890123", "210987"] {
            XCTAssertEqual(PINPolicy.validate(pin), [.trivial], pin)
        }
    }

    func testRejectsRepeatedPatterns() {
        for pin in ["121212", "123123", "12341234", "909090"] {
            XCTAssertEqual(PINPolicy.validate(pin), [.trivial], pin)
        }
    }

    func testAlmostTrivialIsAccepted() {
        XCTAssertEqual(PINPolicy.validate("123457"), [])
        XCTAssertEqual(PINPolicy.validate("121213"), [])
        XCTAssertEqual(PINPolicy.validate("1212123"), [])
    }

    func testMessagesAreItalian() {
        XCTAssertTrue(PINValidationError.notDigits.description.contains("cifre"))
        XCTAssertTrue(PINValidationError.wrongLength(count: 3).description.contains("6"))
        XCTAssertFalse(PINValidationError.trivial.description.isEmpty)
    }
}

final class ConstantTimeTests: XCTestCase {
    func testEquals() {
        XCTAssertTrue(ConstantTime.equals(Data([1, 2, 3]), Data([1, 2, 3])))
        XCTAssertTrue(ConstantTime.equals(Data(), Data()))
        XCTAssertFalse(ConstantTime.equals(Data([1, 2, 3]), Data([1, 2, 4])))
        XCTAssertFalse(ConstantTime.equals(Data([0, 2, 3]), Data([1, 2, 3])))
        XCTAssertFalse(ConstantTime.equals(Data([1, 2, 3]), Data([1, 2])))
    }

    func testSlicesWithNonZeroStartIndex() {
        let full = Data([9, 1, 2, 3])
        XCTAssertTrue(ConstantTime.equals(full.dropFirst(), Data([1, 2, 3])))
    }
}

final class PINAttemptPolicyTests: XCTestCase {
    private let start = date(2026, 11, 2, 10)

    /// Stato dopo `count` errori, l'ultimo dei quali a `start` (i precedenti a blocco già finito).
    private func policy(afterFailures count: Int) -> PINAttemptPolicy {
        var policy = PINAttemptPolicy(failedAttempts: count - 1)
        policy.registerFailure(at: start)
        return policy
    }

    func testFailuresInARowAtTheSameInstantStopAtTheLock() {
        var policy = PINAttemptPolicy()
        for _ in 0..<8 { policy.registerFailure(at: start) }
        XCTAssertEqual(policy.failedAttempts, 5)
        XCTAssertEqual(policy.remainingLockout(at: start), 60)
    }

    func testNoLockBeforeFiveFailures() {
        let policy = policy(afterFailures: 4)
        XCTAssertEqual(policy.failedAttempts, 4)
        XCTAssertFalse(policy.isLocked(at: start))
        XCTAssertEqual(policy.remainingLockout(at: start), 0)
    }

    func testFifthFailureLocksForOneMinute() {
        let policy = policy(afterFailures: 5)
        XCTAssertEqual(policy.remainingLockout(at: start), 60)
        XCTAssertTrue(policy.isLocked(at: start.addingTimeInterval(59)))
        XCTAssertFalse(policy.isLocked(at: start.addingTimeInterval(60)))
    }

    func testLockoutDoublesUpToOneHour() {
        let expected: [(Int, TimeInterval)] = [
            (5, 60), (6, 120), (7, 240), (8, 480), (9, 960), (10, 1920), (11, 3600), (12, 3600)
        ]
        for (failures, duration) in expected {
            XCTAssertEqual(policy(afterFailures: failures).remainingLockout(at: start), duration, "\(failures) errori")
        }
    }

    func testHugeFailureCountDoesNotOverflow() {
        let policy = PINAttemptPolicy(failedAttempts: 10_000, lockedUntil: nil)
        var updated = policy
        updated.registerFailure(at: start)
        XCTAssertEqual(updated.remainingLockout(at: start), 3600)
    }

    func testFailureDuringLockoutIsIgnored() {
        var policy = policy(afterFailures: 5)
        policy.registerFailure(at: start.addingTimeInterval(30))
        XCTAssertEqual(policy.failedAttempts, 5)
        XCTAssertEqual(policy.lockedUntil, start.addingTimeInterval(60))
    }

    func testFailureAfterLockoutDoubles() {
        var policy = policy(afterFailures: 5)
        let later = start.addingTimeInterval(60)
        policy.registerFailure(at: later)
        XCTAssertEqual(policy.failedAttempts, 6)
        XCTAssertEqual(policy.remainingLockout(at: later), 120)
    }

    func testSuccessResets() {
        var policy = policy(afterFailures: 7)
        policy.registerSuccess()
        XCTAssertEqual(policy, PINAttemptPolicy())
        XCTAssertFalse(policy.isLocked(at: start))
    }

    func testCodableRoundTrip() throws {
        let policy = policy(afterFailures: 6)
        let decoded = try JSONDecoder().decode(PINAttemptPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(decoded, policy)
        XCTAssertTrue(decoded.isLocked(at: start))
    }
}

final class PendingRelaxationTests: XCTestCase {
    private let start = date(2026, 11, 2, 10)

    func testDurations() {
        XCTAssertEqual(PendingRelaxation.cooldownDuration, 600)
        XCTAssertEqual(PendingRelaxation.confirmationWindow, 1800)
    }

    func testPhases() {
        let request = PendingRelaxation(change: .disableManualBlock, requestedAt: start)
        XCTAssertEqual(request.phase(at: start), .waiting)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(599)), .waiting)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(600)), .confirmable)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(2399)), .confirmable)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(2400)), .expired)
    }

    func testCanConfirmOnlyInsideWindow() {
        let request = PendingRelaxation(change: .disableManualBlock, requestedAt: start)
        XCTAssertFalse(request.canConfirm(at: start))
        XCTAssertTrue(request.canConfirm(at: start.addingTimeInterval(600)))
        XCTAssertFalse(request.canConfirm(at: start.addingTimeInterval(2400)))
    }

    func testClockMovedBeforeRequestStaysWaiting() {
        let request = PendingRelaxation(change: .disableManualBlock, requestedAt: start)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(-3600)), .waiting)
    }

    func testRemaining() {
        let request = PendingRelaxation(change: .disableManualBlock, requestedAt: start)
        XCTAssertEqual(request.remaining(at: start.addingTimeInterval(100)), 500)
        XCTAssertEqual(request.remaining(at: start.addingTimeInterval(700)), 0)
        XCTAssertEqual(request.confirmationRemaining(at: start.addingTimeInterval(700)), 1700)
        XCTAssertEqual(request.confirmationRemaining(at: start.addingTimeInterval(9_999)), 0)
    }

    func testTargets() {
        let id = UUID()
        let rule = Rule(id: id, name: "Social", kind: .dailyLimit(minutes: 30))
        let cases: [(PendingRelaxation.Change, PendingRelaxation.Target)] = [
            (.disableRule(id), .rule(id)),
            (.deleteRule(id), .rule(id)),
            (.editRule(rule), .rule(id)),
            (.disableManualBlock, .manualBlock),
            (.changeManualSelection, .manualBlock),
            (.disableAppRemovalProtection, .appRemovalProtection),
            (.resetPIN, .pinReset)
        ]
        for (change, target) in cases {
            XCTAssertEqual(PendingRelaxation(change: change, requestedAt: start).target, target)
        }
    }

    func testCodableRoundTrip() throws {
        let rule = limitRule(60)
        let changes: [PendingRelaxation.Change] = [
            .disableRule(rule.id), .deleteRule(rule.id), .editRule(rule),
            .disableManualBlock, .changeManualSelection, .disableAppRemovalProtection, .resetPIN
        ]
        for change in changes {
            let request = PendingRelaxation(change: change, requestedAt: start)
            let decoded = try JSONDecoder().decode(PendingRelaxation.self, from: JSONEncoder().encode(request))
            XCTAssertEqual(decoded, request)
        }
    }

    func testResetPINWaitsOneDayWithTheSameWindow() {
        XCTAssertEqual(PendingRelaxation.pinResetCooldownDuration, 86_400)

        let request = PendingRelaxation(change: .resetPIN, requestedAt: start)
        XCTAssertEqual(request.cooldown.duration, 86_400)
        XCTAssertEqual(request.remaining(at: start), 86_400)
        XCTAssertEqual(request.expiresAt, start.addingTimeInterval(86_400 + PendingRelaxation.confirmationWindow))

        XCTAssertEqual(request.phase(at: start.addingTimeInterval(600)), .waiting)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(86_399)), .waiting)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(86_400)), .confirmable)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(88_199)), .confirmable)
        XCTAssertEqual(request.phase(at: start.addingTimeInterval(88_200)), .expired)
    }

    func testOnlyResetPINSkipsAuthentication() {
        let id = UUID()
        let authenticated: [PendingRelaxation.Change] = [
            .disableRule(id), .deleteRule(id), .editRule(limitRule(30)),
            .disableManualBlock, .changeManualSelection, .disableAppRemovalProtection
        ]
        for change in authenticated {
            XCTAssertTrue(PendingRelaxation(change: change, requestedAt: start).requiresAuthentication, "\(change)")
        }
        XCTAssertFalse(PendingRelaxation(change: .resetPIN, requestedAt: start).requiresAuthentication)
    }
}

final class PendingRelaxationQueueTests: XCTestCase {
    private let start = date(2026, 11, 2, 10)

    func testEnqueueAndLookup() {
        var queue = PendingRelaxationQueue()
        let id = UUID()
        let request = queue.enqueue(.disableRule(id), at: start)
        XCTAssertEqual(queue.pending(for: .rule(id)), request)
        XCTAssertNil(queue.pending(for: .manualBlock))
        XCTAssertEqual(queue.request(id: request.id), request)
    }

    func testSecondRequestOnSameTargetKeepsTheFirst() {
        var queue = PendingRelaxationQueue()
        let id = UUID()
        let first = queue.enqueue(.disableRule(id), at: start)
        // Il timer non riparte e la richiesta non cambia.
        let second = queue.enqueue(.deleteRule(id), at: start.addingTimeInterval(300))
        XCTAssertEqual(second, first)
        XCTAssertEqual(queue.items, [first])
    }

    func testDifferentTargetsCoexist() {
        var queue = PendingRelaxationQueue()
        queue.enqueue(.disableRule(UUID()), at: start)
        queue.enqueue(.disableRule(UUID()), at: start)
        queue.enqueue(.disableManualBlock, at: start)
        queue.enqueue(.disableAppRemovalProtection, at: start)
        XCTAssertEqual(queue.items.count, 4)
    }

    func testResetPINDoesNotOccupyOtherTargets() {
        var queue = PendingRelaxationQueue()
        let id = UUID()
        let reset = queue.enqueue(.resetPIN, at: start)
        // Durante l'attesa del reset tutto il resto funziona normalmente.
        XCTAssertNil(queue.pending(for: .rule(id)))
        XCTAssertNil(queue.pending(for: .manualBlock))
        let disable = queue.enqueue(.disableRule(id), at: start)
        XCTAssertEqual(queue.items, [reset, disable])
    }

    func testRepeatedResetPINKeepsTheTimer() {
        var queue = PendingRelaxationQueue()
        let first = queue.enqueue(.resetPIN, at: start)
        XCTAssertEqual(queue.enqueue(.resetPIN, at: start.addingTimeInterval(3600)), first)
    }

    func testResetPINExpiresLaterThanOtherRequests() {
        var queue = PendingRelaxationQueue()
        let reset = queue.enqueue(.resetPIN, at: start)
        let disable = queue.enqueue(.disableManualBlock, at: start)
        XCTAssertEqual(queue.removeExpired(at: start.addingTimeInterval(2400)), [disable])
        XCTAssertEqual(queue.items, [reset])
    }

    func testRemove() {
        var queue = PendingRelaxationQueue()
        let request = queue.enqueue(.disableManualBlock, at: start)
        queue.remove(id: request.id)
        XCTAssertTrue(queue.items.isEmpty)
        // Dopo l'annullamento si può chiedere di nuovo, con un'attesa nuova.
        let again = queue.enqueue(.disableManualBlock, at: start.addingTimeInterval(60))
        XCTAssertEqual(again.cooldown.requestedAt, start.addingTimeInterval(60))
    }

    func testRemoveExpired() {
        var queue = PendingRelaxationQueue()
        let old = queue.enqueue(.disableManualBlock, at: start)
        let recent = queue.enqueue(.disableAppRemovalProtection, at: start.addingTimeInterval(1000))
        let removed = queue.removeExpired(at: start.addingTimeInterval(2400))
        XCTAssertEqual(removed, [old])
        XCTAssertEqual(queue.items, [recent])
    }
}

final class ManualBlockImpactTests: XCTestCase {
    func testActivationAndDeactivation() {
        XCTAssertEqual(ChangePolicy.manualBlockImpact(wasActive: false, isActive: true, selectionChanged: false), .tightening)
        XCTAssertEqual(ChangePolicy.manualBlockImpact(wasActive: true, isActive: false, selectionChanged: false), .relaxing)
        XCTAssertEqual(ChangePolicy.manualBlockImpact(wasActive: true, isActive: false, selectionChanged: true), .relaxing)
    }

    func testSelectionChange() {
        // A blocco attivo si potrebbero togliere tutte le app: token opachi, quindi prudenza.
        XCTAssertEqual(ChangePolicy.manualBlockImpact(wasActive: true, isActive: true, selectionChanged: true), .relaxing)
        XCTAssertEqual(ChangePolicy.manualBlockImpact(wasActive: true, isActive: true, selectionChanged: false), .neutral)
        // A blocco spento la selezione non blocca nulla.
        XCTAssertEqual(ChangePolicy.manualBlockImpact(wasActive: false, isActive: false, selectionChanged: true), .neutral)
    }
}

final class AppRemovalProtectionImpactTests: XCTestCase {
    func testImpactWithActiveRestrictions() {
        XCTAssertEqual(ChangePolicy.appRemovalProtectionImpact(wasEnabled: true, isEnabled: false, hasActiveRestrictions: true), .relaxing)
        XCTAssertEqual(ChangePolicy.appRemovalProtectionImpact(wasEnabled: false, isEnabled: true, hasActiveRestrictions: true), .tightening)
        XCTAssertEqual(ChangePolicy.appRemovalProtectionImpact(wasEnabled: true, isEnabled: true, hasActiveRestrictions: true), .neutral)
        XCTAssertEqual(ChangePolicy.appRemovalProtectionImpact(wasEnabled: false, isEnabled: false, hasActiveRestrictions: true), .neutral)
    }

    func testDisablingWithNothingActiveRelaxesNothing() {
        XCTAssertEqual(ChangePolicy.appRemovalProtectionImpact(wasEnabled: true, isEnabled: false, hasActiveRestrictions: false), .neutral)
        XCTAssertEqual(ChangePolicy.appRemovalProtectionImpact(wasEnabled: false, isEnabled: true, hasActiveRestrictions: false), .tightening)
    }
}

final class ProtectionPolicyTests: XCTestCase {
    private let on = limitRule(30)
    private let off = limitRule(30, enabled: false)

    func testHasActiveRestrictions() {
        XCTAssertTrue(ProtectionPolicy.hasActiveRestrictions(rules: [off, on], isManualBlockActive: false))
        XCTAssertTrue(ProtectionPolicy.hasActiveRestrictions(rules: [off], isManualBlockActive: true))
        XCTAssertFalse(ProtectionPolicy.hasActiveRestrictions(rules: [off], isManualBlockActive: false))
        XCTAssertFalse(ProtectionPolicy.hasActiveRestrictions(rules: [], isManualBlockActive: false))
    }

    func testDenyAppRemovalNeedsPreferenceAndSomethingActive() {
        XCTAssertTrue(ProtectionPolicy.shouldDenyAppRemoval(rules: [on], isManualBlockActive: false, appRemoval: .enabled))
        XCTAssertTrue(ProtectionPolicy.shouldDenyAppRemoval(rules: [off, on], isManualBlockActive: false, appRemoval: .enabled))
        XCTAssertTrue(ProtectionPolicy.shouldDenyAppRemoval(rules: [], isManualBlockActive: true, appRemoval: .enabled))
        XCTAssertTrue(ProtectionPolicy.shouldDenyAppRemoval(rules: [on], isManualBlockActive: false, appRemoval: .reenabledAutomatically))
        XCTAssertFalse(ProtectionPolicy.shouldDenyAppRemoval(rules: [off], isManualBlockActive: false, appRemoval: .enabled))
        XCTAssertFalse(ProtectionPolicy.shouldDenyAppRemoval(rules: [], isManualBlockActive: false, appRemoval: .enabled))
    }

    func testDenyAppRemovalOffOnlyWhenDisabledOnPurpose() {
        XCTAssertFalse(ProtectionPolicy.shouldDenyAppRemoval(rules: [on], isManualBlockActive: true, appRemoval: .disabled))
        // Vale anche se il riallineamento non è stato salvato.
        XCTAssertTrue(ProtectionPolicy.shouldDenyAppRemoval(rules: [on], isManualBlockActive: false, appRemoval: .suspended))
        XCTAssertFalse(ProtectionPolicy.shouldDenyAppRemoval(rules: [off], isManualBlockActive: false, appRemoval: .suspended))
    }

    func testAutomaticDateAndTimeIgnoresThePreference() {
        XCTAssertTrue(ProtectionPolicy.shouldRequireAutomaticDateAndTime(rules: [on], isManualBlockActive: false))
        XCTAssertTrue(ProtectionPolicy.shouldRequireAutomaticDateAndTime(rules: [], isManualBlockActive: true))
        XCTAssertFalse(ProtectionPolicy.shouldRequireAutomaticDateAndTime(rules: [off], isManualBlockActive: false))
    }

    func testStateDefaultsAndRoundTrip() throws {
        var state = ProtectionState()
        XCTAssertEqual(state.appRemoval, .enabled)
        XCTAssertEqual(state.attempts, PINAttemptPolicy())
        XCTAssertTrue(state.pending.items.isEmpty)

        state.appRemoval = .suspended
        state.attempts.registerFailure(at: date(2026, 11, 2, 10))
        state.pending.enqueue(.disableManualBlock, at: date(2026, 11, 2, 10))
        let decoded = try JSONDecoder().decode(ProtectionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}

final class AppRemovalProtectionTests: XCTestCase {
    func testOnOrOff() {
        XCTAssertTrue(AppRemovalProtection.enabled.isOn)
        XCTAssertTrue(AppRemovalProtection.reenabledAutomatically.isOn)
        XCTAssertFalse(AppRemovalProtection.suspended.isOn)
        XCTAssertFalse(AppRemovalProtection.disabled.isOn)
    }

    func testTurningOffWithoutWaitIsTemporary() {
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .enabled, enabled: false), .suspended)
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .reenabledAutomatically, enabled: false), .suspended)
    }

    func testTurningOnByHandAlwaysGivesPlainEnabled() {
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .suspended, enabled: true), .enabled)
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .disabled, enabled: true), .enabled)
    }

    func testRepeatingTheCurrentValueChangesNothing() {
        // Spegnere di nuovo non deve rendere temporanea una disattivazione confermata col PIN.
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .disabled, enabled: false), .disabled)
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .suspended, enabled: false), .suspended)
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .enabled, enabled: true), .enabled)
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: .reenabledAutomatically, enabled: true), .reenabledAutomatically)
    }

    func testSuspendedComesBackWithTheFirstRestriction() {
        XCTAssertEqual(ProtectionPolicy.reconciled(.suspended, hasActiveRestrictions: false), .suspended)
        XCTAssertEqual(ProtectionPolicy.reconciled(.suspended, hasActiveRestrictions: true), .reenabledAutomatically)
    }

    func testDisabledNeverComesBackByItself() {
        XCTAssertEqual(ProtectionPolicy.reconciled(.disabled, hasActiveRestrictions: true), .disabled)
        XCTAssertEqual(ProtectionPolicy.reconciled(.disabled, hasActiveRestrictions: false), .disabled)
    }

    func testOtherStatesDoNotChange() {
        for active in [true, false] {
            XCTAssertEqual(ProtectionPolicy.reconciled(.enabled, hasActiveRestrictions: active), .enabled)
            // La nota resta anche quando le restrizioni finiscono: si toglie cambiando l'opzione.
            XCTAssertEqual(ProtectionPolicy.reconciled(.reenabledAutomatically, hasActiveRestrictions: active), .reenabledAutomatically)
        }
    }

    func testTemporaryOffThenRuleThenOffAgainIsTemporaryAgain() {
        let off = ProtectionPolicy.appRemovalWithoutWait(from: .enabled, enabled: false)
        let back = ProtectionPolicy.reconciled(off, hasActiveRestrictions: true)
        XCTAssertEqual(back, .reenabledAutomatically)
        XCTAssertEqual(ProtectionPolicy.appRemovalWithoutWait(from: back, enabled: false), .suspended)
    }
}

final class ProtectionStateMigrationTests: XCTestCase {
    /// `protection.json` com'era prima di `AppRemovalProtection`.
    private func legacyJSON(preventsAppRemoval: String) -> Data {
        Data("""
        {
          "attempts": { "failedAttempts": 5, "lockedUntil": 815400000 },
          "pending": { "items": [
            {
              "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
              "change": { "disableManualBlock": {} },
              "cooldown": { "requestedAt": 815300000, "duration": 600 }
            }
          ] }
          \(preventsAppRemoval)
        }
        """.utf8)
    }

    private func decode(_ data: Data) throws -> ProtectionState {
        try JSONDecoder().decode(ProtectionState.self, from: data)
    }

    func testLegacyTrueBecomesEnabled() throws {
        XCTAssertEqual(try decode(legacyJSON(preventsAppRemoval: #", "preventsAppRemoval": true"#)).appRemoval, .enabled)
    }

    func testLegacyFalseStaysOffUntilTurnedOnByHand() throws {
        // Il vecchio file non dice come era stata spenta: vale il significato che aveva, resta spenta.
        let state = try decode(legacyJSON(preventsAppRemoval: #", "preventsAppRemoval": false"#))
        XCTAssertEqual(state.appRemoval, .disabled)
        XCTAssertEqual(ProtectionPolicy.reconciled(state.appRemoval, hasActiveRestrictions: true), .disabled)
    }

    func testMissingKeyMeansEnabled() throws {
        XCTAssertEqual(try decode(legacyJSON(preventsAppRemoval: "")).appRemoval, .enabled)
    }

    func testMigrationKeepsAttemptsAndPendingRequests() throws {
        let state = try decode(legacyJSON(preventsAppRemoval: #", "preventsAppRemoval": false"#))
        XCTAssertEqual(state.attempts.failedAttempts, 5)
        XCTAssertEqual(state.attempts.lockedUntil, Date(timeIntervalSinceReferenceDate: 815_400_000))
        XCTAssertEqual(state.pending.items.count, 1)
        XCTAssertEqual(state.pending.items.first?.change, .disableManualBlock)
        XCTAssertEqual(state.pending.items.first?.cooldown.requestedAt, Date(timeIntervalSinceReferenceDate: 815_300_000))
    }

    func testMigratedStateIsSavedInTheNewFormat() throws {
        let state = try decode(legacyJSON(preventsAppRemoval: #", "preventsAppRemoval": false"#))
        let saved = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNil(object["preventsAppRemoval"])
        XCTAssertEqual(object["appRemoval"] as? String, "disabled")
        XCTAssertEqual(try decode(saved), state)
    }

    func testNewFormatWinsOverLeftoverLegacyKey() throws {
        let json = legacyJSON(preventsAppRemoval: #", "preventsAppRemoval": false, "appRemoval": "suspended""#)
        XCTAssertEqual(try decode(json).appRemoval, .suspended)
    }
}

final class RelaxationNotificationPlanTests: XCTestCase {
    private let start = date(2026, 11, 2, 10)

    private func request(_ change: PendingRelaxation.Change = .disableManualBlock) -> PendingRelaxation {
        PendingRelaxation(change: change, requestedAt: start)
    }

    private func id(_ request: PendingRelaxation, _ kind: RelaxationNotification.Kind) -> String {
        RelaxationNotification.identifier(requestID: request.id, kind: kind)
    }

    // MARK: Date

    func testTenMinuteWait() {
        let notifications = RelaxationNotificationPlan.notifications(for: request(), now: start)
        XCTAssertEqual(notifications.map(\.kind), [.windowOpened, .expiringSoon])
        XCTAssertEqual(notifications.map(\.fireDate), [start.addingTimeInterval(600), start.addingTimeInterval(2100)])
    }

    func testPINResetWait() {
        let notifications = RelaxationNotificationPlan.notifications(for: request(.resetPIN), now: start)
        XCTAssertEqual(notifications.map(\.fireDate), [start.addingTimeInterval(86_400), start.addingTimeInterval(87_900)])
    }

    func testWarningComesFiveMinutesBeforeExpiry() {
        let pending = request()
        XCTAssertEqual(RelaxationNotification.expiryWarning, 300)
        let warning = RelaxationNotificationPlan.notifications(for: pending, now: start).last
        XCTAssertEqual(warning?.fireDate, pending.expiresAt.addingTimeInterval(-300))
    }

    // MARK: Date passate

    func testWindowAlreadyOpenLeavesOnlyTheWarning() {
        let notifications = RelaxationNotificationPlan.notifications(for: request(), now: start.addingTimeInterval(601))
        XCTAssertEqual(notifications.map(\.kind), [.expiringSoon])
    }

    func testLastFiveMinutesLeaveNothing() {
        XCTAssertEqual(RelaxationNotificationPlan.notifications(for: request(), now: start.addingTimeInterval(2101)), [])
    }

    func testExpiredLeavesNothing() {
        XCTAssertEqual(RelaxationNotificationPlan.notifications(for: request(), now: start.addingTimeInterval(9_999)), [])
    }

    func testDateEqualToNowCountsAsPast() {
        let opening = RelaxationNotificationPlan.notifications(for: request(), now: start.addingTimeInterval(600))
        XCTAssertEqual(opening.map(\.kind), [.expiringSoon])
        XCTAssertEqual(RelaxationNotificationPlan.notifications(for: request(), now: start.addingTimeInterval(2100)), [])
    }

    // MARK: Identificativi

    func testIdentifierIsDerivedFromRequestAndKind() {
        let pending = request()
        let identifiers = RelaxationNotificationPlan.notifications(for: pending, now: start).map(\.identifier)
        XCTAssertEqual(identifiers, [id(pending, .windowOpened), id(pending, .expiringSoon)])
        XCTAssertEqual(Set(identifiers).count, 2)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix(RelaxationNotification.identifierPrefix) && $0.contains(pending.id.uuidString) })
    }

    // MARK: Riallineamento

    func testSchedulesWhatIsMissing() {
        let pending = request()
        let result = RelaxationNotificationPlan.reconcile(requests: [pending], scheduled: [id(pending, .windowOpened)], delivered: [], now: start)
        XCTAssertEqual(result.toSchedule.map(\.identifier), [id(pending, .expiringSoon)])
        XCTAssertEqual(result.toCancel, [])
        XCTAssertEqual(result.toRemoveDelivered, [])
    }

    func testAlignedStateDoesNothing() {
        let pending = request()
        let scheduled: Set = [id(pending, .windowOpened), id(pending, .expiringSoon)]
        let result = RelaxationNotificationPlan.reconcile(requests: [pending], scheduled: scheduled, delivered: [], now: start)
        XCTAssertEqual(result, .init(toSchedule: [], toCancel: [], toRemoveDelivered: []))
    }

    func testCancelledRequestLosesItsNotifications() {
        let gone = request()
        let scheduled: Set = [id(gone, .windowOpened), id(gone, .expiringSoon)]
        let delivered: Set = [id(gone, .windowOpened)]
        let result = RelaxationNotificationPlan.reconcile(requests: [], scheduled: scheduled, delivered: delivered, now: start)
        XCTAssertEqual(result.toSchedule, [])
        XCTAssertEqual(result.toCancel, scheduled)
        XCTAssertEqual(result.toRemoveDelivered, delivered)
    }

    func testExpiredRequestCountsAsGone() {
        let expired = request()
        let delivered: Set = [id(expired, .windowOpened), id(expired, .expiringSoon)]
        let result = RelaxationNotificationPlan.reconcile(requests: [expired], scheduled: [], delivered: delivered, now: start.addingTimeInterval(2400))
        XCTAssertEqual(result.toSchedule, [])
        XCTAssertEqual(result.toRemoveDelivered, delivered)
    }

    func testDeliveredNotificationOfLiveRequestStaysAndIsNotRescheduled() {
        let pending = request()
        let now = start.addingTimeInterval(700)
        let result = RelaxationNotificationPlan.reconcile(requests: [pending], scheduled: [id(pending, .expiringSoon)], delivered: [id(pending, .windowOpened)], now: now)
        XCTAssertEqual(result, .init(toSchedule: [], toCancel: [], toRemoveDelivered: []))
    }

    func testScheduledNotificationDueRightNowIsNotCancelled() {
        // iOS può non averla ancora consegnata: cancellarla la perderebbe.
        let pending = request()
        let now = start.addingTimeInterval(600)
        let result = RelaxationNotificationPlan.reconcile(requests: [pending], scheduled: [id(pending, .windowOpened), id(pending, .expiringSoon)], delivered: [], now: now)
        XCTAssertEqual(result.toCancel, [])
        XCTAssertEqual(result.toSchedule, [])
    }

    func testIdentifiersOfOthersAreIgnored() {
        let result = RelaxationNotificationPlan.reconcile(requests: [], scheduled: ["altro"], delivered: ["altro"], now: start)
        XCTAssertEqual(result, .init(toSchedule: [], toCancel: [], toRemoveDelivered: []))
    }

    func testRequestsAreReconciledIndependently() {
        let kept = request(.resetPIN)
        let gone = request()
        let scheduled: Set = [id(kept, .windowOpened), id(kept, .expiringSoon), id(gone, .windowOpened)]
        let result = RelaxationNotificationPlan.reconcile(requests: [kept], scheduled: scheduled, delivered: [], now: start)
        XCTAssertEqual(result.toSchedule, [])
        XCTAssertEqual(result.toCancel, [id(gone, .windowOpened)])
    }
}
