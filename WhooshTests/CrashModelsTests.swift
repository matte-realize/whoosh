import Foundation
import Testing
@testable import Whoosh

/// Model-level tests for the crash-response domain types (spec task 1):
/// Codable round-trips, `CrashResponseTuning` clamps, and the derived
/// `CountdownState.remaining(at:)` computed from an absolute deadline.
struct CrashModelsTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    // MARK: - CrashResponseTuning defaults and ranges

    @Test func tuningDefaultsMatchSpec() {
        let tuning = CrashResponseTuning()
        #expect(tuning.countdownSeconds == 30)
        #expect(tuning.suppressionWindow == 120)
        #expect(tuning.maxAutomaticAlertsPerRide == 1)
        #expect(tuning.maxContacts == 3)
        #expect(tuning.staleLimit == 30 * 60)
        #expect(tuning.maxLocationAge == 30 * 60)
        #expect(tuning.currentFixMaxAge == 10)
        #expect(tuning.requestTimeout == 10)
        #expect(tuning.localRecordRetention == 90 * 24 * 60 * 60)
        #expect(tuning.maxRiderLabelLength == 20)
        #expect(tuning.testCooldownPerContact == 60)
        #expect(tuning.maxRetryAttempts == 6)
        #expect(tuning.retryBackoff == [5, 15, 30, 60])
        #expect(tuning.messageSegmentCap == 4)
        #expect(tuning.messageCharacterCap == 612)
    }

    @Test(arguments: [
        (14.0, 15.0),
        (15.0, 15.0),
        (30.0, 30.0),
        (45.0, 45.0),
        (60.0, 60.0),
        (61.0, 60.0),
        (0.0, 15.0),
        (1000.0, 60.0),
    ])
    func countdownClampsToRange(requested: TimeInterval, expected: TimeInterval) {
        let tuning = CrashResponseTuning()
        #expect(tuning.clampCountdown(requested) == expected)
    }

    @Test func tuningIsCodableRoundTrip() throws {
        let tuning = CrashResponseTuning()
        let data = try JSONEncoder().encode(tuning)
        let decoded = try JSONDecoder().decode(CrashResponseTuning.self, from: data)
        #expect(decoded == tuning)
    }

    // MARK: - CountdownState derived remaining

    @Test func countdownRemainingIsDerivedFromAbsoluteDeadline() {
        let start = Self.epoch
        let deadline = start.addingTimeInterval(30)
        let state = CountdownState(deadline: deadline, totalSeconds: 30)

        #expect(state.remaining(at: start) == 30)
        #expect(state.remaining(at: start.addingTimeInterval(10)) == 20)
        #expect(state.remaining(at: deadline) == 0)
    }

    @Test func countdownRemainingNeverGoesNegative() {
        let deadline = Self.epoch.addingTimeInterval(30)
        let state = CountdownState(deadline: deadline, totalSeconds: 30)
        #expect(state.remaining(at: deadline.addingTimeInterval(5)) == 0)
    }

    @Test func countdownIsExpiredAtOrAfterDeadline() {
        let deadline = Self.epoch.addingTimeInterval(30)
        let state = CountdownState(deadline: deadline, totalSeconds: 30)
        #expect(state.isExpired(at: Self.epoch.addingTimeInterval(29)) == false)
        #expect(state.isExpired(at: deadline) == true)
        #expect(state.isExpired(at: deadline.addingTimeInterval(1)) == true)
    }

    @Test func countdownStateCodableRoundTrip() throws {
        let state = CountdownState(deadline: Self.epoch.addingTimeInterval(45), totalSeconds: 45)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CountdownState.self, from: data)
        #expect(decoded == state)
    }

    // MARK: - LocationSnapshot

    @Test func locationSnapshotCurrentAgeIsDerived() {
        let fixTime = Self.epoch
        let snapshot = LocationSnapshot(
            latitude: 42.36012,
            longitude: -71.05888,
            horizontalAccuracy: 12,
            fixTime: fixTime,
            status: .current
        )
        #expect(snapshot.age(at: fixTime.addingTimeInterval(45)) == 45)
    }

    @Test func locationSnapshotUnavailableHasNoCoordinates() {
        let snapshot = LocationSnapshot.unavailable
        #expect(snapshot.status == .unavailable)
        #expect(snapshot.latitude == nil)
        #expect(snapshot.longitude == nil)
        #expect(snapshot.age(at: Self.epoch) == nil)
    }

    @Test func locationSnapshotCodableRoundTrip() throws {
        let snapshot = LocationSnapshot(
            latitude: -42.36012,
            longitude: -171.05888,
            horizontalAccuracy: 30,
            fixTime: Self.epoch,
            status: .lastKnown
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LocationSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    // MARK: - EmergencyContact

    @Test func emergencyContactEditingNumberResetsVerification() {
        var contact = EmergencyContact(
            id: UUID(),
            label: "Mom",
            e164: "+16175550123",
            verification: .reachable,
            lastStatusAt: Self.epoch
        )
        contact = contact.changingNumber(to: "+16175550124")
        #expect(contact.e164 == "+16175550124")
        #expect(contact.verification == .unverified)
    }

    @Test func emergencyContactChangingLabelKeepsVerification() {
        let contact = EmergencyContact(
            id: UUID(),
            label: "Mom",
            e164: "+16175550123",
            verification: .reachable,
            lastStatusAt: nil
        )
        let renamed = contact.changingLabel(to: "Mother")
        #expect(renamed.label == "Mother")
        #expect(renamed.verification == .reachable)
    }

    @Test func emergencyContactCodableRoundTrip() throws {
        let contact = EmergencyContact(
            id: UUID(),
            label: "Alex",
            e164: "+16175550123",
            verification: .introSent,
            lastStatusAt: Self.epoch
        )
        let data = try JSONEncoder().encode(contact)
        let decoded = try JSONDecoder().decode(EmergencyContact.self, from: data)
        #expect(decoded == contact)
    }

    // MARK: - ConsentRecord

    @Test func consentRecordCodableRoundTrip() throws {
        let record = ConsentRecord(version: 1, acceptedAt: Self.epoch, acknowledgedNotGuaranteed: true)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ConsentRecord.self, from: data)
        #expect(decoded == record)
    }

    @Test func consentIsCurrentForMinimumVersion() {
        let record = ConsentRecord(version: 2, acceptedAt: Self.epoch, acknowledgedNotGuaranteed: true)
        #expect(record.isCurrent(minimumVersion: 1) == true)
        #expect(record.isCurrent(minimumVersion: 2) == true)
        #expect(record.isCurrent(minimumVersion: 3) == false)
    }

    @Test func consentNotCurrentWhenNotAcknowledged() {
        let record = ConsentRecord(version: 1, acceptedAt: Self.epoch, acknowledgedNotGuaranteed: false)
        #expect(record.isCurrent(minimumVersion: 1) == false)
    }

    // MARK: - CrashAlertSettings

    @Test func crashAlertSettingsDefaultsAreOff() {
        let settings = CrashAlertSettings()
        #expect(settings.enabled == false)
        #expect(settings.riderLabel == nil)
        #expect(settings.countdownSeconds == nil)
        #expect(settings.developerToolsEnabled == false)
    }

    @Test func crashAlertSettingsCodableRoundTrip() throws {
        let settings = CrashAlertSettings(
            enabled: true,
            riderLabel: "Alex",
            countdownSeconds: 45,
            developerToolsEnabled: true,
            freshInstallMarker: true
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CrashAlertSettings.self, from: data)
        #expect(decoded == settings)
    }

    // MARK: - CrashMessageKind

    @Test func crashMessageKindRawValuesMatchContract() {
        #expect(CrashMessageKind.crashAlert.rawValue == "crash_alert")
        #expect(CrashMessageKind.drill.rawValue == "drill")
        #expect(CrashMessageKind.test.rawValue == "test")
        #expect(CrashMessageKind.intro.rawValue == "intro")
        #expect(CrashMessageKind.allClear.rawValue == "all_clear")
    }

    @Test func crashMessageKindCodableRoundTrip() throws {
        for kind in CrashMessageKind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(CrashMessageKind.self, from: data)
            #expect(decoded == kind)
        }
    }

    // MARK: - CrashEvent + state

    @Test func crashEventCodableRoundTrip() throws {
        let event = CrashEvent(
            id: UUID(),
            detectedAt: Self.epoch,
            utcOffsetMinutes: -240,
            isDrill: false,
            source: "simulator",
            confidence: 0.9,
            rideId: UUID(),
            state: .countdown,
            countdown: CountdownState(deadline: Self.epoch.addingTimeInterval(30), totalSeconds: 30),
            suppressedUntil: nil,
            locationAtDetection: .unavailable,
            footageRef: nil,
            outcome: nil
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CrashEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test func crashEventStateActiveClassification() {
        let active: [CrashEventState] = [
            .detected, .countdown, .sending, .queuedOffline, .failed, .fallbackPrompted, .recoveryPrompted,
        ]
        for state in active {
            #expect(state.isActive, "\(state) should be active")
        }
        let resting: [CrashEventState] = [.idle, .cancelled, .sent, .stale]
        for state in resting {
            #expect(!state.isActive, "\(state) should not be active")
        }
    }

    @Test func crashEventStateCodableRoundTrip() throws {
        for state in CrashEventState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(CrashEventState.self, from: data)
            #expect(decoded == state)
        }
    }

    @Test func cancelReasonCodableRoundTrip() throws {
        for reason in CrashCancelReason.allCases {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(CrashCancelReason.self, from: data)
            #expect(decoded == reason)
        }
    }

    @Test func countdownOutcomeCodableRoundTrip() throws {
        for outcome in CountdownOutcome.allCases {
            let data = try JSONEncoder().encode(outcome)
            let decoded = try JSONDecoder().decode(CountdownOutcome.self, from: data)
            #expect(decoded == outcome)
        }
    }

    // MARK: - AlertAttempt + CrashAlertRecord

    @Test func alertAttemptMaskedNumberIsLastTwoDigits() {
        let attempt = AlertAttempt(
            recipientRef: UUID(),
            labelSnapshot: "Mom",
            maskedNumber: "23",
            kind: .crashAlert,
            status: .queued,
            whooshErrorCode: nil,
            providerErrorCode: nil,
            attemptedAt: Self.epoch,
            updatedAt: Self.epoch
        )
        #expect(attempt.maskedNumber.count == 2)
    }

    @Test func alertAttemptCodableRoundTrip() throws {
        let attempt = AlertAttempt(
            recipientRef: UUID(),
            labelSnapshot: "Alex",
            maskedNumber: "23",
            kind: .crashAlert,
            status: .delivered,
            whooshErrorCode: nil,
            providerErrorCode: 21610,
            attemptedAt: Self.epoch,
            updatedAt: Self.epoch.addingTimeInterval(10)
        )
        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(AlertAttempt.self, from: data)
        #expect(decoded == attempt)
    }

    @Test func attemptStatusOrdering() {
        #expect(AttemptStatus.queued.rank < AttemptStatus.sent.rank)
        #expect(AttemptStatus.sent.rank < AttemptStatus.delivered.rank)
        #expect(AttemptStatus.delivered.isTerminal)
        #expect(AttemptStatus.undelivered.isTerminal)
        #expect(AttemptStatus.failed.isTerminal)
        #expect(AttemptStatus.rejected.isTerminal)
        #expect(!AttemptStatus.queued.isTerminal)
        #expect(!AttemptStatus.sent.isTerminal)
    }

    @Test func crashAlertRecordCodableRoundTrip() throws {
        let event = CrashEvent(
            id: UUID(),
            detectedAt: Self.epoch,
            utcOffsetMinutes: -240,
            isDrill: false,
            source: "simulator",
            confidence: 1.0,
            rideId: nil,
            state: .sent,
            countdown: nil,
            suppressedUntil: Self.epoch.addingTimeInterval(120),
            locationAtDetection: .unavailable,
            footageRef: nil,
            outcome: .expired
        )
        let record = CrashAlertRecord(
            event: event,
            locationAtSend: nil,
            templateVersion: 1,
            renderedText: "WHOOSH ALERT...",
            attempts: [],
            createdAt: Self.epoch,
            updatedAt: Self.epoch
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CrashAlertRecord.self, from: data)
        #expect(decoded == record)
    }
}
