import Foundation
import Observation

/// The banner the status/takeover UI should surface for the current event
/// (spec Requirement 12.1–12.3, design "Fallback matrix"). Mapped from the
/// machine state; icon + text, never colour alone (Requirement 11.7).
enum CrashBannerKind: Equatable, Sendable {
    /// No banner to show.
    case none
    /// Offline queue: "Alert not sent yet" + "I'm OK — cancel alert" + composer.
    case queuedOffline
    /// The stale limit passed: never auto-sent; composer + discard.
    case stale
    /// A send failed; the composer fallback is offered.
    case failed
    /// The app relaunched past a countdown deadline; Send now / I'm OK.
    case recoveryPrompted
}

/// The display projection of one reachable recipient for the countdown/status
/// UI (spec design "Countdown screen", Requirement 11.6). Read-only; carries the
/// masked number only, never the full E.164 (Requirement 11.3).
struct CrashRecipientDisplay: Equatable, Sendable, Identifiable {
    var id: UUID { recipientRef }
    let recipientRef: UUID
    let label: String
    /// Last two digits of the number, for audit display only.
    let maskedNumber: String
    let status: AttemptStatus?

    init(recipientRef: UUID, label: String, maskedNumber: String, status: AttemptStatus?) {
        self.recipientRef = recipientRef
        self.label = label
        self.maskedNumber = maskedNumber
        self.status = status
    }
}

/// The crash-response coordinator: an `@Observable`, main-actor object that
/// **composes** the pure `CrashStateMachine` reducer with every injected seam
/// (detector, ride context, footage buffer, notifier, scheduler, countdown
/// feedback, connectivity, stores, repository), the `Clock`, and an injectable
/// id factory (crash-response tasks 12–14).
///
/// It never reimplements transition logic: it feeds `CrashReducerEvent`s to the
/// reducer, then **executes the returned effects-as-data** (start feedback,
/// schedule a timer, call the notifier, persist a record, …). Read-only
/// published state drives the views.
///
/// ## Honesty / safety invariants (privacy steering)
/// - This layer references **no** call/dial API: Whoosh never auto-calls; a
///   "Call 911" control exists only as a rider-tapped button elsewhere.
/// - Whoosh cannot guarantee detection or delivery; nothing here claims it does.
/// - The notifier request carries no footage and no free text beyond the
///   sanitized rider label.
@Observable
@MainActor
final class CrashResponseCoordinator {
    // MARK: Injected seams and policy

    @ObservationIgnored private let detector: CrashDetector
    @ObservationIgnored private let rideContext: RideContext
    @ObservationIgnored private let footageBuffer: FootageBuffer
    @ObservationIgnored private let notifier: CrashNotifier
    @ObservationIgnored private let scheduler: CrashNotificationScheduler
    @ObservationIgnored private let feedback: CountdownFeedback
    @ObservationIgnored private let connectivity: ConnectivityMonitor
    @ObservationIgnored private let contactStore: EmergencyContactStore
    @ObservationIgnored private let consentStore: ConsentStore
    @ObservationIgnored private let settingsStore: CrashAlertSettingsStore
    @ObservationIgnored private let repository: CrashAlertRepository
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let tuning: CrashResponseTuning
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private let minimumConsentVersion: Int

    // MARK: Observable, read-only state for views

    /// The reducer's full state (read-only to the UI).
    private(set) var machine: CrashMachineState = .initial
    /// The banner to surface for the current event.
    private(set) var bannerKind: CrashBannerKind = .none
    /// The reachable recipients for the current event with their latest status.
    private(set) var recipients: [CrashRecipientDisplay] = []
    /// Whether the full-screen countdown takeover should be presented.
    private(set) var isTakeoverPresented = false
    /// Whether the composer fallback is being offered.
    private(set) var isComposerFallbackOffered = false
    /// Whether the relaunch recovery prompt is being shown.
    private(set) var isRecoveryPromptPresented = false

    /// The current event's state (convenience projection).
    var eventState: CrashEventState { machine.eventState }

