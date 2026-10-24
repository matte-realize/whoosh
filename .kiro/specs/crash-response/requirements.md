# Requirements — Whoosh Emergency Contact and Crash Response

**Status: APPROVED by the iOS owner (October 24, 2026)** with the recommended answers to the open
decisions (`design.md`, "Owner resolution"). iOS Tier 0 work may proceed. Network tasks (Tier 1)
still wait until Role C marks `.kiro/team/crash-alert-contract.md` **Agreed**.

## Introduction

This spec adds an **opt-in, post-MVP safety feature** to Whoosh: a rider configures trusted
emergency contacts, and if the app's crash-detection service identifies a *probable* crash
during a ride, the app preserves what evidence is available, starts an audible/visual/haptic
countdown with a very large "I'm OK — Cancel" control, and — if the rider does not cancel —
automatically notifies the contacts by text message. The message carries a map link, a
timestamp, and an unmistakable statement that **a crash was detected but an injury has not
been confirmed**.

It builds on the finished ride-recording MVP (`../ride-recording-mvp/`): MVVM + service
protocols with fakes, the `Clock` seam, SwiftData repositories, the `RideSessionViewModel`
state machine, and the `HazardDetector` / `AlertManager` seams. It does not modify the ride
engine's behavior; ride recording is never blocked by anything in this spec (MVP Req 8.3, 11).

Three constraints shape everything below (see `design.md` "iOS capability investigation"):

1. **A third-party iOS app cannot send an SMS silently from the user's number.** The native
   composer always requires the rider to tap Send. Automatic notification therefore requires a
   **backend SMS provider** sending from a provider number. The composer is only a
   *user-initiated fallback*.
2. **Apple's system Crash Detection *is* exposed to apps via SafetyKit (iOS 16+), under an
   Apple-granted entitlement.** (An earlier draft wrongly said it was not available.) Whoosh
   defines a `CrashDetector` seam and ships a no-op plus a debug "Simulate crash" trigger; it
   adds an **entitlement-gated `SafetyKitCrashDetector`** (`SACrashDetectionManager` /
   `SACrashDetectionEvent`, requires `com.apple.developer.severe-vehicular-crash-event`,
   `isAvailable`/authorization checks, one app per device, background-launch + dedupe, severe
   *vehicular* scope that may not fire for a bicycle fall — **verify against current Apple docs**)
   alongside an *experimental* on-device Core Motion heuristic (a separately-tasked stretch).
