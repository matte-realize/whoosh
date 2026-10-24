import Foundation
import Observation

/// The per-contact send status shown in the test/intro flow (spec Requirement
/// 4.4). `idle` before any send; `sending` while a request is in flight;
/// `status` wraps a backend per-recipient `AttemptStatus`; `failed` is a
/// request-level failure (rate limit, kill switch, trial, offline) with a plain
/// reason carried separately on the row.
enum TestSendStatus: Equatable, Sendable {
    case idle
    case sending
    case status(AttemptStatus)
    case failed
}

/// One row in the test/intro flow: a contact plus its latest send status and a
/// plain-language detail string (icon + text is applied in the view).
struct TestAlertRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let maskedNumber: String
    let verification: ContactVerification
    var sendStatus: TestSendStatus
    /// A plain-language status/reason line for the row (never raw error text).
    var statusDetail: String?
}

/// View model for `TestAlertView`, the intro/test message flow (spec Requirement
/// 4, task 18).
///
/// Lets the rider send an **introduction** to a contact (on add or later) and a
/// **test** message to any contact, using the same backend path, idempotency,
/// and delivery-status mechanism as real alerts — so a successful test is
/// meaningful evidence the real path works (Requirement 4.3). It shows the
/// per-contact progression (`queued` → `sent` → `delivered`, or
/// `undelivered`/`failed`/`rejected` with a plain reason), promotes a contact to
/// `reachable` only after `sent`/`delivered` (Requirement 4.5), and surfaces
/// friendly messages for cooldown, quota, offline, and the Twilio-trial
/// restriction.
///
/// ## Tier 0 (no backend)
/// In the shipping Tier 0 build the notifier is `NoopCrashNotifier`, so no
/// message can be sent automatically. `isMessagingConnected` is then `false` and
/// the view shows an honest "Messaging isn't connected yet — use 'Text them
/// yourself'" state. The composer body is prefilled from the shared
/// `CrashMessageBuilder`'s intro/test templates (`composerBody(for:kind:)`), so
/// the rider can still send the intro from their own phone; the composer never
/// sends without the rider tapping Send.
///
/// UI-framework-free (no SwiftUI import), per the layering table.
@Observable
@MainActor
final class TestAlertViewModel {
    @ObservationIgnored private let notifier: CrashNotifier
    @ObservationIgnored private let contactStore: EmergencyContactStore
    @ObservationIgnored private let connectivity: ConnectivityMonitor
    @ObservationIgnored private let settingsStore: CrashAlertSettingsStore
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let cooldown: TimeInterval

    /// Whether a messaging backend is wired (`false` for the Tier 0 Noop). When
    /// `false` the view offers only the rider-initiated composer fallback.
    let isMessagingConnected: Bool

    /// The rows, one per contact, most-relevant-first (store insertion order).
    private(set) var rows: [TestAlertRow] = []
    /// A screen-level message (offline explanation, general errors).
    var globalMessage: String?

    /// Last send instant per contact id, for the client-mirror cooldown.
    @ObservationIgnored private var lastSendAt: [UUID: Date] = [:]

    init(
        notifier: CrashNotifier,
        contactStore: EmergencyContactStore,
        connectivity: ConnectivityMonitor,
        settingsStore: CrashAlertSettingsStore,
        clock: Clock,
        isMessagingConnected: Bool,
        cooldown: TimeInterval = CrashResponseTuning().testCooldownPerContact
    ) {
        self.notifier = notifier
        self.contactStore = contactStore
        self.connectivity = connectivity
        self.settingsStore = settingsStore
        self.clock = clock
        self.isMessagingConnected = isMessagingConnected
        self.cooldown = cooldown
        reload()
    }

    // MARK: - Loading

    /// Rebuild the rows from the current contacts (call when the screen
    /// reappears). Preserves any in-progress status by id.
    func reload() {
        let previous = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        rows = contactStore.contactsOrEmpty().map { contact in
            TestAlertRow(
                id: contact.id,
                label: contact.label,
                maskedNumber: String(contact.e164.suffix(2)),
                verification: contact.verification,
                sendStatus: previous[contact.id]?.sendStatus ?? .idle,
                statusDetail: previous[contact.id]?.statusDetail
            )
        }
    }