    /// Whole seconds remaining in the countdown at the clock's `now`, or `nil`
    /// when not counting down. Absolute-deadline based (Requirement 6.8).
    var remainingSeconds: Int? {
        guard machine.eventState == .countdown, let deadline = machine.deadline else { return nil }
        return Int(max(0, deadline.timeIntervalSince(clock.now())).rounded(.up))
    }

    /// Whether the current event is a drill (the "Simulate crash" demo path).
    /// The countdown/status screens hide the manual "Call 911" control for
    /// drills (Requirement 17.3) and label the UI as a demo.
    var isDrill: Bool { machine.isDrill }

    /// The whole-seconds length the active countdown was created with (the
    /// clamped total), used by the takeover to drive the announcement cadence.
    var totalCountdownSeconds: Int? {
        machine.totalCountdownSeconds.map { Int($0.rounded()) }
    }

    /// The rider's chosen label (first name or nickname) for the countdown
    /// sentence and status copy; empty when none is set.
    var riderLabel: String { settingsStore.current().riderLabel ?? "" }

    /// A rider-initiated composer-fallback payload (spec Requirement 12.1/12.9):
    /// the reachable recipients' full numbers and the exact message built by the
    /// shared `CrashMessageBuilder`, pre-filled with the current delay wording.
    ///
    /// This is the only place the coordinator surfaces full E.164 numbers, and
    /// only for the native composer the rider explicitly opens — it never sends
    /// automatically. Returns `nil` when there is no reachable contact.
    struct ComposerFallbackPayload: Equatable, Sendable {
        /// Full E.164 recipient numbers to pre-fill (composer only).
        let recipients: [String]
        /// The message body, rendered by the shared builder with delay wording.
        let body: String
    }

    /// Build the composer-fallback payload for the current event at `now`.
    /// Rider-initiated only; the composer never sends without the rider tapping
    /// Send (iOS owns that interaction).
    func composerFallback() -> ComposerFallbackPayload? {
        let reachable = reachableContacts()
        guard !reachable.isEmpty else { return nil }
        let now = clock.now()
        let message = CrashMessageBuilder.build(
            kind: currentKind,
            riderLabel: settingsStore.current().riderLabel ?? "",
            detectedAt: currentEvent?.detectedAt ?? now,
            utcOffsetMinutes: currentEvent?.utcOffsetMinutes ?? utcOffsetMinutes(at: now),
            location: (currentKind == .crashAlert || currentKind == .drill) ? locationForSend(at: now) : nil,
            delayedSeconds: TimeInterval(delayedSeconds(at: now)),
            now: now
        )
        return ComposerFallbackPayload(
            recipients: reachable.map(\.e164),
            body: message.text
        )
    }

    // MARK: Private per-event bookkeeping (not persisted via the reducer)

    /// The in-progress crash event being assembled into the record.
    @ObservationIgnored private var currentEvent: CrashEvent?
    /// The newer location snapshot captured at send time, when one existed.
    @ObservationIgnored private var locationAtSend: LocationSnapshot?
    /// The rendered message text for the current event.
    @ObservationIgnored private var renderedText: String = ""
    /// Per-recipient attempts, keyed by recipient ref, for the record.
    @ObservationIgnored private var attempts: [UUID: AlertAttempt] = [:]
    /// The reachable recipients captured for the current event's send.
    @ObservationIgnored private var sendRecipients: [CrashNotificationRecipient] = []
    /// The display labels/masked numbers captured for the current event.
    @ObservationIgnored private var recipientLabels: [UUID: (label: String, masked: String)] = [:]
    /// The consent version in force for the current event.
    @ObservationIgnored private var consentVersionForEvent: Int = 0
    /// The message kind for the current event (`crash_alert` or `drill`).
    @ObservationIgnored private var currentKind: CrashMessageKind = .crashAlert

    /// The one active timer (countdown deadline or retry backoff).
    @ObservationIgnored private var deadlineTimer: Cancellable?
    @ObservationIgnored private var retryTimer: Cancellable?
    /// The per-second feedback tick timer.
    @ObservationIgnored private var tickTimer: Cancellable?
    /// The status-poll timer.
    @ObservationIgnored private var pollTimer: Cancellable?
    /// Whether the app is foregrounded (polling only runs foregrounded).
    @ObservationIgnored private var isForeground = true