3. **The countdown and the send need the app to be running.** v1 is a foreground, screen-awake,
   client-driven countdown (the MVP's ride behavior), with documented limits.

### Explicit non-goals (v1)

- Whoosh does **not** call or text emergency services (911/112) automatically. A rider-initiated
  "Call 911" button is allowed as a manual action only (Requirement 17).
- Whoosh is **not** a guaranteed emergency-response service. It cannot guarantee that a crash
  is detected, that an alert is sent, or that a message is delivered or read.
- No raw camera video or frames are ever uploaded or put in a message (Requirement 7, 16).
- No background location mode, no server-side countdown, no Critical Alerts entitlement in v1
  (Requirement 21 documents them as follow-ups).
- No non-US/CA phone numbers in v1 (cost and provider geo-permission control; Requirement 2.4).

## How to read this document

- Acceptance criteria use EARS-style phrasing (WHEN/WHILE/IF ... THEN ... SHALL ...) so each is
  individually verifiable.
- **Priority** tags: `Demo-critical` (must work live), `Important` (strongly expected),
  `Stretch` (valuable, never blocking), `Future-seam` (defined now, built later).
- "Configurable" means the value lives in one `CrashResponseTuning` constants type with a
  documented default and range; it does not mandate a user-facing setting.
- Defaults referenced in this document (all in `CrashResponseTuning`): countdown **30 s**
  (allowed 15–60 s); suppression window **120 s**; max automatic alerts sent per ride **1**;
  max contacts **3**; stale limit **30 min**; max location age **30 min**; "current fix"
  age **≤ 10 s**; retry backoff **5, 15, 30, 60 s then every 60 s**.
- Units follow the MVP: SI internally; US customary in display (ft/mi); the message uses
  meters for accuracy and seconds/minutes for age because the *recipient* needs to judge it.
- Every acceptance criterion maps to tasks in `tasks.md` via `_Requirements:_` annotations.

## Glossary

- **Rider** — the person using Whoosh and recording a ride.
- **Emergency contact** — a person the rider chose to be notified; stored only on the rider's
  device (Requirement 2).
- **Crash detector** — anything implementing the `CrashDetector` seam: the no-op, the debug
  simulator, or the experimental Core Motion heuristic. It emits a *probable crash* signal.
- **Probable crash** — a detector signal, not a fact. Treated as unconfirmed until the rider
  does or does not cancel.
- **Crash event** — one probable-crash occurrence, identified by a UUID `crashEventId` that is
  also the backend idempotency key.
- **Countdown** — the full-screen, audible, visual, haptic interval after a probable crash in
  which the rider can cancel ("I'm OK").
- **Crash alert** — the text message sent to each emergency contact when the countdown
  expires uncancelled. Kinds: `crash_alert`, `drill` (simulated crash), `test`, `intro`,
  `all_clear`.
- **Crash-alert backend** — the Supabase Edge Functions in `crash-alert-contract.md` that
  call the SMS provider. The provider is an implementation detail (Twilio is the example).
- **Location snapshot** — coordinates plus age and horizontal accuracy, or an explicit
  "unavailable".
- **Suppression window** — period after a cancel or a send during which new probable-crash
  signals are ignored.
- **Composer fallback** — a rider-initiated, prefilled `MFMessageComposeViewController`
  ("Tap to text your contact now"). Never sends without the rider tapping Send.
- **Drill** — a simulated crash used for the demo; always sent with unmistakable "DEMO — NOT
  REAL" wording.

---

## Requirement 1: Positioning, honesty, and non-guarantee

**Priority:** Demo-critical

**User story:** As a rider, I want to understand exactly what this feature does and does not
do, so I never rely on it as a guarantee.

### Acceptance Criteria

1. The consent flow (Requirement 3), the Emergency settings screen, and the crash-countdown
   and status screens SHALL state that Whoosh is **not a guaranteed emergency-response
   service**, may fail to detect a crash, may send false alerts, cannot guarantee message
   delivery, and does **not** contact emergency services.
2. The rider SHALL be required to explicitly acknowledge criterion 1 (a separate control from
   the data-use consent) before crash alerts can be enabled.
3. UI and message copy SHALL NOT claim that Whoosh prevents, predicts, or guarantees
   avoidance of crashes, that help is on the way, or that emergency services were notified.
   Detection SHALL be labeled **experimental** wherever a detector is named in the UI.
   Disclaimer copy SHALL be phrased so it also passes `scripts/privacy-check.sh` rule 4 (e.g.
   "cannot guarantee detection or delivery", not "cannot prevent a crash").
4. The feature SHALL be **off by default** and enabled only through the Emergency setup flow.
5. WHEN crash alerts are off, not consented, or no verified contact exists THEN the app
   SHALL behave exactly as the MVP: no countdown, no notification, no network use for this
   feature.

## Requirement 2: Emergency contact management

**Priority:** Demo-critical

**User story:** As a rider, I want to choose, test, change, and remove my trusted contacts
before I ride.

### Acceptance Criteria

1. The rider SHALL be able to add an emergency contact by (a) picking from the system contact
   picker (`CNContactPickerViewController`, which requires no Contacts permission) or (b)
   typing a name and phone number manually. The app SHALL NOT request Contacts permission.
2. The system SHALL allow **1 to 3** contacts (configurable maximum 3); adding a fourth SHALL
   be refused with an explanation (cost/abuse control).
3. The system SHALL normalize every entered number to **E.164** and validate it before saving;
   invalid input SHALL show an inline, actionable error and SHALL NOT be saved.
4. In v1 only US/Canada (`+1`, NANP-valid) numbers SHALL be accepted; other countries SHALL be
   refused with a "not supported yet" message. (`Future-seam` for other regions.)
5. Each contact SHALL have a display label (editable) and a **verification state**:
   `unverified` (no message sent), `introSent`, `reachable` (provider reported `sent` or
   `delivered`), `undeliverable` (provider reported undelivered/failed), or `optedOut`
   (recipient replied STOP). Automatic alerts SHALL be sent only to contacts in `reachable`
   state (Requirement 4.5).
6. The rider SHALL be able to edit a contact's label or number and to remove a contact at any
   time. Changing a number SHALL reset that contact to `unverified`. Removal SHALL delete the
   contact from secure storage immediately and SHALL NOT affect past alert history except for
   the masked display (Requirement 11.3).
7. Contact names and phone numbers SHALL be stored **on the device only**, in the Keychain
   (accessibility `AfterFirstUnlockThisDeviceOnly`), not in plain SwiftData, UserDefaults, logs,
   or iCloud. Contacts SHALL NOT be included in any backup that leaves the device.
8. IF Keychain items exist on first launch of a fresh install (items can outlive app
   deletion) THEN the app SHALL purge them so deleting the app removes the contacts.
9. The rider SHALL be required to enter a **rider label** (first name or nickname, ≤ 20
   characters, letters/digits/space/`.`/`'`/`-` only) used in messages so recipients know who
   the alert is about. Alerts SHALL NOT be enabled without it.
10. All persistence access SHALL go through an `EmergencyContactStore` abstraction with an
    in-memory fake, and SHALL be unit-tested (add/update/remove/limit/validation/purge).

## Requirement 3: Consent and disclosure

**Priority:** Demo-critical

**User story:** As a rider, I want to know exactly what is sent, to whom, and by what, and to
be able to withdraw consent at any time.

### Acceptance Criteria

1. Crash alerts SHALL require a **separate, explicit, versioned consent** recorded locally
   (version number, accepted-at timestamp). It SHALL be independent of the ride-sync toggle
   (MVP Req 12); enabling one SHALL NOT enable the other.
2. The consent screen SHALL list exactly **what is sent**: the rider label; the crash
   timestamp and UTC offset; the last known or current location as map links (precise,
   *not* privacy-zone trimmed); a statement that a crash was detected but an injury is not
   confirmed; and the contact's phone number (to the backend and SMS provider, only when an
   alert/test/intro is sent).
3. The consent screen SHALL list exactly **what is NOT sent**: no camera video or frames, no
   ride history or route, no contact list, no device identifiers beyond an anonymous account.
4. The consent screen SHALL state that text messages are not end-to-end encrypted, that the
   SMS provider and carriers process them, that delivery is not guaranteed, that the contact
   can reply STOP, and that the rider is responsible for telling their contacts.
5. The consent screen SHALL show the **exact text** of the message a contact would receive
   (rendered by the same pure builder as Requirement 10, with an example location).
6. WHEN the consent text changes materially THEN the consent version SHALL be incremented and
   the rider SHALL be asked again; until re-accepted, automatic alerts SHALL be disabled.
7. The rider SHALL be able to revoke consent at any time. WHEN consent is revoked THEN
   automatic alerts SHALL be disabled immediately, any queued unsent alert SHALL be cancelled
   with a visible note, and the rider SHALL be offered "Delete my contacts".
8. WHEN consent is missing, revoked, or outdated AND a probable crash is detected THEN the
   system SHALL NOT start a countdown or send anything automatically; it MAY show a
   non-blocking prompt on next foreground (Requirement 12.7).
9. Consent state and version SHALL be sent with each alert request so the backend can log it;
   the backend SHALL reject requests from client versions below its minimum consent version.

## Requirement 4: Introduction and test messages

**Priority:** Demo-critical

**User story:** As a rider, I want to test the whole notification workflow and make sure my
contact knows why they might hear from Whoosh.

### Acceptance Criteria