    // MARK: - Intents

    /// Send an introduction message to a contact (Requirement 4.1).
    func sendIntro(to contactID: UUID) async {
        await send(kind: .intro, to: contactID)
    }

    /// Send a test message to a contact (Requirement 4.2).
    func sendTest(to contactID: UUID) async {
        await send(kind: .test, to: contactID)
    }

    // MARK: - Composer fallback (Tier 0 / not connected, Requirement 12.8/12.9)

    /// The recipient numbers to prefill the composer with for `contactID`.
    func composerRecipients(for contactID: UUID) -> [String] {
        guard let contact = contact(contactID) else { return [] }
        return [contact.e164]
    }

    /// The composer body prefilled from the shared builder's intro/test template
    /// (Requirement 12.9). Used only for the rider-initiated fallback; the
    /// composer never sends without the rider tapping Send.
    func composerBody(for contactID: UUID, kind: CrashMessageKind) -> String {
        let label = settingsStore.current().riderLabel ?? "Alex"
        return CrashMessageBuilder.build(
            kind: kind,
            riderLabel: label,
            detectedAt: clock.now(),
            utcOffsetMinutes: 0,
            location: nil,
            delayedSeconds: 0,
            now: clock.now()
        ).text
    }

    // MARK: - Send flow

    private func send(kind: CrashMessageKind, to contactID: UUID) async {
        globalMessage = nil
        guard let contact = contact(contactID) else { return }

        // Tier 0: no backend wired — do not attempt an automatic send.
        guard isMessagingConnected else {
            setDetail(
                contactID,
                status: nil,
                detail: "Messaging isn't connected yet. Use \"Text them yourself\" to send from your own phone."
            )
            return
        }

        // Offline: explain, never queue a test/intro (Requirement 4.7).
        guard connectivity.isOnline else {
            globalMessage = "Testing needs an internet connection. Connect and try again — test messages are never queued."
            return
        }

        // Client-mirror cooldown (Requirement 4.6; backend is authoritative).
        if let last = lastSendAt[contactID],
           clock.now().timeIntervalSince(last) < cooldown {
            let wait = Int((cooldown - clock.now().timeIntervalSince(last)).rounded(.up))
            setDetail(contactID, status: .failed, detail: "Please wait \(wait)s before sending to \(contact.label) again.")
            return
        }

        setStatus(contactID, .sending, detail: nil)

        let request = CrashNotificationRequest(
            crashEventId: UUID(),
            kind: kind,
            riderLabel: settingsStore.current().riderLabel ?? "",
            detectedAt: clock.now(),
            utcOffsetMinutes: 0,
            delayedSeconds: 0,
            location: nil,
            recipients: [CrashNotificationRecipient(recipientRef: contact.id, e164: contact.e164)],
            consentVersion: CrashMessageBuilder.templateVersion,
            templateVersion: CrashMessageBuilder.templateVersion
        )

        lastSendAt[contactID] = clock.now()
        do {
            let result = try await notifier.send(request)
            applyResult(result, kind: kind, contactID: contactID)
        } catch let error as CrashNotifierError {
            applyError(error, contactID: contactID)
        } catch {
            setDetail(contactID, status: .failed, detail: "Couldn't send right now. Please try again.")
        }
    }

    private func applyResult(
        _ result: CrashNotificationResult,
        kind: CrashMessageKind,
        contactID: UUID
    ) {
        guard let recipient = result.recipients.first(where: { $0.recipientRef == contactID }) else {
            setDetail(contactID, status: .failed, detail: "Couldn't send right now. Please try again.")
            return
        }
        setStatus(contactID, .status(recipient.status), detail: detail(for: recipient))
        updateVerification(for: recipient, kind: kind)
    }

    private func applyError(_ error: CrashNotifierError, contactID: UUID) {
        setDetail(contactID, status: .failed, detail: message(for: error))
    }