    init(
        detector: CrashDetector,
        rideContext: RideContext,
        footageBuffer: FootageBuffer,
        notifier: CrashNotifier,
        scheduler: CrashNotificationScheduler,
        feedback: CountdownFeedback,
        connectivity: ConnectivityMonitor,
        contactStore: EmergencyContactStore,
        consentStore: ConsentStore,
        settingsStore: CrashAlertSettingsStore,
        repository: CrashAlertRepository,
        clock: Clock,
        tuning: CrashResponseTuning = CrashResponseTuning(),
        minimumConsentVersion: Int = 1,
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.detector = detector
        self.rideContext = rideContext
        self.footageBuffer = footageBuffer
        self.notifier = notifier
        self.scheduler = scheduler
        self.feedback = feedback
        self.connectivity = connectivity
        self.contactStore = contactStore
        self.consentStore = consentStore
        self.settingsStore = settingsStore
        self.repository = repository
        self.clock = clock
        self.tuning = tuning
        self.minimumConsentVersion = minimumConsentVersion
        self.makeID = makeID

        wireDetector()
        wireConnectivity()
    }

    // MARK: - Wiring

    private func wireDetector() {
        detector.onSignal = { [weak self] signal in
            self?.handleSignal(signal)
        }
    }

    private func wireConnectivity() {
        connectivity.onChange = { [weak self] online in
            guard let self, online else { return }
            // A retry trigger only; real request outcomes remain ground truth.
            self.dispatch(.retryTrigger)
        }
    }

    // MARK: - Foreground / background (polling gate, Requirement 11.4)

    /// Note the app entering the foreground: resume status polling if an event
    /// is awaiting terminal statuses.
    func enterForeground() {
        isForeground = true
        if machine.eventState == .sent, hasPendingStatuses() {
            startPolling()
        }
    }