1. WHEN a contact is added THEN the app SHALL offer to send an **introduction** message to it
   (telling them who added them, that they may receive a crash text, and how to STOP).
2. The rider SHALL be able to send a **test message** to any contact at any time from the
   Emergency screens. A test message states clearly that no crash happened.
3. Intro and test messages SHALL use the same backend path, authentication, idempotency, and
   delivery-status mechanism as real alerts, so a successful test is meaningful evidence the
   real path works.
4. The test flow SHALL show the per-contact status progression (`queued` → `sent` →
   `delivered`, or `undelivered`/`failed` with a plain reason) and SHALL work with a
   `FakeCrashNotifier` in tests and previews.
5. A contact SHALL become `reachable` only after an intro or test reaches provider status
   `sent` or `delivered`. IF a contact later replies STOP (provider error "recipient
   unsubscribed") THEN the contact SHALL become `optedOut`, the rider SHALL be told, and the
   contact SHALL NOT be sent automatic alerts.
6. Intro and test sends SHALL be rate-limited more tightly than real alerts (Requirement 15)
   and the rider SHALL see a friendly message when a limit is hit.
7. The test flow SHALL require crash-alert consent (Requirement 3) and network; WHEN offline
   THEN it SHALL explain that testing needs a connection and SHALL NOT queue test messages.
8. WHILE the Twilio trial (or equivalent) restriction applies, THE test flow SHALL show a
   plain explanation when a provider rejects an unverified recipient number.

## Requirement 5: Crash detection seam and arming

**Priority:** Demo-critical (seam + simulator); Stretch (experimental heuristic detector);
Future-seam (entitlement-gated SafetyKit detector)

**User story:** As a developer, I want a clean seam so different crash detectors — including a
future better one — can plug in without touching the ride engine or the alert workflow.

### Acceptance Criteria

1. The system SHALL define a `CrashDetector` abstraction that emits a *probable crash*
   signal (timestamp, a confidence value in `0...1`, a short source label such as
   `simulator` or `motion-heuristic`) and has `start()` / `stop()`. It SHALL be on-device,
   non-blocking, and `Sendable`-friendly, consistent with the `HazardDetector` contract (MVP
   Req 8.3).
2. The MVP-compatible default SHALL be a `NoopCrashDetector` that never emits. A
   `FakeCrashDetector` SHALL emit on command for tests.
3. A `DebugCrashSimulator` SHALL emit a signal on demand, reachable only when the
   "Simulate crash" toggle is explicitly enabled in Settings (Requirement 19). Signals from
   the simulator SHALL be marked `isDrill = true`, and any message resulting SHALL use the
   `drill` template.
4. The detector SHALL be **armed** only WHILE a ride is `recording` or `signalLost`, crash
   alerts are enabled and consented, and at least one `reachable` contact exists. It SHALL be
   disarmed while `paused`, `idle`, `finished`, or when consent is revoked. (Armed rules are
   a pure, unit-tested function of those inputs.)
5. An **experimental** `MotionCrashDetector` (Core Motion accelerometer/device-motion +
   GPS speed-drop + post-impact stillness) MAY be implemented as a separate stretch task. It
   SHALL be labeled experimental in UI and docs, SHALL expose every threshold in
   `CrashResponseTuning`, and SHALL ship only after its false-positive behavior has been
   measured on real rides and the measured numbers recorded in the spec's design notes. Its
   pure signal-processing core SHALL be unit-tested against recorded/synthetic traces (Req
   19.7).
6. The system SHALL NOT claim reliable crash detection anywhere in copy. Phrases such as
   "may detect a possible crash" are acceptable; "detects crashes" is not.
7. Detector implementations SHALL NOT access the camera. (Camera-based crash cues are
   `Future-seam`, owned by the detection teammate behind this same protocol.)
8. A detector failure or absence SHALL NOT affect ride recording.
9. The system MAY include an **entitlement-gated `SafetyKitCrashDetector`** behind the same
   `CrashDetector` protocol, using Apple's SafetyKit (`SACrashDetectionManager` /
   `SACrashDetectionEvent`). IF the `com.apple.developer.severe-vehicular-crash-event`
   entitlement is granted, `SACrashDetectionManager.isAvailable` is true, and the user has
   authorized the app, THEN SafetyKit events SHALL emit a `CrashDetector` signal
   (`source = "safetykit"`, `isDrill = false`) that flows through the same coordinator, reducer,
   and countdown as any other detector; OTHERWISE the app SHALL behave exactly as without it
   (no change). The adapter SHALL dedupe events that the system re-reports across background
   launches (idempotent on the crash event), SHALL NOT use `SAEmergencyResponseManager` (Whoosh
   never auto-contacts emergency services, Requirement 17), and SHALL be labeled a better
   *source*, never a reliability guarantee. All SafetyKit claims are marked **verify against
   current Apple docs**; SafetyKit targets severe *vehicular* crashes and may not fire for a
   bicycle fall. The OS background-launch after a SafetyKit event is a **partial** mitigation of
   the foreground-only limitation (Requirement 13.2) for SafetyKit-detected events only.

## Requirement 6: Crash event lifecycle and duplicate prevention

**Priority:** Demo-critical

**User story:** As a rider and as a contact, I never want one crash to produce repeated
alerts, and I never want a relaunch to re-trigger an old one.

### Acceptance Criteria

1. The crash workflow SHALL be modeled as an explicit state machine with states `idle`,
   `detected`, `countdown`, `cancelled`, `sending`, `sent`, `queuedOffline`, `failed`,
   `fallbackPrompted`, plus `recoveryPrompted` (after an interrupted run, Req 13.5) and
   `stale` (Req 12.3). Only the transitions in `design.md` SHALL be permitted; undefined
   transitions SHALL be no-ops, never crashes. Each transition-table row SHALL be a unit test.
2. Every crash event SHALL have a UUID `crashEventId`, generated once at detection, persisted
   with its state, and used as the idempotency key both locally and in the backend request.
3. The state and `crashEventId` SHALL be persisted on every transition so that a relaunch
   cannot start a second countdown or re-send for the same event (Req 13.5 defines recovery).