    // MARK: - Verification promotion (Requirement 4.5)

    private func updateVerification(for recipient: CrashRecipientResult, kind: CrashMessageKind) {
        guard var contact = contact(recipient.recipientRef) else { return }
        let newVerification: ContactVerification?
        switch recipient.status {
        case .sent, .delivered:
            newVerification = .reachable
        case .queued:
            // A queued intro leaves the contact as introSent; a queued test
            // does not change an unverified contact.
            newVerification = (kind == .intro && contact.verification == .unverified) ? .introSent : nil
        case .undelivered, .failed:
            newVerification = recipient.whooshErrorCode == "recipient_opted_out" ? .optedOut : .undeliverable
        case .rejected:
            newVerification = recipient.whooshErrorCode == "recipient_opted_out" ? .optedOut : nil
        }
        guard let verification = newVerification, verification != contact.verification else {
            syncRowVerification(contact.id)
            return
        }
        contact.verification = verification
        contact.lastStatusAt = clock.now()
        try? contactStore.update(contact)
        syncRowVerification(contact.id)
    }

    // MARK: - Plain-language detail mapping

    private func detail(for recipient: CrashRecipientResult) -> String {
        switch recipient.status {
        case .queued, .sent, .delivered:
            return CrashAlertLogDisplay.title(for: recipient.status)
        case .undelivered, .failed, .rejected:
            return reasonText(whooshCode: recipient.whooshErrorCode, status: recipient.status)
        }
    }

    /// Map a per-recipient whoosh error code to a friendly reason.
    private func reasonText(whooshCode: String?, status: AttemptStatus) -> String {
        switch whooshCode {
        case "recipient_opted_out":
            return "This contact opted out (they replied STOP)."
        case "trial_recipient_unverified":
            return "Demo account: this number isn't verified yet, so the provider wouldn't send to it."
        case "recipient_landline":
            return "That number looks like a landline and can't receive texts."
        case "recipient_invalid":
            return "That number can't receive texts."
        case "recipient_unreachable":
            return "Couldn't reach that number right now."
        case "carrier_filtered":
            return "The carrier blocked the message."
        default:
            return "\(CrashAlertLogDisplay.title(for: status)). Please try again or text them yourself."
        }
    }

    /// Map a request-level error to a friendly, honest message.
    private func message(for error: CrashNotifierError) -> String {
        switch error.code {
        case .rateLimited:
            return "You've reached the daily limit for test messages. Please try again later."
        case .serviceDisabled:
            return "Messaging is temporarily unavailable. Text them yourself in the meantime."
        case .noConnection:
            return "Testing needs an internet connection. Connect and try again."
        case .timeout, .serverError, .unauthenticated, .unknown:
            return "Couldn't send right now. Please try again."
        case .invalidRecipient, .invalidLabel, .invalidRequest, .invalidLocation,
             .tooManyRecipients, .payloadTooLarge, .eventTooOld, .idempotencyConflict,
             .unsupportedTemplateVersion, .clientUpgradeRequired:
            return "Couldn't send this message. Check the contact and try again."
        }
    }

    // MARK: - Row mutation helpers

    private func contact(_ id: UUID) -> EmergencyContact? {
        contactStore.contactsOrEmpty().first { $0.id == id }
    }

    private func setStatus(_ id: UUID, _ status: TestSendStatus, detail: String?) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].sendStatus = status
        rows[index].statusDetail = detail
    }

    private func setDetail(_ id: UUID, status: TestSendStatus?, detail: String?) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        if let status { rows[index].sendStatus = status }
        rows[index].statusDetail = detail
    }

    private func syncRowVerification(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              let contact = contact(id) else { return }
        rows[index] = TestAlertRow(
            id: contact.id,
            label: contact.label,
            maskedNumber: String(contact.e164.suffix(2)),
            verification: contact.verification,
            sendStatus: rows[index].sendStatus,
            statusDetail: rows[index].statusDetail
        )
    }
}