    /// Note the app leaving the foreground: pause status polling (foreground
    /// only, Requirement 11.4). The absolute deadline stays authoritative.
    func enterBackground() {
        isForeground = false
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Detector signal

    private func handleSignal(_ signal: CrashSignal) {
        dispatch(.detectorSignal(isDrill: signal.isDrill), signal: signal)
    }

    // MARK: - Rider intents (forwarded to the reducer)

    /// The rider tapped "I'm OK — Cancel".
    func riderCancel() { dispatch(.riderCancel) }

    /// The rider tapped "Send now".
    func sendNow() { dispatch(.sendNow) }

    /// Consent was revoked while an event was active.
    func consentRevoked() { dispatch(.consentRevoked) }

    /// The rider tapped "Tell contacts I'm OK" after a sent alert (stretch).
    func tellContactsImOK() { dispatch(.tellContactsImOK) }

    /// The composer fallback was opened / dismissed / discarded.
    func composerAction() { dispatch(.composerAction) }

    // MARK: - Relaunch recovery (task 14)

    /// Reconcile a persisted active event on launch. Rebuilds the in-memory
    /// state from the repository's active record and feeds the reducer a
    /// `relaunch` event so it resumes, prompts, or marks stale as specified
    /// (Requirement 13.5). Safe to call with no active event.
    func reconcileOnLaunch() {
        guard let record = try? repository.activeEvent() else { return }
        restoreState(from: record)
        dispatch(.relaunch)
    }

    // MARK: - The reduce → apply loop

    /// Reduce one event and execute its effects. `signal` is supplied only for a
    /// `detectorSignal` so evidence capture can read the detector's values.
    private func dispatch(_ event: CrashReducerEvent, signal: CrashSignal? = nil) {
        let context = makeContext()
        let reduction = CrashStateMachine.reduce(machine, event, context)
        machine = reduction.state
        for effect in reduction.effects {
            apply(effect, context: context, signal: signal)
        }
        refreshDisplay()
    }

    /// Build the ambient context for a reduction step from the current app
    /// state and seams.
    private func makeContext() -> CrashReducerContext {
        CrashReducerContext(
            now: clock.now(),
            tuning: tuning,
            armed: isArmed(),
            online: connectivity.isOnline,
            consentCurrent: isConsentCurrent(),
            newEventId: makeID()
        )
    }

    private func isArmed() -> Bool {
        let settings = settingsStore.current()
        let reachable = reachableContacts().count
        return CrashArming.isArmed(
            CrashArming.Input(
                rideState: rideState(),
                enabled: settings.enabled,
                consentCurrent: isConsentCurrent(),
                riderLabelPresent: (settings.riderLabel?.isEmpty == false),
                reachableContactCount: reachable
            )
        )
    }

    private func isConsentCurrent() -> Bool {
        consentStore.current()?.isCurrent(minimumVersion: minimumConsentVersion) ?? false
    }

    private func rideState() -> RideState {
        if rideContext.isRecordingOrSignalLost { return .recording }
        if rideContext.isRideActive { return .paused }
        return .idle
    }

    private func reachableContacts() -> [EmergencyContact] {
        contactStore.contactsOrEmpty().filter { $0.verification == .reachable }
    }

    // MARK: - Effect execution

    private func apply(_ effect: CrashEffect, context: CrashReducerContext, signal: CrashSignal?) {
        switch effect {
        case let .captureEvidence(eventId):
            captureEvidence(eventId: eventId, context: context, signal: signal)

        case let .startCountdownFeedback(totalSeconds):
            startFeedback(totalSeconds: totalSeconds)

        case .stopCountdownFeedback:
            endFeedback(for: machine.outcome)

        case let .scheduleBackupNotification(deadline):
            scheduler.scheduleDeadlinePrompt(eventId: machine.eventId ?? makeID(), at: deadline)
            armDeadlineTimer(deadline: deadline)

        case .cancelBackupNotification:
            cancelDeadlineTimer()
            if let id = machine.eventId { scheduler.cancel(eventId: id) }

        case .presentTakeover:
            isTakeoverPresented = true

        case .keepScreenAwake:
            // Screen-awake is a view-layer concern (idle timer); the coordinator
            // only records the intent via `isTakeoverPresented`.
            break

        case let .dispatchSend(eventId, isRetry):
            performDispatch(eventId: eventId, isRetry: isRetry, context: context)

        case let .scheduleRetry(delay):
            armRetryTimer(delay: delay)

        case let .startStatusPolling(eventId):
            beginStatusPolling(eventId: eventId)

        case .presentComposerFallback:
            isComposerFallbackOffered = true

        case .presentOfflineBanner:
            // Banner is derived in refreshDisplay; also re-arm the retry trigger
            // so a queued alert retries on the backoff schedule.
            armRetryTimer(delay: tuning.backoffDelay(forAttempt: 1))

        case .presentStaleNotice:
            cancelAllTimers()

        case .localNotSentNotice:
            if let id = machine.eventId { scheduler.scheduleNotSentNotice(eventId: id) }

        case let .sendAllClear(eventId):
            performAllClear(eventId: eventId)

        case let .presentRecoveryPrompt(eventId):
            _ = eventId
            isRecoveryPromptPresented = true

        case .updateAttempts:
            // Attempts are merged in `applyStatus`; persistence follows.
            break

        case .persist:
            persistRecord()

        case .logIgnored:
            // Ignored-signal reasons are audit-only; no side effect needed here.
            break
        }
    }

    // MARK: - Evidence capture (Requirement 7.1, 7.2)

    private func captureEvidence(eventId: UUID, context: CrashReducerContext, signal: CrashSignal?) {
        let now = context.now
        let snapshot = LocationSnapshotPolicy.snapshot(
            fromAcceptedFix: acceptedFix(),
            now: now,
            tuning: tuning
        )
        let footageRef = footageBuffer.preserve(eventId: eventId, around: now)
        let kind: CrashMessageKind = machine.isDrill ? .drill : .crashAlert
        currentKind = kind
        consentVersionForEvent = consentStore.current()?.version ?? minimumConsentVersion
        locationAtSend = nil
        attempts = [:]
        sendRecipients = []
        recipientLabels = [:]

        currentEvent = CrashEvent(
            id: eventId,
            detectedAt: now,
            utcOffsetMinutes: utcOffsetMinutes(at: now),
            isDrill: machine.isDrill,
            source: signal?.source ?? "unknown",
            confidence: signal?.confidence ?? 0,
            rideId: rideContext.currentRideID,
            state: .detected,
            countdown: nil,
            suppressedUntil: nil,
            locationAtDetection: snapshot,
            footageRef: footageRef,
            outcome: nil
        )

        // Evidence captured → let the reducer open the countdown.
        dispatch(.evidenceCaptured)
    }

    private func acceptedFix() -> AcceptedFix? {
        guard let fix = rideContext.latestAcceptedFix else { return nil }
        return AcceptedFix(
            latitude: fix.latitude,
            longitude: fix.longitude,
            horizontalAccuracy: fix.horizontalAccuracy,
            time: fix.timestamp
        )
    }

    private func utcOffsetMinutes(at date: Date) -> Int {
        TimeZone.current.secondsFromGMT(for: date) / 60
    }

    // MARK: - Countdown feedback (Requirement 8.5)

    private func startFeedback(totalSeconds: TimeInterval) {
        let whole = Int(totalSeconds.rounded())
        feedback.begin(totalSeconds: whole)
        armTickTimer()
    }

    private func armTickTimer() {
        tickTimer?.cancel()
        tickTimer = clock.schedule(after: 1) { [weak self] in
            self?.onTick()
        }
    }

    private func onTick() {
        guard machine.eventState == .countdown, let deadline = machine.deadline else { return }
        let remaining = Int(max(0, deadline.timeIntervalSince(clock.now())).rounded(.up))
        feedback.tick(remaining: remaining)
        if remaining > 0 {
            armTickTimer()
        }
    }

    private func endFeedback(for outcome: CountdownOutcome?) {
        let reason: CountdownFeedbackEndReason
        switch outcome {
        case .riderCancelled: reason = .cancelled
        case .expired: reason = .expired
        case .sentNow: reason = .sentNow
        case .consentRevoked: reason = .consentRevoked
        case nil: reason = .expired
        }
        tickTimer?.cancel()
        tickTimer = nil
        feedback.end(reason: reason)
    }

    // MARK: - Timers

    private func armDeadlineTimer(deadline: Date) {
        deadlineTimer?.cancel()
        let delay = max(0, deadline.timeIntervalSince(clock.now()))
        deadlineTimer = clock.schedule(after: delay) { [weak self] in
            self?.dispatch(.deadlineReached)
        }
    }

    private func cancelDeadlineTimer() {
        deadlineTimer?.cancel()
        deadlineTimer = nil
    }

    private func armRetryTimer(delay: TimeInterval) {
        retryTimer?.cancel()
        retryTimer = clock.schedule(after: delay) { [weak self] in
            guard let self else { return }
            // If the stale limit passed, tell the reducer; else trigger a retry.
            if let detectedAt = self.machine.detectedAt,
               !RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: self.clock.now(), tuning: self.tuning) {
                self.dispatch(.staleLimitReached)
            } else {
                self.dispatch(.retryTrigger)
            }
        }
    }