4. WHILE a crash event is active (`detected`, `countdown`, `sending`, `queuedOffline`,
   `failed`, `fallbackPrompted`, `recoveryPrompted`) OR a suppression window is running
   THE system SHALL ignore new probable-crash signals (they are logged as `suppressed`
   and never start a countdown or a send).
5. WHEN the rider cancels the countdown THEN the system SHALL enter `cancelled`, record the
   reason `riderCancelled`, stop all feedback, send nothing, and start a **suppression
   window** (default 120 s) during which new signals are ignored.
6. WHEN an alert reaches a terminal sent state THEN the system SHALL start the suppression
   window and SHALL enforce a **per-ride cap** of 1 automatic alert (configurable) counted
   against *sent* alerts only; a cancelled countdown does not consume the cap.
7. IF the same `crashEventId` is submitted to the backend more than once (retry, relaunch,
   duplicate tap, race) THEN the backend SHALL send at most one message per recipient for it
   (Requirement 14.5) and the client SHALL treat the repeated response as the same event.
8. The countdown SHALL be driven by an absolute **deadline** (`Clock`-based), not a
   decrementing counter, so a missed timer tick, a backgrounded app, or a rebuilt view cannot
   extend or double-fire it.
9. Only one crash event SHALL be active at a time; the "send" action SHALL be taken exactly
   once per event per recipient on the client (guarded by the persisted state).

## Requirement 7: Evidence collection — timestamp, location, footage

**Priority:** Demo-critical (timestamp, location); Future-seam (footage)

**User story:** As a contact, I want to know when and where the rider probably crashed; as a
rider, I want any pre-crash footage kept safely on my device.

### Acceptance Criteria

1. WHEN a probable crash is detected THEN the system SHALL record the detection timestamp
   (from the injected `Clock`) and the UTC offset in effect at the rider's location.
2. WHEN a probable crash is detected THEN the system SHALL capture a **location snapshot**:
   the freshest accepted route point (coordinates, age, horizontal accuracy), or an explicit
   "unavailable" if no accepted fix exists in this ride or the freshest is older than the max
   location age (default 30 min).
3. WHEN the countdown expires and a newer accepted fix exists THEN the message SHALL use the
   newer fix (age computed at send time); both snapshots SHALL be stored in the record.
4. A fix with age ≤ 10 s SHALL be described as the current location; an older fix SHALL be
   described as "last known location" with its age and accuracy.
5. The location snapshot SHALL come from a `RideContext`-style read-only provider so the
   crash workflow neither changes nor depends on the internals of `RideSessionViewModel`
   (Requirement 13.1).
6. The system SHALL define a `FootageBuffer` abstraction (rolling pre-crash buffer) with a
   `NoopFootageBuffer` default. WHEN a probable crash is detected THEN the system SHALL ask
   the buffer to preserve the available pre-crash footage **locally** and store a nullable
   reference in the crash record; IF no footage is available THEN the record SHALL say
   "no footage" (not an error).
7. Footage SHALL stay **on the device**. It SHALL NEVER be uploaded, attached to a message,
   or referenced by a URL in a message. The notifier protocol SHALL have no parameter that can
   carry footage, and the privacy check SHALL keep camera APIs out of the notification and
   crash-workflow layers.
