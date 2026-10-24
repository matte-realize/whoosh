import Foundation
import Testing
@testable import Whoosh

/// Tests for `TestAlertViewModel` (crash-response task 18, Requirement 4).
///
/// Cover: per-contact status progression (queued → sent → delivered /
/// undelivered / failed with a plain reason), a contact becoming `reachable`
/// only after `sent`/`delivered`, cooldown and quota messages, the offline
/// explanation (no queuing of test messages), the Twilio-trial restriction
/// message, and the Tier 0 Noop "messaging isn't connected" state whose composer
/// body is prefilled by the shared `CrashMessageBuilder`. All driven by
/// `FakeCrashNotifier` + `TestClock`, no UI.
@MainActor
struct TestAlertViewModelTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func contact(
        _ id: UUID = UUID(),
        label: String = "Mom",
        e164: String = "+16175550123",
        verification: ContactVerification = .unverified
    ) -> EmergencyContact {
        EmergencyContact(id: id, label: label, e164: e164, verification: verification)
    }

    private func makeViewModel(
        contacts: [EmergencyContact],
        online: Bool = true,
        isMessagingConnected: Bool = true,
        sendBehavior: FakeCrashNotifier.Behavior? = nil,
        riderLabel: String = "Alex"
    ) -> (
        vm: TestAlertViewModel,
        notifier: FakeCrashNotifier,
        contactStore: InMemoryEmergencyContactStore,
        clock: TestClock
    ) {
        let clock = TestClock(now: Self.t0)
        let notifier = FakeCrashNotifier()
        if let sendBehavior { notifier.sendBehavior = sendBehavior }
        let contactStore = InMemoryEmergencyContactStore(contacts: contacts)
        let connectivity = FakeConnectivityMonitor(isOnline: online)
        connectivity.start()
        let settingsStore = InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(enabled: true, riderLabel: riderLabel)
        )
        let vm = TestAlertViewModel(
            notifier: notifier,
            contactStore: contactStore,
            connectivity: connectivity,
            settingsStore: settingsStore,
            clock: clock,
            isMessagingConnected: isMessagingConnected
        )
        return (vm, notifier, contactStore, clock)
    }

    private static func result(
        _ ref: UUID,
        _ status: AttemptStatus,
        whoosh: String? = nil,
        provider: Int? = nil
    ) -> CrashRecipientResult {
        CrashRecipientResult(
            recipientRef: ref,
            status: status,
            whooshErrorCode: whoosh,
            providerErrorCode: provider,
            segments: 1,
            updatedAt: t0
        )
    }

    // MARK: - Rows mirror contacts

    @Test func rowsMirrorContacts() {
        let c1 = Self.contact(label: "Mom", e164: "+16175550101")
        let c2 = Self.contact(label: "Dad", e164: "+16175550102")
        let (vm, _, _, _) = makeViewModel(contacts: [c1, c2])
        #expect(vm.rows.map(\.label) == ["Mom", "Dad"])
        #expect(vm.rows.allSatisfy { $0.sendStatus == .idle })
    }

    // MARK: - Test send success → sent → reachable (Requirement 4.4, 4.5)

    @Test func sendTestProgressesToSentAndMarksReachable() async throws {
        let c = Self.contact(verification: .unverified)
        let (vm, notifier, store, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(recipients: [Self.result(c.id, .sent)], deduplicated: false)

        await vm.sendTest(to: c.id)

        let row = try #require(vm.rows.first)
        #expect(row.sendStatus == .status(.sent))
        #expect(notifier.sendRequests.first?.kind == .test)
        // Contact promoted to reachable after sent.
        #expect(try store.contacts().first?.verification == .reachable)
        #expect(row.statusDetail == CrashAlertLogDisplay.title(for: .sent))
    }

    @Test func deliveredAlsoMarksReachable() async throws {
        let c = Self.contact(verification: .unverified)
        let (vm, notifier, store, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(recipients: [Self.result(c.id, .delivered)], deduplicated: false)
        await vm.sendTest(to: c.id)
        #expect(try store.contacts().first?.verification == .reachable)
        #expect(vm.rows.first?.sendStatus == .status(.delivered))
    }

    @Test func queuedDoesNotMarkReachable() async throws {
        let c = Self.contact(verification: .unverified)
        let (vm, notifier, store, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(recipients: [Self.result(c.id, .queued)], deduplicated: false)
        await vm.sendTest(to: c.id)
        #expect(vm.rows.first?.sendStatus == .status(.queued))
        #expect(try store.contacts().first?.verification == .unverified)
    }

    // MARK: - Intro send (Requirement 4.1)

    @Test func sendIntroUsesIntroKindAndMarksIntroSent() async throws {
        let c = Self.contact(verification: .unverified)
        let (vm, notifier, store, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(recipients: [Self.result(c.id, .queued)], deduplicated: false)
        await vm.sendIntro(to: c.id)
        #expect(notifier.sendRequests.first?.kind == .intro)
        // Queued intro leaves the contact introSent (not yet reachable).
        #expect(try store.contacts().first?.verification == .introSent)
    }

    // MARK: - Failure reasons (Requirement 4.4)

    @Test func undeliveredShowsPlainReasonAndMarksUndeliverable() async throws {
        let c = Self.contact(verification: .unverified)
        let (vm, notifier, store, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(
            recipients: [Self.result(c.id, .undelivered, whoosh: "recipient_unreachable")],
            deduplicated: false
        )
        await vm.sendTest(to: c.id)
        let row = try #require(vm.rows.first)
        #expect(row.sendStatus == .status(.undelivered))
        #expect(row.statusDetail?.isEmpty == false)
        #expect(try store.contacts().first?.verification == .undeliverable)
    }

    @Test func optedOutMarksContactOptedOut() async throws {
        let c = Self.contact(verification: .reachable)
        let (vm, notifier, store, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(
            recipients: [Self.result(c.id, .rejected, whoosh: "recipient_opted_out")],
            deduplicated: false
        )
        await vm.sendTest(to: c.id)
        #expect(try store.contacts().first?.verification == .optedOut)
        #expect(vm.rows.first?.statusDetail?.contains("opted out") == true)
    }

    // MARK: - Trial restriction (Requirement 4.8)

    @Test func trialUnverifiedShowsTrialExplanation() async throws {
        let c = Self.contact()
        let (vm, notifier, _, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(
            recipients: [Self.result(c.id, .rejected, whoosh: "trial_recipient_unverified", provider: 21608)],
            deduplicated: false
        )
        await vm.sendTest(to: c.id)
        let row = try #require(vm.rows.first)
        #expect(row.sendStatus == .status(.rejected))
        #expect(row.statusDetail?.lowercased().contains("verif") == true)
    }

    // MARK: - Request-level error (rate limit / quota, Requirement 4.6)

    @Test func rateLimitedShowsQuotaMessage() async throws {
        let c = Self.contact()
        let (vm, notifier, _, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .failure(CrashNotifierError(.rateLimited))
        await vm.sendTest(to: c.id)
        let row = try #require(vm.rows.first)
        #expect(row.sendStatus == .failed)
        #expect(row.statusDetail?.lowercased().contains("limit") == true)
    }

    @Test func serviceDisabledShowsNotConnectedAfterwards() async throws {
        let c = Self.contact()
        let (vm, notifier, _, _) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .failure(CrashNotifierError(.serviceDisabled))
        await vm.sendTest(to: c.id)
        let row = try #require(vm.rows.first)
        #expect(row.sendStatus == .failed)
        #expect(row.statusDetail?.isEmpty == false)
    }

    // MARK: - Cooldown (Requirement 4.6, client mirror 60 s)

    @Test func secondSendWithinCooldownIsBlockedWithMessage() async throws {
        let c = Self.contact()
        let (vm, notifier, _, clock) = makeViewModel(contacts: [c])
        notifier.sendBehavior = .success(recipients: [Self.result(c.id, .sent)], deduplicated: false)
        await vm.sendTest(to: c.id)
        #expect(notifier.sendCallCount == 1)

        // Immediately retry: blocked by the 60 s cooldown.
        await vm.sendTest(to: c.id)
        #expect(notifier.sendCallCount == 1) // not sent again
        #expect(vm.rows.first?.statusDetail?.lowercased().contains("wait") == true)

        // After the cooldown passes, a send is allowed again.
        clock.advance(by: 61)
        await vm.sendTest(to: c.id)
        #expect(notifier.sendCallCount == 2)
    }

    // MARK: - Offline (Requirement 4.7 — explain, never queue)

    @Test func offlineDoesNotSendAndExplains() async throws {
        let c = Self.contact()
        let (vm, notifier, _, _) = makeViewModel(contacts: [c], online: false)
        await vm.sendTest(to: c.id)
        #expect(notifier.sendCallCount == 0) // never queued
        let row = try #require(vm.rows.first)
        #expect(row.sendStatus == .idle || row.sendStatus == .failed)
        #expect(vm.globalMessage?.lowercased().contains("connection") == true)
    }

    // MARK: - Not connected (Tier 0 Noop) → composer fallback prefilled

    @Test func notConnectedExposesComposerBodyFromBuilder() throws {
        let c = Self.contact()
        let (vm, notifier, _, _) = makeViewModel(
            contacts: [c],
            isMessagingConnected: false
        )
        #expect(vm.isMessagingConnected == false)
        // No automatic send is attempted when not connected.
        #expect(notifier.sendCallCount == 0)

        // The composer body matches the builder's intro/test templates.
        let introBody = vm.composerBody(for: c.id, kind: .intro)
        let testBody = vm.composerBody(for: c.id, kind: .test)
        let expectedIntro = CrashMessageBuilder.build(
            kind: .intro, riderLabel: "Alex", detectedAt: Self.t0,
            utcOffsetMinutes: 0, location: nil, delayedSeconds: 0, now: Self.t0
        ).text
        #expect(introBody == expectedIntro)
        #expect(testBody.contains("WHOOSH TEST"))
        #expect(vm.composerRecipients(for: c.id) == [c.e164])
    }

    @Test func notConnectedSendDoesNotCallNotifier() async {
        let c = Self.contact()
        let (vm, notifier, _, _) = makeViewModel(contacts: [c], isMessagingConnected: false)
        await vm.sendTest(to: c.id)
        await vm.sendIntro(to: c.id)
        #expect(notifier.sendCallCount == 0)
    }
}