    private func cancelAllTimers() {
        deadlineTimer?.cancel(); deadlineTimer = nil
        retryTimer?.cancel(); retryTimer = nil
        tickTimer?.cancel(); tickTimer = nil
        pollTimer?.cancel(); pollTimer = nil
    }

    // MARK: - Dispatch to the notifier (Requirement 9)

    private func performDispatch(eventId: UUID, isRetry: Bool, context: CrashReducerContext) {
        // Build (or reuse) the send recipients and the message at dispatch time.
        if sendRecipients.isEmpty {
            prepareSend(at: context.now)
        }
        guard !sendRecipients.isEmpty else {
            // No reachable contact at send time ⇒ treat as non-retryable fail.
            dispatch(.dispatchResult(.nonRetryableError))
            return
        }

        let delayed = delayedSeconds(at: context.now)
        let location = currentKind == .crashAlert || currentKind == .drill ? locationForSend(at: context.now) : nil
        let request = CrashNotificationRequest(
            crashEventId: eventId,
            kind: currentKind,
            riderLabel: settingsStore.current().riderLabel ?? "",
            detectedAt: currentEvent?.detectedAt ?? context.now,
            utcOffsetMinutes: currentEvent?.utcOffsetMinutes ?? utcOffsetMinutes(at: context.now),
            delayedSeconds: delayed,
            location: location,
            recipients: sendRecipients,
            consentVersion: consentVersionForEvent,
            templateVersion: CrashMessageBuilder.templateVersion
        )

        let notifier = self.notifier
        Task { [weak self] in
            do {
                let result = try await notifier.send(request)
                self?.handleSendResult(result)
            } catch let error as CrashNotifierError {
                self?.handleSendError(error)
            } catch {
                self?.handleSendError(CrashNotifierError(.unknown))
            }
        }
    }