8. The footage buffer SHALL exist only if the user has separately enabled camera detection
   (not in this spec's v1); this spec requests no camera permission.
9. The user SHALL be able to delete saved footage and a crash record's footage reference from
   the crash alert log (Requirement 11.5). (`Future-seam` until a real buffer ships.)

## Requirement 8: Countdown and cancellation

**Priority:** Demo-critical

**User story:** As a rider who is fine, I want an obvious, easy way to stop a false alert; as
a rider who is not, I want the alert to go out without me touching the phone.

### Acceptance Criteria

1. WHEN a crash event enters `countdown` THEN the system SHALL present a **full-screen
   takeover** above every other screen (including the active-ride cover and Home) showing a
   very large remaining-seconds number and the text "Crash detected. Sending an alert to
   <contacts> in N seconds." with the not-a-guarantee note in smaller type.
2. The countdown SHALL last **30 s by default** and SHALL be configurable within **15–60 s**;
   values outside the range SHALL be clamped to the nearest bound.
3. The takeover SHALL provide a prominent **"I'm OK — Cancel"** control at least **80 pt**
   tall and full-width, placed in the one-handed thumb zone, with an accessibility label and
   a VoiceOver-activatable path that does not require precise touch.
4. Cancellation SHALL be a **single tap** (not a hold), because a false positive must be easy
   to dismiss; accidental-cancel risk is accepted and documented (design decision D12).
5. The countdown SHALL provide three independent signals: **audible** (spoken prompt then a
   tone each second in the final 10 s, via `AVAudioSession` playback category so the ring/
   silent switch does not mute it — verify on device), **haptic** (a warning pulse each
   second, foreground only), and **visual** (high-contrast screen with a numeric countdown).
   No single signal SHALL be the only indication.
6. Visual feedback SHALL be flashing-safe: no more than **one** full-screen luminance change per
   second and no flashing when Reduce Motion is enabled (use a static high-contrast state).
7. Audio SHALL duck or interrupt other audio for the countdown and release the audio session
   when the countdown ends or is cancelled.
8. The takeover SHALL keep the screen awake and SHALL NOT be dismissible by swipe or system
   gesture; the only exits are Cancel, expiry (→ sending), or an explicit "Send now".
9. The takeover SHALL offer a secondary **"Send now"** control to skip the remaining wait
   (not adjacent to Cancel). It SHALL be disabled in tests that assert the full wait.
10. The system SHALL record how the countdown ended: `riderCancelled` or `expired` (or
    `sentNow`), with timestamps.
11. IF the app becomes inactive/backgrounded during the countdown THEN the deadline SHALL
    remain authoritative (Req 6.8) and a time-sensitive local notification SHALL have been
    scheduled for the deadline as a backup prompt (Requirement 13.3).
12. The countdown screen SHALL include a clearly secondary manual "Call 911" action per
    Requirement 17, hidden for drills.

## Requirement 9: Automatic notification

**Priority:** Demo-critical

**User story:** As a rider who did not cancel, I want my trusted contacts texted automatically,
with the app doing everything it can to make that happen.

### Acceptance Criteria

1. WHEN the countdown expires (or "Send now") AND crash alerts are consented AND at least one
   `reachable` contact exists THEN the system SHALL enter `sending` and request the
   `CrashNotifier` to send the alert to **all** reachable contacts (max 3) in **one request**
   keyed by `crashEventId`.
2. The notification mechanism SHALL be the **crash-alert backend** (Requirement 14). The
   native SMS composer SHALL NOT be used for automatic sending, and the app SHALL NOT claim or
   attempt to send silently from the rider's number.
3. The notifier SHALL return per-recipient results (`queued`, `sent`, `delivered`,
   `undelivered`, `failed`, `rejected`) with a stable app-level error code when applicable.
4. WHEN a request returns at least one recipient `queued`/`sent`/`delivered` THEN the event
   SHALL enter `sent` (partial failures are shown per contact; the event is not retried as
   a whole). IF every recipient is `rejected`/`failed` with a non-retryable code THEN the event
   SHALL enter `failed` and the composer fallback SHALL be offered (Requirement 12).
5. The client SHALL NOT retry a request that the backend has acknowledged for that
   `crashEventId`; it SHALL poll status instead (Requirement 11.4).
6. The send SHALL run off the main actor and SHALL NOT block the UI or ride recording.
7. WHEN the send action is taken THEN the suppression window and per-ride cap SHALL apply
   (Req 6.6) regardless of whether the final delivery status is later `undelivered`.
8. The notifier SHALL be an injected protocol with `Noop`, `Fake` (scriptable success/
   failure/timeout/delivery-status), and `Supabase` implementations.

## Requirement 10: Message content

**Priority:** Demo-critical

**User story:** As a contact, I want a short, plain, honest message that tells me who, when,
where, and what is and is not known.

### Acceptance Criteria

1. A `crash_alert` message SHALL include: the rider label; the local date/time with UTC
   offset; a location block (Apple Maps link **and** Google Maps link, each an HTTPS URL, plus
   age and accuracy when not current) or "Location unavailable."; the exact sentence "A crash
   was detected but an injury has NOT been confirmed."; and "Sent automatically by Whoosh,
   not an emergency service. Reply STOP to opt out."
2. The text SHALL be produced by a **pure, Foundation-only message builder** with golden-string
   unit tests, using the cases in `crash-alert-contract.md` Appendix A as the shared source of
   truth between iOS and the backend.
3. The builder SHALL restrict output to the **GSM-7 character set** (ASCII-safe copy, no smart
   quotes or emoji) and SHALL sanitize the rider label accordingly, because any non-GSM
   character forces UCS-2 encoding and shrinks segments from 153 to 67 characters (cost).
4. The builder SHALL report character count and SMS segment count; a `crash_alert` SHALL fit
   in **≤ 4 segments (≤ 612 characters)**. IF a rendering would exceed that THEN the builder
   SHALL drop the Google Maps line before truncating anything else.
5. WHEN the message is delayed by ≥ 60 s between detection and send THEN it SHALL include
   "Message delayed by N min."
6. WHEN the location is a last-known fix THEN the text SHALL show its age and accuracy (for
   example "Last known location (45 s old, +/-30 m)"); WHEN location is unavailable THEN it
   SHALL say so and the message SHALL still be sent.
7. A `drill` message SHALL begin "WHOOSH DEMO - NOT REAL" and say no crash happened; `test`,
   `intro`, and `all_clear` SHALL use the templates in the contract appendix.
8. The backend SHALL render the message from structured fields using the same template
   version; it SHALL accept **no free-form text** from the client other than the sanitized
   rider label (no open relay, Requirement 15.3).
9. The template SHALL carry an integer `templateVersion` sent by the client; the backend SHALL
   reject unknown versions and the client SHALL fall back to composer-only on rejection.

## Requirement 11: Delivery recording and the crash alert log

**Priority:** Demo-critical (record + live status); Important (log screen, polling edge cases)

**User story:** As a rider, I want a trustworthy record of what happened and what was
delivered, even if I never see the screen again.

### Acceptance Criteria

1. The system SHALL persist a local `CrashAlertRecord` (SwiftData, behind a repository
   protocol with an in-memory fake) per crash event with: `crashEventId`; detection time and
   UTC offset; whether it was a drill; location snapshot(s) (coordinates, age, accuracy) or
   "unavailable"; countdown outcome and timestamps; current state; the template version and
   rendered text; a nullable footage reference; and an ordered list of **per-recipient attempts**.
2. Each attempt SHALL record: attempt time; recipient reference and masked number (last 2
   digits); status (`queued`, `sent`, `delivered`, `undelivered`, `failed`, `rejected`);
   Whoosh error code; provider error code when available; last-update time.
3. The record SHALL NOT store the full phone number; it SHALL store the contact reference,
   the display label snapshot, and the masked number.
4. WHILE an event has recipients not yet in a terminal status THE system SHALL poll the
   backend status endpoint by `crashEventId` (immediately, then every 5 s for 60 s, then every
   15 s up to 10 min), update attempts, and stop polling on terminal statuses or the cap. Polling
   SHALL happen only while the app is foregrounded.
5. The Settings → "Crash alerts" **log screen** SHALL list records most-recent-first with an
   icon + text status and SHALL let the rider delete one record or all records (real deletion).
6. The post-send **status screen** SHALL show per-contact status in plain language and the
   not-a-guarantee note, and SHALL offer the composer fallback and "I'm OK" follow-up
   (Requirement 20) as applicable.
7. Statuses SHALL be conveyed with icon + text, never colour alone.
8. Status SHALL be monotonic: a later `queued` response SHALL NOT overwrite `delivered`.
9. Records SHALL be retained locally until the rider deletes them or a configurable local
   retention (default 90 days) elapses; deletion SHALL be real.

## Requirement 12: Fallbacks

**Priority:** Demo-critical (composer fallback, offline queue, location fallback); Important (rest)

**User story:** As a rider, I want clear fallbacks when the phone has no network, GPS is
unavailable, or the messaging service fails.

### Acceptance Criteria

1. IF there is no network when the countdown expires THEN the event SHALL enter
   `queuedOffline`, retry on connectivity change and on the backoff schedule (5, 15, 30, 60 s,
   then every 60 s) via a `ConnectivityMonitor` abstraction, and the rider SHALL be shown a
   persistent "Alert not sent yet" banner with a one-tap **"I'm OK — cancel alert"** and a
   **"Tap to text <contact> now"** composer-fallback action, plus a local notification.
2. WHEN connectivity returns within the stale limit (default 30 min of detection) THEN the
   queued alert SHALL be sent with the "Message delayed by N min." wording.
3. IF the stale limit passes without a successful send THEN the event SHALL become `stale`,
   SHALL NOT be sent automatically, and the rider SHALL be told (on next foreground and by local
   notification) with the composer fallback and "discard" actions.
4. IF location is unavailable THEN the alert SHALL still be sent with "Location unavailable."
   wording; IF only an old fix exists THEN last-known wording with age/accuracy.
5. IF the backend or SMS provider fails (HTTP 5xx, timeout, network error) THEN the client
   SHALL retry with backoff (same `crashEventId`) up to the stale limit or 6 attempts,
   whichever comes first, then mark the event `failed`, then enter `fallbackPrompted`.
6. Non-retryable errors (kill switch `service_disabled`, `rate_limited` daily cap,
   `invalid_*`, `unsupported_template_version`, `consent_*`) SHALL NOT be retried; the event
   SHALL go to `failed` → `fallbackPrompted` immediately with a plain explanation.
7. IF consent is missing/outdated or no `reachable` contact exists WHEN a probable crash occurs
   THEN no automatic action SHALL be taken; a prompt MAY be shown on next foreground.
8. The composer fallback SHALL be shown only when the device can send text (the equivalent
   of `canSendText`); otherwise the app SHALL offer **Copy message** and **Share** actions.
9. The composer fallback SHALL be pre-filled (recipient + message built by the same builder
   with `delayedSeconds`) and SHALL NEVER send without the rider tapping Send.
10. Every fallback row above SHALL be unit-tested with fakes (Requirement 19).

## Requirement 13: Execution environment, backgrounding, and relaunch

**Priority:** Important

**User story:** As a rider, I want the app to behave predictably when iOS limits what it can
do, and I want to know those limits.

### Acceptance Criteria

1. The crash workflow SHALL attach to the ride via a small read-only **`RideContext`** and an
   observing bridge, without modifying `RideSessionViewModel` internals (permitted addition:
   a read-only accessor for the current ride id, if the owner approves).
2. v1 SHALL assume the MVP's foreground, screen-awake ride (idle timer disabled). The docs and
   consent SHALL state that crash alerts work **only while Whoosh is open and the ride is
   active**, and may not work if the app is closed, the phone is locked, or iOS suspends it.
3. WHEN a countdown starts THEN the app SHALL schedule a **time-sensitive local notification**
   at the deadline (a backup prompt, not a send) and cancel it on cancel/send. Notification
   permission SHALL be requested only when the rider enables crash alerts, with an honest
   purpose string.
4. The app SHALL keep the screen awake and SHALL NOT enable the `location` background mode in
   v1 (documented follow-up, Requirement 21). IF the app returns to the foreground after the
   deadline THEN it SHALL reconcile state from the persisted record (never double-send).
5. WHEN the app relaunches and finds a persisted event: IF `countdown` with remaining time
   THEN resume with the remaining time; IF `countdown` with the deadline passed THEN enter
   `recoveryPrompted` ("Your app closed during a crash countdown — send the alert?" with
   **Send now** / **I'm OK**) rather than auto-sending (a relaunch implies someone is using
   the phone); IF `sending` THEN resume with the same `crashEventId` (idempotent); IF
   `queuedOffline` and within the stale limit THEN resume retries; otherwise leave terminal
   states untouched.
6. Resuming SHALL honor the suppression window and per-ride cap (Req 6).
7. The phone being destroyed, off, or without signal after impact SHALL be documented as a
   known limit of the v1 client-driven design; the server-side countdown option (design item
   (d)) is recorded as a v2 follow-up (Requirement 21).

## Requirement 14: Backend integration and security

**Priority:** Demo-critical

**User story:** As the team, I want messages sent through a secure backend so no provider
secrets or open-relay risk ever reach the app.

### Acceptance Criteria

1. The app SHALL call only the Supabase Edge Functions defined in `crash-alert-contract.md`
   (`send-crash-alert`, `crash-alert-status`); it SHALL implement against the contract only
   once marked **Agreed** (same rule as MVP Req 12.9).
2. SMS provider credentials SHALL exist **only** as Edge Function secrets in Role C's
   environment. The app and Git repo SHALL contain no provider credentials; the privacy check
   SHALL flag provider-credential patterns.
3. The app SHALL authenticate with the Supabase **anonymous-auth JWT** plus the public anon
   key. The `service_role` key SHALL never ship. The Edge Function SHALL verify the JWT.
4. All traffic SHALL use TLS. The backend SHALL NOT persist plaintext phone numbers; it SHALL
   store only a **salted hash and the last 2 digits** per recipient for audit and rate
   limiting. It SHALL NOT persist the message body or coordinates (Req 16.6).
5. The backend SHALL enforce **idempotency**: a unique constraint on
   (`user_id`, `crash_event_id`, `recipient_hash`, `kind`) such that repeated requests for the same event
   never send a second message to the same recipient; a repeated request returns the existing
   per-recipient statuses with `deduplicated: true`.
6. The backend SHALL accept provider **delivery status callbacks**, validate the provider's
   signature, and update statuses idempotently and monotonically (callbacks can be duplicated
   or arrive out of order).
7. The backend SHALL expose a **status endpoint** by `crashEventId` that returns per-recipient
   statuses for the authenticated user only (RLS).
8. The backend SHALL log without PII (no numbers, names, coordinates, or message bodies).
9. Documented environment constraint: for the hackathon demo the provider runs in **trial
   mode** (verified recipient numbers only, trial message prefix); full sender registration
   (10DLC / toll-free verification) is production work with lead time (verify current
   requirements) and is not demo-blocking.
10. The contract's error taxonomy and client behavior per code (Requirement 12.5/12.6) SHALL be
    implemented exactly; unknown codes are treated as retryable once, then `failed`.

## Requirement 15: Cost and abuse controls

**Priority:** Important

**User story:** As the team, I want the SMS feature to be unable to run up a bill or be used
to spam people.

### Acceptance Criteria

1. Per request: **≤ 3 recipients**; per recipient: one message per kind per `crashEventId`.
2. The backend SHALL enforce, with documented defaults in the contract: a per-user daily cap
   on real alerts; a tighter per-user daily cap on test/intro/drill messages; a cap on **new
   distinct recipients** per user per day; and a **per-recipient (hash) cap across all users**
   to protect a third party from being spammed.
3. The backend SHALL accept only the fixed templates with variable fields and a sanitized
   rider label (≤ 20 chars, restricted charset); no arbitrary text, no URLs from the client.
4. There SHALL be a **global kill switch** (config flag) that makes `send-crash-alert` return
   `service_disabled` immediately; the client SHALL treat it as non-retryable and go to the
   composer fallback.
5. The provider account SHALL have a **spend cap / usage alert** and geo-permissions limited
   to US/CA.
6. The client SHALL mirror the caps it can know about (max 3 contacts, test cooldown) to give
   friendly errors before a request, but SHALL treat the backend as authoritative.
7. Anonymous accounts are cheap to mint; the contract documents the residual risk and the
   production hardening options (App Attest / DeviceCheck, CAPTCHA) as follow-ups.

## Requirement 16: Privacy, data handling, and network invariants

**Priority:** Demo-critical

**User story:** As a rider, I want to trust where my contacts' numbers and my location go.

### Acceptance Criteria

1. Emergency contacts SHALL live on the device only (Req 2.7). They are transmitted only to
   the crash-alert backend, over TLS, when an intro, test, drill, alert, or all-clear is sent.
2. The MVP invariant "while cloud sync is disabled the app makes no network requests"
   (MVP Req 9.2) is amended to: **WHILE neither ride sync (MVP Req 12) NOR crash alerts is
   enabled THE app SHALL make no network requests.** WHILE crash alerts are enabled THE
   app SHALL make network requests only for: anonymous sign-in/refresh for the crash-alert
   account, intro/test/drill/alert/all-clear sends, and status polling for an existing
   `crashEventId`. Connectivity monitoring (`NWPathMonitor`) generates no traffic.
3. Network code SHALL live only in `Services/Sync` (ride sync) and `Services/Notification`
   (crash alerts), enforced by `scripts/privacy-check.sh` (updated by a task in this spec).
   No analytics or tracking SDKs; the pinned Supabase client remains the only networking
   dependency.
4. Raw camera video and frames SHALL never leave the device; footage references are local.
5. Crash alert location is **precise and not privacy-zone trimmed** (a contact needs it); this
   SHALL be stated in the consent screen. Ride-sync privacy zones (MVP Req 12.5) are unaffected.
6. The backend SHALL NOT persist plaintext numbers, message bodies, or coordinates; audit rows
   (hashed number, last 2 digits, status, timestamps, template version, location *status*
   only) SHALL be retained for a documented window (default **30 days**) and then purged.
   Provider-side retention of message logs SHALL be minimized and documented (verify provider
   settings).
7. The rider SHALL be able to delete contacts, consent, and local crash records at any time.
   A remote "delete my crash audit rows" action SHALL be available (rider-scoped, RLS), noting
   that rate-limit counters are separate and contain no PII.
8. Usage-description strings: no new Info.plist permission strings are required for contacts
   (system picker) or SMS composer; the notification permission prompt SHALL have an honest
   in-app pre-explanation.
9. `privacy.md` SHALL contain an "Emergency contacts and crash alerts" section (updated by this
   job) and `product.md` SHALL list this as an opt-in post-MVP safety feature.

## Requirement 17: Emergency services

**Priority:** Demo-critical

**User story:** As a rider, I want to be able to call for help myself, and I never want the
app to call emergency services without my action.

### Acceptance Criteria

1. The system SHALL NOT automatically call, text, or otherwise contact emergency services
   under any state or error condition. This SHALL be enforced by (a) design: no code path in
   the workflow layers references a call API, (b) a privacy-check rule that flags `tel:` /
   `telprompt:` outside `Features/Emergency/`, and (c) a unit test with a recording fake.
2. The countdown screen and the post-send status screen SHALL include a clearly labeled,
   secondary **"Call 911"** button that the rider must tap; iOS shows its own call
   confirmation (verify). It SHALL be visually and spatially separated from "I'm OK — Cancel".
3. The "Call 911" button SHALL be **hidden or replaced by an inert "Demo" label for drills**
   to avoid an accidental real 911 call during the demo.
4. Contacts' message text SHALL say "consider calling emergency services" and SHALL NOT claim
   that emergency services have been notified.

## Requirement 18: Accessibility and design system

**Priority:** Important

**User story:** As any rider, I want the emergency screens to be usable under stress and with
assistive technology.

### Acceptance Criteria

1. Emergency screens SHALL use the existing `Theme` tokens and shared components; the Alert
   red and Ink/Mist pairings SHALL meet WCAG AA contrast (4.5:1; 7:1 for the large countdown
   numeral) — verify with the Accessibility Inspector.
2. Primary emergency controls SHALL be ≥ 60 pt; "I'm OK — Cancel" ≥ 80 pt (Req 8.3).
3. State SHALL be conveyed by icon + text; the countdown number SHALL be exposed to VoiceOver
   with periodic announcements (at start, every 10 s, final 5 s) and a modal accessibility trait
   so focus stays on the takeover.
4. The countdown SHALL respect Reduce Motion, Increase Contrast, and Dynamic Type (the large
   numeral uses a fixed scale like ride metrics; surrounding text scales).
5. Setup screens (contacts, consent, test) SHALL be fully operable with VoiceOver and Dynamic
   Type at accessibility sizes.
6. Home and the active-ride screen SHALL show a small "Crash alerts on/off" state chip
   (icon + text) when the feature is set up, without adding a fourth number to the ride screen.

## Requirement 19: Testing, simulation, and demo path

**Priority:** Demo-critical

**User story:** As the team, I want every safety-critical behavior verified without crashing a
bike, including the live demo.

### Acceptance Criteria

1. The system SHALL be built test-first with fakes: `FakeCrashDetector`, `TestClock`,
   `FakeCrashNotifier` (scriptable success, failure per code, timeout, delayed delivery-status),
   `FakeLocationTracker`, `FakeConnectivityMonitor`, `FakeCountdownFeedback`,
   in-memory contact/consent/record stores, `FakeFootageBuffer`.
2. **False positives:** unit tests SHALL show that a detector signal during a disarmed state, a
   signal during the suppression window, a signal for a second event during an active event,
   and a rider cancel all result in **zero** notifier calls.
3. **Countdown cancellation:** tests SHALL cover cancel at t=0, mid-countdown, at the last
   second, and at the deadline boundary (cancel at exactly the deadline loses to expiry as
   specified), including state, reason, feedback stop, and notification cancel.
4. **Unavailable GPS:** tests SHALL cover no fix ever, stale fix, accuracy too poor, and GPS
   loss during countdown; the alert is still sent with the right wording.
5. **Lost connectivity:** tests SHALL cover offline at expiry, connectivity returning inside and
   outside the stale limit, flapping connectivity, and cancel while queued.
6. **Duplicate notifications:** tests SHALL cover double detector signal, double tap on "Send
   now", relaunch during `sending`, retry after timeout with the same `crashEventId`, and a
   backend `deduplicated` response, all asserting **at most one** notifier send per event.
7. **Backend failures:** tests SHALL cover each error code in the contract (retryable and not),
   timeout, malformed response, partial per-recipient failure, and provider `undelivered`
   after `sent`.
8. The pure message builder SHALL have golden-string tests for every case in Appendix A of the
   contract, plus GSM-7 sanitization, segment counting, and length-cap tests.
9. A **Simulate crash** control SHALL exist in Settings → Crash alerts, visible only when an
   explicit "Developer / demo tools" toggle is on, that injects a drill signal through the real
   workflow with the real notifier (so judges see the real flow without a crash). Drills are
   labeled in messages and in the log, do not consume the real-alert cap, and are limited by the
   test/drill quota.
10. A **manual QA checklist** (`manual-qa.md` in this spec folder, created by a task) SHALL
    cover on-device checks that unit tests cannot: audio with the silent switch on,
    haptics, screen-awake behavior, VoiceOver, real composer fallback, airplane mode, and
    an end-to-end trial-SMS run.
11. Everything runs without a network except the explicit on-device SMS trial run.

## Requirement 20: All-clear follow-up

**Priority:** Stretch

**User story:** As a rider whose alert was sent but who is actually fine, I want to quickly
tell my contacts so they don't worry.

### Acceptance Criteria

1. After a `crash_alert` is `sent`, the status screen SHALL offer **"Tell contacts I'm OK"**,
   which sends an `all_clear` message via the same backend path to the same recipients.
2. The all-clear SHALL be idempotent per `crashEventId` and kind, share the test/drill quota
   or a dedicated small quota, and SHALL be recorded in the same record.
3. The all-clear text SHALL NOT claim anything about injuries beyond "says they are OK".

## Requirement 21: Future seams and follow-ups

**Priority:** Future-seam

**User story:** As the team, I want the next steps captured so v1 doesn't paint us into a
corner.

### Acceptance Criteria

1. **Critical Alerts** (bypass Do Not Disturb/silent) need Apple's entitlement approval (an
   application to Apple, intended for health/safety apps); v1 SHALL use normal/time-sensitive
   notifications; the design SHALL keep the notification path ready to switch with a one-
   property change after approval.
