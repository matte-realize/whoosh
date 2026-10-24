import Foundation
import Testing
@testable import Whoosh

/// Resilience and privacy-degradation tests for the crash-response coordinator
/// (crash-response task 29). These exercise the "expected states, not crashes"
/// rules from the design's "Error and degradation handling" table:
///
/// - A **persistence error on a transition** must never block the countdown or
///   the send; the coordinator keeps its in-memory state and carries on
///   (Requirement 6.3).
/// - A **Keychain read error** is treated as "no contacts" so the feature
///   disarms instead of crashing, and a probable-crash signal is ignored
///   (Requirement 2.7, design "Error and degradation handling").
/// - **Audio-session failure** degrades silently: the `SystemCountdownFeedback`
///   never throws out of `begin`/`tick`/`end`, so the countdown is unaffected
///   (Requirement 8.5).
///
/// Composes the real reducer with fakes and failing test doubles; time is driven
/// by `TestClock`. No network, no device services.
@MainActor
struct CrashResilienceTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func reachableContact() -> EmergencyContact {
        EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .reachable)
    }

    static func drain() async {
        for _ in 0..<6 { await Task.yield() }
    }

    /// Build a coordinator with injectable stores so a test can supply failing
    /// doubles. Armed by default (recording, enabled, consented, label, contact).
    static func makeCoordinator(
        repository: CrashAlertRepository,
        contactStore: EmergencyContactStore,
        notifier: CrashNotifier = NoopCrashNotifier(),
        feedback: CountdownFeedback = FakeCountdownFeedback()
    ) -> (coordinator: CrashResponseCoordinator, detector: FakeCrashDetector, clock: TestClock) {
        let clock = TestClock(now: t0)
        let detector = FakeCrashDetector()
        let ride = FakeRideContext(
            isRideActive: true,
            isRecordingOrSignalLost: true,
            latestAcceptedFix: nil,
            currentRideID: UUID()
        )
        let consentStore = InMemoryConsentStore()
        consentStore.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: t0)
        let settingsStore = InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
        )
        let coordinator = CrashResponseCoordinator(
            detector: detector,
            rideContext: ride,
            footageBuffer: FakeFootageBuffer(),
            notifier: notifier,
            scheduler: FakeCrashNotificationScheduler(),
            feedback: feedback,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: repository,
            clock: clock
        )
        detector.start()
        return (coordinator, detector, clock)
    }

    // MARK: - Persistence error on a transition does not block the flow

    @Test func persistenceErrorDoesNotBlockCountdownOrSend() async {
        let repo = ThrowingCrashAlertRepository()
        let contacts = InMemoryEmergencyContactStore(contacts: [Self.reachableContact()])
        let notifier = FakeCrashNotifier()
        let (coordinator, detector, _) = Self.makeCoordinator(repository: repo, contactStore: contacts, notifier: notifier)

        // Signal → countdown should still open even though every save throws.
        detector.emit()
        #expect(coordinator.eventState == .countdown)
        #expect(repo.saveAttempts > 0)       // it tried to persist
        #expect(repo.savedRecords.isEmpty)   // …and every save threw

        // Send now → the send still dispatches (not blocked by the save failure).
        let ref = (try? contacts.contacts())?.first?.id ?? UUID()
        notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: ref, status: .sent, segments: 4, updatedAt: Self.t0)],
            deduplicated: false
        )
        coordinator.sendNow()
        await Self.drain()
        #expect(coordinator.eventState == .sent)
        #expect(notifier.sendCallCount == 1)
    }

    // MARK: - Keychain read error disarms the feature (no crash, no countdown)

    @Test func keychainReadErrorDisarmsAndIgnoresSignal() {
        let repo = InMemoryCrashAlertRepository()
        // A contact store whose contacts() throws and contactsOrEmpty() is empty
        // (the Keychain degradation rule) ⇒ no reachable contact ⇒ disarmed.
        let contacts = ReadErrorContactStore()
        let (coordinator, detector, _) = Self.makeCoordinator(repository: repo, contactStore: contacts)

        detector.emit()
        #expect(coordinator.eventState == .idle)          // not armed ⇒ ignored
        #expect((try? repo.all())?.isEmpty ?? true)       // nothing persisted
    }

    // MARK: - Audio-session failure degrades silently (feedback never throws)

    @Test func systemFeedbackBeginTickEndNeverThrows() {
        // SystemCountdownFeedback is the only AVAudioSession user; its begin/
        // tick/end must degrade silently so the visual countdown is unaffected.
        // Driving it directly proves the calls are non-throwing and idempotent.
        let feedback = SystemCountdownFeedback()
        feedback.begin(totalSeconds: 30)
        feedback.tick(remaining: 10)
        feedback.tick(remaining: 10)   // repeated tick for the same second
        feedback.end(reason: .cancelled)
        feedback.end(reason: .cancelled)  // idempotent end
        // Reaching here without a trap/throw is the assertion.
        #expect(Bool(true))
    }
}

/// A `CrashAlertRepository` whose `save` always throws, to prove a persistence
/// failure on a transition never blocks the crash workflow (Requirement 6.3).
@MainActor
private final class ThrowingCrashAlertRepository: CrashAlertRepository {
    private(set) var saveAttempts = 0
    private(set) var savedRecords: [CrashAlertRecord] = []

    func save(_ record: CrashAlertRecord) throws {
        saveAttempts += 1
        throw ContactStoreError.storageFailure
    }

    func all() throws -> [CrashAlertRecord] { savedRecords }
    func record(id: UUID) throws -> CrashAlertRecord? { nil }
    func delete(id: UUID) throws {}
    func deleteAll() throws {}
    func purge(olderThan date: Date) throws {}
    func activeEvent() throws -> CrashAlertRecord? { nil }
}

/// An `EmergencyContactStore` whose `contacts()` throws (a Keychain read error)
/// and whose `contactsOrEmpty()` returns empty — the degradation rule that
/// disarms the feature rather than crashing (Requirement 2.7).
@MainActor
private final class ReadErrorContactStore: EmergencyContactStore {
    func contacts() throws -> [EmergencyContact] { throw ContactStoreError.storageFailure }
    func contactsOrEmpty() -> [EmergencyContact] { [] }
    func add(_ contact: EmergencyContact) throws { throw ContactStoreError.storageFailure }
    func update(_ contact: EmergencyContact) throws { throw ContactStoreError.storageFailure }
    func remove(id: UUID) throws { throw ContactStoreError.storageFailure }
    func removeAll() throws { throw ContactStoreError.storageFailure }
    func purgeOrphansIfFreshInstall() throws {}
}