    /// Capture the reachable recipients, labels, rendered text, and send-time
    /// location for the current event (once per event).
    private func prepareSend(at now: Date) {
        let reachable = reachableContacts()
        sendRecipients = reachable.map { CrashNotificationRecipient(recipientRef: $0.id, e164: $0.e164) }
        for contact in reachable {
            recipientLabels[contact.id] = (contact.label, maskedNumber(contact.e164))
        }
        locationAtSend = locationForSend(at: now)
        let message = CrashMessageBuilder.build(
            kind: currentKind,
            riderLabel: settingsStore.current().riderLabel ?? "",
            detectedAt: currentEvent?.detectedAt ?? now,
            utcOffsetMinutes: currentEvent?.utcOffsetMinutes ?? utcOffsetMinutes(at: now),
            location: currentKind == .crashAlert || currentKind == .drill ? locationAtSend : nil,
            delayedSeconds: TimeInterval(delayedSeconds(at: now)),
            now: now
        )
        renderedText = message.text
    }

    private func locationForSend(at now: Date) -> LocationSnapshot {
        let detection = currentEvent?.locationAtDetection ?? .unavailable
        let snapshot = LocationSnapshotPolicy.snapshotForSend(
            detectionSnapshot: detection,
            latestAcceptedFix: acceptedFix(),
            now: now,
            tuning: tuning
        )
        return snapshot
    }