2. **Background location** (`location` mode) to keep the process alive is a separate owner
   decision with battery/privacy cost and App Review implications.
3. **Server-side countdown** (design option (d)) — the client reports the crash and the
   backend holds a deadline — is documented as a v2 option with the false-alert trade-off.
4. A **better crash detector** (including camera-assisted cues from the detection teammate)
   SHALL plug in behind `CrashDetector` without workflow changes.
5. A real `FootageBuffer` SHALL plug in behind its protocol and obey Requirement 7.
6. Additional regions, App Attest hardening, and provider sender registration are production
   follow-ups.

---

## Non-functional notes

- **Safety-critical honesty:** every screen on this path is reviewed against Requirement 1.
- **Never block a ride:** all crash-workflow failures degrade to "nothing happens" or a
  prompt; none stops GPS recording (MVP "Never block a ride").
- **Battery:** the experimental motion detector samples only while armed; thresholds, sample
  rate, and battery impact are measured before it is enabled by default (it never is by default).
- **Testability:** pure functions (message builder, state transition function, arming rule,
  phone normalization) carry the logic; the coordinator composes them with injected seams.
- **Revisability:** SMS provider, detector, footage buffer, and notification mechanism are
  behind protocols and can be swapped with localized change.

## Traceability

Every acceptance criterion is mapped to one or more tasks in `tasks.md` via `_Requirements:_`
annotations; `design.md` references requirement numbers where it explains how each is
satisfied. Backend tasks (Role C) cite the same requirement numbers and the contract sections.