    private func delayedSeconds(at now: Date) -> Int {
        guard let detectedAt = currentEvent?.detectedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(detectedAt)))
    }

    private func maskedNumber(_ e164: String) -> String {
        String(e164.suffix(2))
    }

    /// Handle a successful/returned notifier result: classify as success vs.
    /// all-rejected (non-retryable) and merge attempts, then feed the reducer.
    private func handleSendResult(_ result: CrashNotificationResult) {
        mergeAttempts(from: result, at: clock.now())
        let anyProgress = result.recipients.contains {
            $0.status == .queued || $0.status == .sent || $0.status == .delivered
        }
        if anyProgress || result.deduplicated {
            dispatch(.dispatchResult(.success))
        } else {
            // Every recipient rejected/failed ⇒ non-retryable failure.
            dispatch(.dispatchResult(.nonRetryableError))
        }
    }

    /// Classify a notifier error into the reducer's dispatch outcome.
    private func handleSendError(_ error: CrashNotifierError) {
        let outcome: CrashDispatchOutcome
        switch error.code {
        case .noConnection:
            outcome = .offline
        case .timeout:
            outcome = .timeoutUnknown
        default:
            outcome = error.isRetryable ? .retryableError : .nonRetryableError
        }
        dispatch(.dispatchResult(outcome))
    }

    // MARK: - All-clear (stretch, Requirement 20)

    private func performAllClear(eventId: UUID) {
        guard !sendRecipients.isEmpty, let event = currentEvent else { return }
        let request = CrashNotificationRequest(
            crashEventId: eventId,
            kind: .allClear,
            riderLabel: settingsStore.current().riderLabel ?? "",
            detectedAt: event.detectedAt,
            utcOffsetMinutes: event.utcOffsetMinutes,
            delayedSeconds: 0,
            location: nil,
            recipients: sendRecipients,
            consentVersion: consentVersionForEvent,
            templateVersion: CrashMessageBuilder.templateVersion
        )
        let notifier = self.notifier
        Task { _ = try? await notifier.send(request) }
    }

    // MARK: - Status polling (Requirement 11.4)

    private func beginStatusPolling(eventId: UUID) {
        guard isForeground else { return }
        pollStatus(eventId: eventId)       // immediately
        startPolling()
    }

    private func startPolling() {
        guard isForeground, let eventId = machine.eventId, hasPendingStatuses() else { return }
        pollTimer?.cancel()
        pollTimer = clock.schedule(after: 5) { [weak self] in
            guard let self else { return }
            self.pollStatus(eventId: eventId)
            if self.hasPendingStatuses() { self.startPolling() }
        }
    }

    private func pollStatus(eventId: UUID) {
        let notifier = self.notifier
        let kind = currentKind
        Task { [weak self] in
            if let result = try? await notifier.status(crashEventId: eventId, kind: kind) {
                self?.onStatusPoll(result)
            }
        }
    }

    private func onStatusPoll(_ result: CrashNotificationResult) {
        mergeAttempts(from: result, at: clock.now())
        dispatch(.statusPollUpdate)
    }

    private func hasPendingStatuses() -> Bool {
        guard !attempts.isEmpty else { return false }
        return attempts.values.contains { !$0.status.isTerminal }
    }

    // MARK: - Attempt merge (monotonic, Requirement 11.8)

    private func mergeAttempts(from result: CrashNotificationResult, at now: Date) {
        for recipient in result.recipients {
            let label = recipientLabels[recipient.recipientRef]?.label ?? ""
            let masked = recipientLabels[recipient.recipientRef]?.masked ?? ""
            if var existing = attempts[recipient.recipientRef] {
                // Monotonic: never regress rank; terminal is sticky.
                if !existing.status.isTerminal, recipient.status.rank >= existing.status.rank {
                    existing.status = recipient.status
                    existing.whooshErrorCode = recipient.whooshErrorCode
                    existing.providerErrorCode = recipient.providerErrorCode
                    existing.updatedAt = recipient.updatedAt
                    attempts[recipient.recipientRef] = existing
                }
            } else {
                attempts[recipient.recipientRef] = AlertAttempt(
                    recipientRef: recipient.recipientRef,
                    labelSnapshot: label,
                    maskedNumber: masked,
                    kind: currentKind,
                    status: recipient.status,
                    whooshErrorCode: recipient.whooshErrorCode,
                    providerErrorCode: recipient.providerErrorCode,
                    attemptedAt: now,
                    updatedAt: recipient.updatedAt
                )
            }
            applyVerification(for: recipient)
        }
    }

    /// Update a contact's verification from a per-recipient status
    /// (`reachable`/`undeliverable`/`optedOut`, Requirement 4.5, design
    /// "Delivery recording and polling").
    private func applyVerification(for recipient: CrashRecipientResult) {
        guard var contact = (try? contactStore.contacts())?.first(where: { $0.id == recipient.recipientRef }) else { return }
        let newVerification: ContactVerification?
        switch recipient.status {
        case .sent, .delivered:
            newVerification = .reachable
        case .undelivered, .failed:
            if recipient.whooshErrorCode == "recipient_opted_out" {
                newVerification = .optedOut
            } else {
                newVerification = .undeliverable
            }
        case .rejected:
            newVerification = recipient.whooshErrorCode == "recipient_opted_out" ? .optedOut : nil
        case .queued:
            newVerification = nil
        }
        guard let verification = newVerification, verification != contact.verification else { return }
        contact.verification = verification
        contact.lastStatusAt = clock.now()
        try? contactStore.update(contact)
    }

    // MARK: - Persistence (Requirement 6.3, 11.1)

    private func persistRecord() {
        guard var event = currentEvent else { return }
        event.state = machine.eventState
        event.outcome = machine.outcome
        event.suppressedUntil = machine.suppressedUntil
        if let deadline = machine.deadline, let total = machine.totalCountdownSeconds {
            event.countdown = CountdownState(deadline: deadline, totalSeconds: total)
        }
        currentEvent = event

        let now = clock.now()
        let ordered = attempts.values.sorted { $0.attemptedAt < $1.attemptedAt }
        let existing = try? repository.record(id: event.id)
        let record = CrashAlertRecord(
            event: event,
            locationAtSend: locationAtSend,
            templateVersion: CrashMessageBuilder.templateVersion,
            renderedText: renderedText,
            attempts: ordered,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try? repository.save(record)
    }

    // MARK: - Relaunch restore (task 14)

    /// Rebuild in-memory per-event bookkeeping and the machine state from a
    /// persisted record before feeding the reducer a `relaunch` event.
    private func restoreState(from record: CrashAlertRecord) {
        let event = record.event
        currentEvent = event
        currentKind = event.isDrill ? .drill : .crashAlert
        locationAtSend = record.locationAtSend
        renderedText = record.renderedText
        consentVersionForEvent = consentStore.current()?.version ?? minimumConsentVersion
        attempts = Dictionary(uniqueKeysWithValues: record.attempts.map { ($0.recipientRef, $0) })
        recipientLabels = Dictionary(
            uniqueKeysWithValues: record.attempts.map { ($0.recipientRef, (label: $0.labelSnapshot, masked: $0.maskedNumber)) }
        )
        // Rebuild the send recipients from the reachable contacts so a resumed
        // send/retry can proceed.
        let reachable = reachableContacts()
        sendRecipients = reachable.map { CrashNotificationRecipient(recipientRef: $0.id, e164: $0.e164) }
        for contact in reachable where recipientLabels[contact.id] == nil {
            recipientLabels[contact.id] = (contact.label, maskedNumber(contact.e164))
        }

        machine = CrashMachineState(
            eventState: event.state,
            eventId: event.id,
            detectedAt: event.detectedAt,
            isDrill: event.isDrill,
            deadline: event.countdown?.deadline,
            totalCountdownSeconds: event.countdown?.totalSeconds,
            suppressedUntil: event.suppressedUntil,
            perRideSentCount: event.state == .sent ? 1 : 0,
            attemptCount: record.attempts.isEmpty ? 0 : 1,
            requestInFlight: false,
            timeoutRetryUsed: false,
            outcome: event.outcome
        )
    }

    // MARK: - Display refresh

    private func refreshDisplay() {
        bannerKind = bannerKind(for: machine.eventState)
        isTakeoverPresented = (machine.eventState == .countdown)
        isRecoveryPromptPresented = (machine.eventState == .recoveryPrompted)
        isComposerFallbackOffered = (machine.eventState == .queuedOffline
            || machine.eventState == .fallbackPrompted
            || machine.eventState == .stale)
        recipients = buildRecipientDisplays()
    }

    private func bannerKind(for state: CrashEventState) -> CrashBannerKind {
        switch state {
        case .queuedOffline: return .queuedOffline
        case .stale: return .stale
        case .failed, .fallbackPrompted: return .failed
        case .recoveryPrompted: return .recoveryPrompted
        default: return .none
        }
    }

    private func buildRecipientDisplays() -> [CrashRecipientDisplay] {
        // Prefer the captured send set; fall back to the reachable contacts for
        // the countdown preview before a send.
        if !recipientLabels.isEmpty {
            return recipientLabels.map { ref, info in
                CrashRecipientDisplay(
                    recipientRef: ref,
                    label: info.label,
                    maskedNumber: info.masked,
                    status: attempts[ref]?.status
                )
            }
            .sorted { $0.label < $1.label }
        }
        return reachableContacts().map {
            CrashRecipientDisplay(
                recipientRef: $0.id,
                label: $0.label,
                maskedNumber: maskedNumber($0.e164),
                status: nil
            )
        }
        .sorted { $0.label < $1.label }
    }
}
