# Design — Whoosh Emergency Contact and Crash Response

**Status: APPROVED by the iOS owner (October 24, 2026)** with the recommended answers to O1–O10
(see "Owner resolution" under Decisions). This document contains **no source code** by design:
the owner required requirements, design, and tasks to be reviewed before any implementation. Types, protocols, and state machines are described in tables and diagrams;
the code is written later, task by task, test-first (`tasks.md`).

## Overview

The feature adds a small, isolated subsystem next to the finished ride-recording MVP. It
follows the same architecture: MVVM + service protocols, the injected `Clock`, SwiftData
repositories, explicit state machines, fakes for every framework touchpoint, and a composition
root that wires concrete types. The ride engine (`RideSessionViewModel`) is **not modified**; the
crash subsystem observes it through a read-only context.

```
 CrashDetector ──signal──▶ CrashResponseCoordinator ──▶ CrashNotifier ──▶ Edge Function ──▶ SMS provider
 (Noop / Simulator /        (@Observable, MainActor)      (Supabase impl)    (Role C)          (Twilio, etc.)
  experimental Motion)            │     ▲
                                   │     └── pure reducer: state × event → state × effects
                                   ├──▶ CountdownFeedback (audio + speech + haptics)
                                   ├──▶ CrashNotificationScheduler (time-sensitive local notification)
                                   ├──▶ FootageBuffer (Noop now; local-only)
                                   ├──▶ CrashAlertRepository (SwiftData record + attempts)
                                   └──▶ ConnectivityMonitor (NWPath)
 RideContext (read-only) ◀── RideSessionBridge ◀── RideSessionViewModel (unchanged internals)
```

### Revisability note

SMS provider, detector, footage buffer, notification mechanism, audio output, and connectivity
source are each behind a protocol and can be swapped with localized change. The decisions below
are recommendations for owner review; items marked **OPEN** need an owner decision before the
affected tasks start.

---

## iOS capability investigation

**Method and honesty note.** These findings record what is known and what the owner asked to be
re-checked. During this job the web-search tools were unavailable, so **nothing below was
re-verified against live Apple or provider documentation**. Items tagged
**Verify** MUST be checked against current Apple/provider docs before any task relies on them.
Items tagged **Established** reflect long-standing, well-documented platform behavior but are
still confirmed during the relevant task's device check.

| # | Question | Finding | Status |
| - | -------- | ------- | ------ |
| 1 | Can a third-party app send an SMS silently from the user's number? | **No.** `MFMessageComposeViewController` always presents a sheet and requires the rider to tap Send; the app cannot send programmatically or in the background and only learns "sent/cancelled/failed" (queued by Messages, not delivered). Apple has documented `TelephonyMessagingKit` for eligible default-carrier-messaging apps only — treat as **unavailable** to Whoosh. Consequence: automatic notification **requires a backend SMS provider** sending from a provider number with the rider's label in the text. The composer is only a user-initiated **fallback**. | Composer behavior: Established. TelephonyMessagingKit eligibility: **Verify against current Apple docs before relying on it** (we rely on it being unavailable). |
| 2 | Is Apple's system Crash Detection (iPhone 14+/Apple Watch) exposed to apps? | **Not as a public API to third parties** (it drives Emergency SOS by the OS). Whoosh cannot subscribe to it. Whoosh defines its own `CrashDetector` seam: Noop, a debug simulator, and an experimental heuristic over public Core Motion data (accelerometer/device motion; the public sensor range is limited — roughly low-g relative to a real impact — so a hard impact may saturate or be clipped) combined with a GPS speed-drop and a post-impact stillness check. Expect many false positives (potholes, drops, bumping or removing the phone, a phone falling from a mount) and false negatives. The countdown-and-cancel UX is the mitigation. Copy never claims reliable detection. | **Verify** (API availability and the accelerometer's public range). |
| 3 | What can run without foreground interaction? | The countdown timer and the network send need the process running. The MVP records in the **foreground with the screen on** (idle timer disabled), where timers, audio, haptics, and network all work. If the app is backgrounded or suspended, timers and network are not reliable; a *scheduled local notification* is delivered by the OS even when the app is suspended but can only prompt, not send. A `location` background mode can keep the process alive but has battery, privacy, and App Review cost. See "Execution model" below. | Established; background-mode review implications **Verify**. |
| 4 | Critical Alerts? | Critical Alerts (bypass Do Not Disturb and the mute switch) require Apple's entitlement approval (`com.apple.developer.usernotifications.critical-alerts`, requested from Apple; intended for health/safety apps). The code change after approval is one notification-content property. v1 uses normal/**time-sensitive** notifications plus in-app audio and haptics; critical alerts are a follow-up requiring an Apple application. | **Verify** (current entitlement process and criteria). |
| 5 | In-app audio vs. the silent switch | The audible countdown plays through `AVAudioSession` with the **playback** category, which is documented to play regardless of the ring/silent switch while the app is foregrounded and the session is active. Volume cannot be forced; the rider's volume applies. Audio must **never** be the only signal: visual and haptic accompany it. Speech via `AVSpeechSynthesizer` works through the same session. | **Verify on device** (task device check) |
| 6 | Time-sensitive local notifications | Require notification authorization and the Time Sensitive Notifications capability/entitlement; `interruptionLevel = timeSensitive` can break through Focus/scheduled summaries unless the user has disabled it. The user can still disable notifications, so this is a **backup**, not a guarantee. | **Verify** (entitlement name and setup) |
| 7 | Contact picking | `CNContactPickerViewController` runs out-of-process and needs **no Contacts permission** for the contacts the user picks. Manual entry is the alternative. | **Verify** (behavior under limited-contact-access in the latest iOS) |
| 8 | Composer fallback availability | `MFMessageComposeViewController.canSendText()` is false on devices that cannot send SMS (iPad, simulator, no SIM/Messages). Present it only when true; else offer Copy/Share. The composer must be presented from the foreground app after a user action. | Established |
| 9 | Keychain vs. app deletion | Keychain items can **survive app deletion** and reinstall. A fresh-install marker (stored in app-container storage, which *is* deleted) lets the app purge orphaned contact items on first launch. `AfterFirstUnlockThisDeviceOnly` keeps the data off backups/other devices and readable when the phone is locked after first unlock. | **Verify** |
| 10 | `tel:` behavior | `UIApplication.open` on a `tel:` URL triggers the system's own call confirmation. Only used from a rider-tapped button. | **Verify** (confirmation behavior on current iOS) |
| 11 | Connectivity | `NWPathMonitor` reports path status without generating traffic. "Satisfied" does **not** prove our backend is reachable; real request outcomes are ground truth, `NWPath` is only a trigger to retry sooner. | Established |
| 12 | Core Motion permission | Raw accelerometer/device-motion streaming is not gated by a permission prompt (motion *activity* APIs are); no `NSMotionUsageDescription` is expected for the heuristic. | **Verify** |
| 13 | App Review | Safety/emergency-adjacent apps get extra scrutiny; claims of guaranteed detection or help are a rejection risk, and automatic sending of messages needs clear consent. Our honesty rules already align. | **Verify** (current guidelines) |
| 14 | SMS provider specifics (Twilio as the example) | Status callbacks deliver `MessageSid`, `MessageStatus`, and `ErrorCode` **asynchronously, possibly out of order and more than once** → handlers must be idempotent and statuses monotonic. Webhooks carry an `X-Twilio-Signature` that must be validated. US application-to-person messaging needs sender registration (10DLC campaign or toll-free verification) with real lead time. A **trial account** can message only verified recipient numbers and prefixes messages. For the hackathon: trial route; registration is production work. Spend limits and per-user rate limits are part of cost control. STOP keywords are handled by the provider per sender number; a later send to an opted-out number returns an error (surfaced to the rider as "opted out"). | **Verify** (current registration rules, error codes, trial behavior) |
| 15 | Provider-side data | Even if our backend persists no numbers or bodies, the provider's own message logs may. Provider retention/redaction settings must be reviewed and documented by Role C. | **Verify** |

### Execution model — options and recommendation (OPEN decision O1)

| Option | How it works | Pros | Cons |
| ------ | ------------ | ---- | ---- |
| (a) Foreground, screen-awake, client-driven countdown (MVP behavior) | App must be open with the ride active; timers, audio, haptics, send all run in-process | Zero new capability; most reliable *when it applies*; matches the demo | Fails if the app is closed, the phone locks, iOS suspends, or the phone is destroyed/off after impact |
| (b) `location` background mode | Process kept alive by background location; countdown/send continue when backgrounded | Works with the phone in a pocket/bag | Battery/privacy cost; App Review justification; Always-authorization rules; not in the MVP's demo path |
| (c) Time-sensitive local notification at the deadline | OS shows a prompt at the deadline even if the app is suspended | Cheap; helps the rider notice; no background mode | Cannot send or cancel anything by itself; can be disabled; adds a permission |
| (d) Server-side countdown | Client reports the crash; the backend holds a deadline and sends unless cancelled | Most robust to a dead/offline phone after impact | Highest false-alert risk if the cancel can't reach the server; new backend timers; more cost and trust surface |

**Recommendation for v1: (a) + (c).** Document the limitation in consent and Settings. **(d) is
a documented v2 option** (Requirement 21). **(b) stays a separate owner decision.** This is
OPEN for owner review (O1).

---

## Architecture and layering

### Layering additions

| Layer / folder | Contents | Knows about | Must NOT import |
| -------------- | -------- | ----------- | --------------- |
| `Models/` | `CrashEvent`, `CrashEventState`, countdown-outcome and cancel-reason enums, `EmergencyContact`, `ContactVerification`, `ConsentRecord`, `CrashAlertSettings`, `CountdownState`, `LocationSnapshot`, `CrashAlertRecord`, `AlertAttempt`, `CrashResponseTuning`, `CrashMessageKind` (named to avoid clashing with the existing `AlertKind` in `Services/Alerts`) | Foundation | everything else |
| `Metrics/` (Foundation-only, pure) | `CrashMessageBuilder`, `E164Normalizer`, `CrashStateMachine` (reducer), `CrashArming`, `LocationSnapshotPolicy`, `RetryPolicy`, `GSM7Sanitizer` | Models | UI, any framework |
| `Services/Crash/` | `CrashDetector` protocol, `NoopCrashDetector`, `FakeCrashDetector`, `DebugCrashSimulator`, `MotionCrashDetector` (experimental, stretch; the only place that imports Core Motion) | Models | SwiftUI, other services' concrete types |
| `Services/Notification/` | `CrashNotifier` protocol, `NoopCrashNotifier`, `FakeCrashNotifier`, `SupabaseCrashNotifier` (the only crash code that touches the network), `CrashNotificationScheduler` protocol + `UNUserNotificationCenter` impl + fake | Models | SwiftUI |
| `Services/Contacts/` | `EmergencyContactStore` protocol, `KeychainEmergencyContactStore` (the only place using Keychain APIs), `InMemoryEmergencyContactStore`, `ConsentStore` (protocol + UserDefaults impl + fake) | Models | SwiftUI |
| `Services/Network/` | `ConnectivityMonitor` protocol, `NWPathConnectivityMonitor`, `FakeConnectivityMonitor`. Makes no requests. | Models | `URLSession` |
| `Services/Footage/` | `FootageBuffer` protocol, `NoopFootageBuffer`, `FakeFootageBuffer` (real buffer is a future task; may use asset-writer APIs, never a capture session) | Models | camera capture |
| `Services/Alerts/` | adds `CountdownFeedback` protocol, `SystemCountdownFeedback` (AVAudioSession + speech + haptics), `NoopCountdownFeedback`, `FakeCountdownFeedback`. The existing `AlertManager` seam is left unchanged. | Models | SwiftUI |
| `Services/Persistence/` | adds `CrashAlertRepository` protocol, `SwiftDataCrashAlertRepository`, `InMemoryCrashAlertRepository`, `CrashAlertRecordEntity` (`@Model`) | Models | SwiftUI |
| `Features/Emergency/` | `EmergencySetupView(+VM)`, `ContactEditorView(+VM)`, `ConsentView(+VM)`, `TestAlertView(+VM)`, `CrashCountdownView`, `CrashAlertStatusView`, `CrashAlertLogView(+VM)`, `EmergencyCallButton`, root `CrashCountdownHost` | ViewModels, Theme | CoreLocation, SwiftData, services' concrete types |
| `Features/Emergency/` (coordination) | `CrashResponseCoordinator` (`@Observable`, MainActor), `RideSessionBridge`, `EmergencySetupViewModel`, etc. | Models, Metrics, service protocols | concrete services |
| `Support/Representables/` | `ContactPickerView` (ContactsUI) and `MessageComposeView` (MessageUI) UIKit wrappers | UIKit | — |
| `App/` | composition root additions in `AppEnvironment`; root host in `WhooshApp` | everything | — |

Folder names follow the owner's brief (`Services/Network/` holds only the path monitor and is
unrelated to the "network code only in Sync/Notification" privacy rule, which keys on API
names such as `URLSession`).

### File layout (proposed)

```
Whoosh/
  Models/            CrashEvent… (see table)
  Metrics/           CrashMessageBuilder · E164Normalizer · CrashStateMachine · CrashArming …
  Services/
    Crash/           CrashDetector · Noop · Fake · DebugCrashSimulator · MotionCrashDetector (stretch)
    Notification/    CrashNotifier · Noop · Fake · SupabaseCrashNotifier · CrashNotificationScheduler …
    Contacts/        EmergencyContactStore · Keychain impl · InMemory · ConsentStore
    Network/         ConnectivityMonitor · NWPath impl · Fake
    Footage/         FootageBuffer · Noop · Fake
    Alerts/          (existing) + CountdownFeedback · System · Noop · Fake
    Persistence/     (existing) + CrashAlertRepository · SwiftData · InMemory
  Features/Emergency/ views, view models, coordinator, bridge
  Support/Representables/ ContactPickerView · MessageComposeView
WhooshTests/         Fakes and tests for every row in this document
```

### Dependency rule

Same as the MVP: views → view models → service **protocols**; concrete types are injected at the
composition root. The coordinator receives the `Clock`, an ID factory, and all seams, so every
behavior is deterministic in tests.

---

## Domain models (described, not coded)

### CrashResponseTuning (all constants in one place)

| Constant | Default | Range / note |
| -------- | ------- | ------------ |
| Countdown length | 30 s | clamped to 15–60 s |
| Suppression window | 120 s | after cancel or send |
| Max automatic alerts sent per ride | 1 | counts *sent* only; cancelled countdowns don't consume it |
| Max contacts | 3 | cost/abuse control |
| Stale limit | 30 min | from detection time; after it, never auto-send |
| Retry backoff | 5, 15, 30, 60 s, then every 60 s | max 6 attempts for backend failures |
| Max location age | 30 min | older ⇒ treated as unavailable |
| "Current" fix age | ≤ 10 s | otherwise "last known" |
| Request timeout | 10 s | per notifier call |
| Status poll schedule | immediately, every 5 s for 60 s, then every 15 s up to 10 min | foreground only |
| Local record retention | 90 days | rider can delete sooner |
| Max rider label length | 20 | GSM-7-safe charset |
| Test/intro cooldown (client mirror) | 60 s per contact | backend authoritative |

### Entities

| Entity | Fields (summary) | Storage |
| ------ | ---------------- | ------- |
| `EmergencyContact` | `id` (UUID), `label`, `e164`, `verification` (`unverified`/`introSent`/`reachable`/`undeliverable`/`optedOut`), `lastStatusAt` | Keychain (single encoded blob; never SwiftData/UserDefaults) |
| `CrashAlertSettings` | `enabled`, `riderLabel`, `countdownSeconds?`, `developerToolsEnabled`, `freshInstallMarker` | `UserDefaults` (no contact data) |
| `ConsentRecord` | `version`, `acceptedAt`, `acknowledgedNotGuaranteed` | `ConsentStore` (UserDefaults JSON) |
| `LocationSnapshot` | `latitude?`, `longitude?`, `horizontalAccuracy?`, `fixTime?`, `status` (`current`/`lastKnown`/`unavailable`); `age(at:)` is derived | inside the record |
| `CountdownState` | `deadline`, `totalSeconds`; `remaining(at:)` is derived — **absolute deadline**, never a decrementing counter | inside the persisted event |
| `CrashEvent` | `id` (= `crashEventId`), `detectedAt`, `utcOffsetMinutes`, `isDrill`, `source`, `confidence`, `rideId?`, `state`, `countdown?`, `suppressedUntil?`, `locationAtDetection`, `footageRef?`, `outcome?` | persisted via the record |
| `CrashAlertRecord` | event fields + `locationAtSend?`, `templateVersion`, `renderedText`, `attempts: [AlertAttempt]`, timestamps | SwiftData `@Model` entity behind `CrashAlertRepository` |
| `AlertAttempt` | `recipientRef` (contact UUID), `labelSnapshot`, `maskedNumber` (last 2 digits), `kind`, `status`, `whooshErrorCode?`, `providerErrorCode?`, `attemptedAt`, `updatedAt` | child of the record (encoded) |
| `CrashMessageKind` | `crash_alert`, `drill`, `test`, `intro`, `all_clear` | Foundation enum |

### Location snapshot policy (Requirement 7)

1. At detection: take the freshest **accepted** route point from `RideContext` (the MVP already
   filters by accuracy ≤ 30 m and plausible jumps). If none exists, or it is older than the max
   location age, the snapshot is `unavailable`.
2. At send: re-read `RideContext`; if a newer accepted fix exists, use it for the message
   (age relative to send time) and store both snapshots.
3. Age ≤ 10 s ⇒ `current`; otherwise `lastKnown` with age and accuracy.
4. GPS loss is the common case after a crash; "last known location, 45 s old, +/-30 m" is
   expected and acceptable.
5. We do **not** start a new location request at crash time in v1 (the `LocationTracking`
   protocol has no one-shot call and the ride tracker already streams). A one-shot fix is a
   possible follow-up.

---

## Service protocols (described, not coded)

| Protocol | Members (summary) | Implementations |
| -------- | ----------------- | --------------- |
| `CrashDetector` | `onSignal(timestamp, confidence, source, isDrill)` callback on the main actor; `start()` / `stop()`; on-device; never blocks or stops recording | `NoopCrashDetector`, `FakeCrashDetector`, `DebugCrashSimulator`, `MotionCrashDetector` (stretch) |
| `RideContext` (read-only) | `isRideActive` and ride state (`recording`/`signalLost` vs. other), `latestAcceptedFix` (coordinates, accuracy, time) or none, `currentRideID?` | `RideSessionBridge` over `RideSessionViewModel`; `FakeRideContext` |
| `CrashNotifier` | `send(request) async` → per-recipient results or a typed error; `status(crashEventId) async` → per-recipient statuses. Errors are classified `retryable` or `nonRetryable` with a Whoosh error code. **No parameter can carry footage or arbitrary text.** | `NoopCrashNotifier`, `FakeCrashNotifier`, `SupabaseCrashNotifier` |
| `ConnectivityMonitor` | `isOnline`, `onChange` | `NWPathConnectivityMonitor`, `FakeConnectivityMonitor` |
| `CountdownFeedback` | `begin(totalSeconds)`, `tick(remaining)`, `end(reason)` — audio, speech, haptics; idempotent `end` | `SystemCountdownFeedback`, `NoopCountdownFeedback`, `FakeCountdownFeedback` |
| `CrashNotificationScheduler` | `scheduleDeadlinePrompt(eventId, at)`, `scheduleNotSentNotice(eventId)`, `cancel(eventId)`, `requestAuthorizationIfNeeded()` | `UNUserNotificationCenter` impl, `FakeCrashNotificationScheduler` |
| `FootageBuffer` | `preserve(eventId, around: detectedAt)` → local reference or none; `delete(reference)` | `NoopFootageBuffer` (returns none), `FakeFootageBuffer` |
| `EmergencyContactStore` | `contacts()`, `add`, `update`, `remove`, `removeAll`, `purgeOrphansIfFreshInstall()`; max-3 enforced by the caller and the store | Keychain, InMemory |
| `ConsentStore` | `current()`, `record(version, acknowledged)`, `revoke()` | UserDefaults, InMemory |
| `CrashAlertRepository` | `save(record)`, `all()` (most recent first), `record(id)`, `delete(id)`, `deleteAll()`, `purge(olderThan:)`, `activeEvent()` for relaunch recovery | SwiftData, InMemory |

All protocols are `Sendable`-aware where they cross actors; heavy work (network, motion
processing) is explicitly off the main actor, with callbacks delivered on the main actor.

---

## Pure functions (the testable core)

| Function | Inputs → output | Notes |
| -------- | ---------------- | ----- |
| `E164Normalizer` | raw string → normalized E.164 or typed error | v1: NANP (`+1`) only; strips punctuation; rejects invalid area/exchange codes and N11/premium-style patterns |
| `GSM7Sanitizer` | string → GSM-7-safe string | replaces smart quotes/dashes, strips unsupported characters, collapses whitespace; used for the rider label |
| `CrashMessageBuilder` | kind, rider label, detectedAt, UTC offset, location snapshot, delayedSeconds, template version → text, character count, segment count | Uses Appendix A of `crash-alert-contract.md` as golden cases; drops the Google Maps line if > 612 chars |
| `LocationSnapshotPolicy` | accepted fix?, now, tuning → snapshot | `current` / `lastKnown` / `unavailable` |
| `CrashArming` | ride state, consent current, acknowledged, riderLabel present, reachable contacts count, enabled → armed? | Armed only while `recording`/`signalLost`; disarmed in `paused` |
| `RetryPolicy` | attempt number → delay; `isWithinStaleLimit(detectedAt, now)` | |
| `CrashStateMachine` | (state, event, context) → (state, [effects]) | Context carries `now`, deadline, consent/armed flags, per-ride sent count, `suppressedUntil`. Effects are data (e.g., start feedback, schedule timer, call notifier, persist) executed by the coordinator |

---

## Crash event state machine

### Diagram

```
                       signal [armed ∧ not suppressed ∧ cap ok]
   idle / resting ───────────────────────────────────────────────▶ detected
        ▲                                                              │ evidence captured
        │                                                              ▼
   suppression ended                                         ┌──── countdown(deadline) ────┐
        │                                  cancel (single tap)│     │ deadline / "Send now"  │
        │                                                      ▼     ▼                        │
        │                                                  cancelled  sending ◀───────────────┘
        │                                                              │
        │          ┌─────────────── offline at dispatch ───────────────┤
        │          ▼                                                   │ result
        │     queuedOffline ─ online & within stale ─▶ sending         ├─▶ sent ──▶ (poll statuses)
        │          │  └ stale limit ─▶ stale                           ├─▶ retry wait (stay in sending)
        │          └ cancel ─▶ cancelled                               └─▶ failed ─▶ fallbackPrompted
        │
   relaunch: countdown (deadline passed) ─▶ recoveryPrompted ─ Send now ─▶ sending / I'm OK ─▶ cancelled
```

`cancelled`, `sent`, `stale`, `fallbackPrompted` (after resolution) are **resting** states: the
persisted event stays for the log, and the coordinator returns to `idle` for new signals once the
suppression window has passed.

### Transition table (every row is a unit test against the pure reducer)

| #  | From | Event | Guard | To | Effects |
| -- | ---- | ----- | ----- | -- | ------- |
| 1  | idle / resting | detector signal | armed ∧ not suppressed ∧ sent-count < cap | detected | new `crashEventId`, capture timestamp + UTC offset, location snapshot, `footage.preserve`, persist |
| 2  | idle / resting | detector signal | not armed (ride/consent/label/contacts) | same | ignore; log `ignored(notArmed)` |
| 3  | resting | detector signal | now < `suppressedUntil` | same | ignore; log `suppressed` |
| 4  | resting | detector signal | sent-count ≥ cap | same | ignore; log `capReached` |
| 5  | detected | evidence captured | — | countdown | deadline = now + N s; start feedback; schedule backup notification; keep screen awake; present takeover; persist |
| 6  | detected, countdown, sending, queuedOffline, fallbackPrompted, recoveryPrompted | detector signal | — | same | ignore; log `eventActive` |
| 7  | countdown | rider cancel | now < deadline | cancelled | stop feedback; cancel timer + notification; outcome `riderCancelled`; `suppressedUntil` = now + window; persist |
| 8  | countdown | deadline reached | — | sending | stop feedback; outcome `expired`; dispatch send |
| 9  | countdown | rider cancel | now ≥ deadline (expiry not yet processed) | sending | process expiry first (cancel loses a tie; deterministic) |
| 10 | countdown | "Send now" | — | sending | outcome `sentNow`; dispatch send |
| 11 | countdown | consent revoked | — | cancelled | stop feedback; outcome `consentRevoked`; no send |
| 12 | sending | dispatch | offline | queuedOffline | persist; banner; "I'm OK — cancel" + composer actions; local not-sent notice |
| 13 | sending | notifier result | ≥ 1 recipient `queued`/`sent`/`delivered` | sent | persist attempts; per-ride sent count + 1; `suppressedUntil` = now + window; cancel backup notification; start status polling |
| 14 | sending | notifier error | non-retryable | failed → fallbackPrompted | persist; plain explanation; composer fallback; not-sent notice |
| 15 | sending | notifier error | retryable ∧ attempts left ∧ within stale limit | sending (retry scheduled) | schedule next backoff attempt; same `crashEventId` |
| 16 | sending | notifier error | retryable ∧ (attempts exhausted ∨ stale limit passed) | failed → fallbackPrompted | as row 14 |
| 17 | sending (retry wait, no request in flight) | rider "I'm OK" | — | cancelled | stop retries; suppression; outcome `riderCancelled` |
| 18 | sending (request in flight) | rider "I'm OK" | — | sending | not cancellable; offer "Tell contacts I'm OK" after `sent` instead |
| 19 | queuedOffline | connectivity restored ∨ retry timer | within stale limit | sending | recompute `delayedSeconds`; dispatch |
| 20 | queuedOffline | stale limit reached | — | stale | persist; notice + composer fallback + "Discard"; never auto-send |
| 21 | queuedOffline | rider "I'm OK" | — | cancelled | suppression; outcome `riderCancelled` |
| 22 | queuedOffline, sending (retry wait) | consent revoked | — | cancelled | stop; outcome `consentRevoked` |
| 23 | fallbackPrompted | composer opened / dismissed / discarded | — | fallbackPrompted (resting) | persist `fallbackAction` |
| 24 | sent | status poll update | — | sent | update attempts (monotonic) |
| 25 | sent | rider "Tell contacts I'm OK" (stretch) | — | sent | send `all_clear` for the same `crashEventId` |
| 26 | relaunch: countdown | app relaunched | deadline in the future | countdown | resume with remaining time; re-arm timer/feedback |
| 27 | relaunch: countdown | app relaunched | deadline passed | recoveryPrompted | prompt "Your app closed during a crash countdown — send the alert?" |
| 28 | recoveryPrompted | "Send now" | within stale limit | sending | delayed wording |
| 29 | recoveryPrompted | "I'm OK" / dismiss | — | cancelled | outcome `recoveryDismissed`; suppression |
| 30 | relaunch: sending | app relaunched | within stale limit | sending | resume with the same `crashEventId` (idempotent) |
| 31 | relaunch: queuedOffline | app relaunched | within stale limit | queuedOffline → sending when online | resume retries |
| 32 | relaunch: queuedOffline / sending | app relaunched | stale limit passed | stale | as row 20 |
| 33 | any resting | relaunch | — | same | nothing; no re-trigger |
| 34 | idle | cancel / send now / other intent | — | idle | no-op (undefined transitions are safe) |

Why the explicit **deadline** and the persisted state: a missed timer tick, a rebuilt view, a
backgrounding, or a relaunch can never extend a countdown or double-fire a send. The
`crashEventId` is generated once at detection and is the idempotency key on the wire (row 30).

### Duplicate-prevention layers (defense in depth)

1. Reducer rows 2–6: ignore signals while disarmed, suppressed, capped, or active.
2. One active event; the state is persisted on every transition (a relaunch cannot restart it).
3. The coordinator calls the notifier **at most once per event** for the initial send; retries
   reuse the same `crashEventId` and only follow a *retryable* failure with no acknowledgement.
4. The backend unique constraint on (`user_id`, `crash_event_id`, `recipient_hash`, `kind`)
   (contract) is the last line.
5. UI: "Send now" is disabled after the first tap; the reducer ignores repeats.

---

## Experimental motion detector (Stretch; Teammate B or the iOS owner)

Behind the same `CrashDetector` protocol; **disabled by default**; labeled experimental.

| Stage | Signal | Initial value (all in tuning; to be measured) |
| ----- | ------ | ---------------------------------------------- |
| 1. Impact candidate | Peak acceleration magnitude from device motion (accelerometer sample rate ~50 Hz), within the sensor's public range; saturation counts as strong evidence | threshold TBD from field data (low-g public range — **Verify**) |
| 2. Speed drop | GPS speed over the prior ~5 s ≥ 3 m/s (~7 mph) and < 1 m/s within 3 s after the impact candidate | requires known speed; unknown speed lowers confidence |
| 3. Post-impact stillness | Low variance of acceleration and rotation for ≥ 5 s inside a 10 s window | |
| 4. Combine | Weighted score → `confidence` in `0...1`; emit only if all three stages occur within a 15 s window and the score ≥ threshold | threshold TBD |
| Rate limit | At most one signal per suppression window (defense in depth with the reducer) | |

Known false positives (cannot be separated from a real crash by the phone alone): phone falling
from the mount at speed, a hard bump followed by a stop, placing the phone down after a drop.
Known false negatives: low-speed falls, impacts below the threshold, GPS speed unknown.

**Acceptance process (before it can be enabled even as an opt-in experiment):**
(1) pure signal-processing core tested against synthetic and recorded traces (test-first);
(2) a local-only debug log of candidate triggers during real rides (nothing uploaded);
(3) measure triggers per hour of riding, record in this document under "Measured results";
(4) owner sets the acceptance bar (OPEN O9) — nothing is claimed in copy until measured.

---

## Countdown, feedback, and UI

### Presentation

The takeover is a **root-level overlay** (`CrashCountdownHost` in `WhooshApp`, above the
`NavigationStack` and above the active-ride full-screen cover) so it works from Home (drills),
from the ride screen, and while the ride cover is up. It is modal for accessibility
(`accessibilityViewIsModal`-equivalent) and cannot be swiped away.

### Countdown screen (Requirement 8)

| Element | Spec |
| ------- | ---- |
| Background | Alert red `#D32F2F` with white/Mist text (contrast verified with the Accessibility Inspector; the numeral ≥ 7:1 target). Reduce Motion ⇒ static; otherwise at most one slow pulse per second (flashing-safe) |
| Headline | "Crash detected" with an icon (not color alone) |
| Numeral | Very large remaining seconds, tabular digits, fixed scale (like ride metrics) |
| Sentence | "Sending an alert to Mom and 1 other in N seconds." The label list is truncated to fit; text scales with Dynamic Type |
| Primary control | "I'm OK — Cancel", full width, ≥ 80 pt tall, bottom thumb zone, single tap |
| Secondary controls | "Send now" (away from Cancel); "Call 911" (manual; hidden for drills — replaced by an inert "Demo" tag) |
| Fine print | "Whoosh is not a guaranteed emergency service. It can't guarantee detection or delivery. It does not contact emergency services." |
| Audio | Spoken prompt at start ("Crash detected. Sending an alert in 30 seconds. Tap I'm OK to cancel."), a tone each second in the last 10 s, spoken final warning; `.playback` session, ducks others, released on end |
| Haptics | Warning pulse each second (foreground only) |
| VoiceOver | Modal; announce at start, every 10 s, and each of the last 5 s; Cancel is the first focus target |
| Screen | Idle timer disabled for the duration |

### Other screens

| Screen | Purpose |
| ------ | ------- |
| `EmergencySetupView` (hub; pushed from Settings → "Crash alerts") | Status (On/Off + why), rider label, contacts list with verification state, consent status/revoke, countdown length (stretch), "Send a test", "Crash alert log", developer/demo tools toggle |
| `ContactEditorView` | Pick from system picker or type name + number; inline validation errors; remove; verification state |
| `ConsentView` | Required reading in plain language (what is/isn't sent, how, not-a-guarantee, STOP, limits of foreground-only operation); renders the **exact message preview** from the builder; two controls (data-use consent + not-a-guarantee acknowledgement) |
| `TestAlertView` | Send intro/test to selected contacts; per-contact progress; plain failure reasons |
| `CrashAlertStatusView` | After send/fail/queue: per-contact status, banner for queued/stale/failed, composer fallback ("Tap to text <contact> now"), Copy/Share, "I'm OK — cancel alert" (queued only), "Tell contacts I'm OK" (stretch), manual "Call 911" |
| `CrashAlertLogView` | History of records with icon + text status, detail, delete one/all |
| Home / ride screen | Small "Crash alerts on/off" chip (icon + text) when set up; no extra number on the ride screen |

### Integration with `RideSessionViewModel` (Requirement 13.1)

The ride engine already exposes `rideState` and `points` as observable state. A
`RideSessionBridge` owned by the composition root observes them (Observation tracking) and
publishes a read-only `RideContext`: ride active/not, the freshest accepted fix, and (if the
owner approves a one-line read-only accessor, OPEN O7) the current ride id. The bridge feeds
`CrashArming` and the detector start/stop. If the owner prefers, the alternative is a tiny
additive `onRideEvent` closure on the view model; this design chooses the bridge to leave the
ride engine untouched and fully test it with the existing fakes.

The ride can still be stopped with hold-to-stop while a countdown is not running; **while the
takeover is up the ride screen is covered**, and ending the ride does not cancel an in-flight
crash event (the event is independent of ride state once `detected`).

---

## Message template

Exact text, pure builder, golden tests (Appendix A of the contract is the source of truth for
both iOS and the backend). Summary of `crash_alert` v1:

```
WHOOSH ALERT: <label> may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: <Day Mon D, h:mm AM/PM> (UTC<±h[:mm]>)[. Message delayed by N min.]
<location block>
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
```

Location block variants: `Location (+/-A m):` + Apple Maps link + Google Maps link (current
fix); `Last known location (<age>, +/-A m):` + both links; or `Location unavailable.`
Typical length 465–514 characters (4 segments); worst case in the golden set 540. The
builder reports segment count and enforces ≤ 612 characters; ASCII/GSM-7 only.

`drill` begins "WHOOSH DEMO - NOT REAL"; `test`, `intro`, `all_clear` are short (2 segments).
Why Apple **and** Google links: a contact may not use an iPhone.

---

## Fallback matrix (Requirement 12)

| Condition | Detection | Automatic behavior | Rider-visible behavior | Test |
| --------- | --------- | ------------------ | ---------------------- | ---- |
| No network at expiry | `ConnectivityMonitor.isOnline == false` or request fails with no connection | `queuedOffline`; retry on restore and backoff; send with "delayed" wording within the stale limit | Banner "Alert not sent yet", "I'm OK — cancel alert", "Tap to text <contact> now", local not-sent notice | F-NET-1…4 |
| Stale limit passed | `now − detectedAt ≥ 30 min` | `stale`; **never auto-send** (a late alert may do more harm than good; OPEN O3) | Notice + composer fallback + Discard | F-STALE-1 |
| Location unavailable / stale | `LocationSnapshotPolicy` | Send with "Location unavailable." or last-known wording | Status shows what was sent | F-LOC-1…4 |
| Backend 5xx / timeout / network error | Typed retryable error | Backoff retries with the same `crashEventId`; up to 6 attempts or the stale limit | "Retrying…" then failure + composer fallback | F-BE-1…6 |
| Non-retryable (kill switch, daily cap, invalid request, consent, template version) | Typed non-retryable error | `failed` → `fallbackPrompted` immediately | Plain explanation + composer fallback | F-BE-7…10 |
| Provider `undelivered`/`failed` after `sent` | Status poll | Update attempt; mark contact `undeliverable`/`optedOut` | Per-contact status + composer fallback for that contact | F-DEL-1…3 |
| Consent missing / no reachable contact | `CrashArming` | Nothing automatic; no countdown | Prompt on next foreground | F-CONSENT-1…2 |
| Composer unavailable (`canSendText` false) | Check at presentation | — | Copy message / Share actions | F-COMP-1 |
| App closed during countdown | Relaunch reconciliation | `recoveryPrompted` (no auto-send) | "Send now / I'm OK" | F-REL-1…4 |
| Unknown outcome (timeout after request may have reached the server) | Timeout | Retry **once** with the same key (OPEN O5: accepts a rare duplicate over a silent loss; the backend dedupes by key, so a duplicate requires a provider-side race) | Status shows "Checking…" then result | F-BE-5 |

---

## Delivery recording and polling

- On `sent` the coordinator persists attempts from the response and starts the poll schedule
  (immediately, 5 s for 60 s, then 15 s up to 10 min); foreground only.
- Backend status mapping (see contract): `queued` → `sent` → `delivered` | `undelivered` |
  `failed`; `rejected` (our caps/validation). Monotonic: statuses never regress.
- A contact whose attempt ends `delivered`/`sent` is `reachable`; `undelivered`/`failed` with
  an unreachable-class code ⇒ `undeliverable`; opted-out code ⇒ `optedOut`.
- The log screen is the rider's audit trail; deleting a record is a real local delete.

---

## Permissions, capabilities, and configuration (all done in implementation tasks)

| Item | Needed? | Notes |
| ---- | ------- | ----- |
| Contacts permission | No | System picker only |
| Notifications authorization | Yes, when enabling crash alerts | Honest in-app pre-explanation; backup prompt only |
| Time Sensitive Notifications capability | Yes | Entitlement added through `project.yml`, regenerate once (the iOS owner owns the project file) |
| Critical Alerts entitlement | No (v1) | Follow-up; requires Apple approval |
| Background modes | No (v1) | `location` mode is OPEN O1(b) |
| Motion usage string | Not expected for raw accelerometer (**Verify**) | Only for the stretch detector |
| Secrets | Reuse `SUPABASE_URL` / `SUPABASE_ANON_KEY` from `Secrets.xcconfig` | No provider credentials ever in the app |
| New dependency | `supabase-swift` at an exact pinned version (shared with MVP task 28) | Whichever task lands first adds it |

---

## Privacy and network invariants

- **Amended invariant:** *While neither ride sync nor crash alerts is enabled, the app makes no
  network requests.* While crash alerts are on, the only requests are sign-in/refresh,
  intro/test/drill/alert/all-clear sends, and status polls for existing events.
- **Network code location:** `Services/Sync` (ride sync) and `Services/Notification` (crash
  alerts) only.
- **`scripts/privacy-check.sh` changes (an implementation task; not made in this job):**
  1. Rule 1 allows `Services/Notification` and updates its message to "no network unless ride
     sync or crash alerts is enabled".
  2. New: provider-credential patterns (for example account-SID/key-like strings and
     provider names in key contexts) are flagged anywhere under `Whoosh/`.
  3. New: `tel:` / `telprompt:` URL use outside `Features/Emergency/` is flagged
     (enforces "never auto-call", Requirement 17.1).
  4. New: `import MessageUI` / `MFMessageComposeViewController` outside `Support/Representables/`
     is flagged (the composer can never become an "automatic" path in services).
  5. New: `import CoreMotion` outside `Services/Crash/`; Keychain `SecItem*` outside
     `Services/Contacts/`; `AVAudioSession` outside `Services/Alerts/`.
  6. New: copy claims such as "emergency services (have been|were|will be) notified/called/
     contacted" and "help is on (the|its) way" are flagged. (Existing rule 4 already flags
     "prevent/predict/avoid/guarantee [a] crash/collision" **including in code comments** — all
     disclaimer text, in code or docs-in-code, must be phrased to avoid it.)
  7. Camera rule unchanged (camera APIs only in `Services/Detection`).
- **Hooks:** the existing `privacy-guard-on-save` hook already runs the script on every saved
  Swift file, so no new privacy hook is needed once the script is updated. Optional new hook
  (suggested, not created here): `crash-template-golden-guard` — after saving the message
  builder or its tests, run just the golden-message tests. Another optional one: a
  pre-task reminder that `crash-alert-contract.md` must be **Agreed** before the notifier task.

---

## Error and degradation handling

| Scenario | Behavior | Req |
| -------- | -------- | --- |
| Feature off / no consent / no reachable contact | App behaves as the MVP | 1.5, 3.8 |
| Detector missing or throws | Nothing happens; recording unaffected | 5.8 |
| Detector fires repeatedly | Reducer suppresses (rows 2–6) | 6.4 |
| Rider cancels | Stop feedback, no send, suppression window | 6.5, 8 |
| Audio session fails | Visual + haptic continue; log; countdown unaffected | 8.5 |
| Notification permission denied | Backup prompt unavailable; documented limitation shown in setup | 13.3 |
| Keychain read error | Treat as "no contacts"; alerts disarmed; setup shows an error | 2.7 |
| Persistence error on a transition | Keep in-memory state; retry persist; never block the send | 6.3 |
| Supabase session expired offline | Token refresh on reconnect; if refresh fails ⇒ retryable error ⇒ fallback | 14.3 |

---

## Testing strategy

All logic is unit-tested with fakes; the pure reducer makes every state-machine row a plain
table-driven test. Manual device checks are listed in `manual-qa.md` (created by a task).

| ID | Area | Scenario → assertion |
| -- | ---- | -------------------- |
| FP-1 | False positive | Signal while ride is `paused`/`idle`/`finished` ⇒ zero countdowns, zero notifier calls |
| FP-2 | False positive | Signal with consent missing / revoked / outdated ⇒ ignored |
| FP-3 | False positive | Signal with no `reachable` contact ⇒ ignored |
| FP-4 | False positive | Second signal during `countdown` / `sending` / `sent` ⇒ ignored (one event) |
| FP-5 | False positive | Signal inside the suppression window after a cancel ⇒ ignored; after the window ⇒ new event |
| FP-6 | False positive | Per-ride cap: second signal after a *sent* alert ⇒ ignored; after a *cancelled* one ⇒ allowed |
| CC-1…5 | Cancellation | Cancel at t=0, mid, last second ⇒ `cancelled`, feedback ended, notification cancelled, zero sends; cancel at exactly the deadline ⇒ expiry wins (row 9); cancel after `sending` begins ⇒ not cancellable (row 18) |
| CC-6 | Cancellation | Cancel while `queuedOffline` ⇒ cancelled, retries stop |
| CC-7 | Cancellation | Countdown length below 15 / above 60 ⇒ clamped |
| GPS-1…4 | Unavailable GPS | No fix ever ⇒ "Location unavailable." sent; stale fix ⇒ last-known wording with age; fix older than 30 min ⇒ unavailable; GPS lost during countdown ⇒ send-time re-read |
| NET-1…5 | Connectivity | Offline at expiry ⇒ `queuedOffline`; online inside stale ⇒ sent with delay wording; online after stale ⇒ `stale`, no send; flapping ⇒ one send; offline then cancel ⇒ no send |
| DUP-1…7 | Duplicates | Double signal; double "Send now"; relaunch in `sending` ⇒ same `crashEventId`; retry after timeout ⇒ same key; backend `deduplicated: true` ⇒ one logical event; notifier call count ≤ 1 per event (initial) |
| BE-1…10 | Backend failures | Each contract error code (retryable ⇒ backoff then fallback; non-retryable ⇒ immediate fallback), timeout, malformed response, partial per-recipient failure, `undelivered` after `sent` |
| REL-1…4 | Relaunch | Persisted countdown with time left ⇒ resumes; deadline passed ⇒ `recoveryPrompted`; `sending` ⇒ resumes idempotently; resting ⇒ untouched |
| MSG-1…n | Message builder | Every golden case in contract Appendix A; GSM-7 sanitization; segment counting; length cap behavior; label sanitization; time/offset formatting across DST and half-hour offsets |
| CON-1…n | Contacts | E.164 normalization table; NANP validation; max 3; remove; edit resets verification; Keychain store (unique service name, cleanup); fresh-install purge |
| CONS-1…n | Consent | Version bump disarms; revoke disarms and cancels queued; acknowledgement required |
| ARM-1…n | Arming | Truth table of arming inputs |
| NEVER-CALL | Safety | A recording fake proves workflow layers never reference a call action; privacy-check rule flags `tel:` elsewhere |
| NOFOOT | Safety | Notifier request type has no footage field (compile-time) and the record stores only a local reference |
| PRIV-1 | Privacy | With crash alerts off, the recording notifier fake sees zero calls and no sign-in |
| DRILL-1 | Demo | Simulator signal ⇒ real workflow, `drill` template, no real-alert cap consumed, hidden Call 911 |
| UI | Views | Preview-driven checks; accessibility labels/traits asserted where practical |

Manual device checks (not automatable): audio with the silent switch on, haptics, screen-awake
behavior, VoiceOver, backgrounding mid-countdown (backup notification), real composer fallback,
airplane mode, and a live trial-SMS run end to end.

---

## Decisions

Status: **Proposed** = recommended default pending the owner's review of this draft; **OPEN** =
needs an explicit owner decision before the affected tasks start.

| #   | Decision | Choice | Why | Status |
| --- | -------- | ------ | --- | ------ |
| D1  | Notification mechanism | Backend SMS via Supabase Edge Function `send-crash-alert`; composer only as user-initiated fallback | iOS cannot send silently; no provider credentials in the app | Proposed |
| D2  | SMS provider | Twilio as the reference; behind the function so it is swappable; trial account for the demo | Fast to stand up; trial limits are acceptable for a demo | Proposed (O6: confirm provider) |
| D3  | Detection | `CrashDetector` seam + Noop + debug simulator; experimental Core Motion heuristic as a stretch | System crash detection isn't available; honest scoping | Proposed |
| D4  | Execution model | (a) foreground client countdown + (c) local-notification backup; (d) documented v2; (b) separate decision | Smallest change that matches the MVP's reliable path | **OPEN O1** |
| D5  | Alert sounds | `.playback` audio + speech + haptics + visual; no Critical Alerts in v1 | No Apple entitlement dependency | Proposed |
| D6  | Contact storage | Keychain (`AfterFirstUnlockThisDeviceOnly`), max 3, E.164, US/CA only, picker + manual | Sensitive data stays on-device; cost control | Proposed (O8: non-US) |
| D7  | Backend data minimization | No plaintext numbers, bodies, or coordinates stored; salted hash + last 2 digits | Limits breach/compliance surface | Proposed |
| D8  | Consent | Separate, versioned, revocable, plus a not-a-guarantee acknowledgement | Reconciles with "cloud sync is opt-in" | Proposed |
| D9  | Contact verification | A contact is `reachable` only after an intro/test reaches `sent`/`delivered`; alerts go only to reachable contacts | Catches typos/landlines/opt-outs before a real crash | Proposed |
| D10 | Duplicate prevention | Persisted state machine; `crashEventId` idempotency key; 120 s suppression; cap of 1 *sent* alert per ride | Directly addresses "cannot repeatedly trigger" | Proposed (O2: cap and repeated-cancel handling) |
| D11 | Countdown | 30 s default, 15–60 s range, absolute deadline | Long enough to cancel, short enough to matter | Proposed |
| D12 | Cancel gesture | Single tap, ≥ 80 pt; "Send now" is separate and distant | A false positive must be trivial to dismiss; the opposite risk (cancelling a real crash by accident) is accepted and documented | Proposed |
| D13 | Emergency services | Never automatic; manual "Call 911" button on the countdown/status screens, hidden for drills | Explicit non-goal; manual call is the rider's action | Proposed (O4: include the button?) |
| D14 | Location | Freshest accepted fix; re-read at send; last-known wording; "unavailable" still sends; Apple + Google links | Contacts need where; GPS loss is expected | Proposed |
| D15 | Message | Fixed templates, GSM-7, ≤ 612 chars/4 segments, versioned, golden-tested; backend renders from fields | No open relay; cost control | Proposed |
| D16 | Delivery records | Local `CrashAlertRecord` + attempts; status by polling `crashEventId` (push later) | Simple and testable; no push infra | Proposed |
| D17 | Stale policy | Within 30 min: send with "delayed" wording; after: never auto-send, offer composer/discard | A very late alert may panic contacts; a short delay is still useful | **OPEN O3** |
| D18 | Relaunch | Interrupted countdown past its deadline ⇒ prompt, not auto-send | A relaunch implies someone is using the phone | Proposed |
| D19 | Ride integration | Read-only `RideSessionBridge`/`RideContext`; no changes to ride internals (a read-only ride-id accessor is optional) | Keeps the finished MVP stable | **OPEN O7** (accessor) |
| D20 | Feedback seam | New `CountdownFeedback` protocol rather than extending `AlertManager` | Leaves the existing seam unchanged for the alerts teammate | Proposed |
| D21 | Cost/abuse | Caps, fixed templates, kill switch, spend cap, geo-permissions US/CA (values in contract) | Prevents bill shock and spam | Proposed |
| D22 | Network invariant | "No network unless ride sync or crash alerts is enabled"; script allows `Services/Notification` | Honest, enforceable privacy story | Proposed |
| D23 | Demo path | "Simulate crash" behind a developer-tools toggle; drill template; real backend | Judges see the real flow without crashing | Proposed |
| D24 | Arming | Armed while `recording`/`signalLost`; disarmed while paused | Fewer false positives when the phone is handled at a stop | Proposed (**O10**: confirm) |
| D25 | Countdown host | Root-level overlay above the ride cover | Works on every screen; one implementation | Proposed |
| D26 | Auth timing | Anonymous sign-in when crash alerts are enabled; session pre-warmed at ride start while online | A valid token at crash time | Proposed |
| D27 | Unknown outcome | Retry once with the same key | Prefer a rare duplicate over silent loss; backend dedupes | **OPEN O5** |
| D28 | Folder name | `Services/Network/` per owner brief (path monitor only) | Matches the brief; privacy rule keys on API names | Proposed |
| D29 | Motion detector acceptance bar | Not set | Needs measured data | **OPEN O9** |

### Owner resolution (October 24, 2026)

The iOS owner approved this spec and accepted the recommended answer for every open decision.
Where this resolution and an "OPEN" row above disagree, this resolution wins.

| # | Resolution |
| - | ---------- |
| O1 | v1 = (a) foreground, screen-awake, client-driven countdown + (c) time-sensitive local-notification backup. (d) server-side countdown is the v2 design (task 36). (b) background location is not adopted; revisit in task 35. |
| O2 | Per-ride cap = 1 **sent** automatic alert. Cancelled countdowns are not capped; the suppression window after a cancel still applies. |
| O3 | Stale limit 30 min: within it, send with "delayed" wording; after it, never auto-send (mark `stale`, offer the composer fallback). |
| O4 | Include the rider-tapped manual "Call 911" button; never shown for drills; never triggered automatically. |
| O5 | On an unknown outcome (timeout), retry once with the same `crashEventId`; accept a rare duplicate over a silent loss (backend dedupes). |
| O6 | Twilio as the provider (trial account for the demo). The account holder is Role C, to be confirmed at C1. Affects Tier 1 only. |
| O7 | Approved: add one read-only `currentRideID` accessor to `RideSessionViewModel`; no other change to ride internals. |
| O8 | Non-US numbers are out of scope for v1 (NANP only). |
| O9 | No acceptance bar set yet. The motion detector (tasks 32–33) stays off and is not offered in the UI until measured results exist. |
| O10 | Disarm detection while the ride is paused; armed only in `recording` and `signalLost`. |

### Open decisions for the owner (summary, now resolved above)

- **O1** Execution model: confirm (a) + (c) for v1, (d) as v2; decide whether (b) is ever wanted.
- **O2** Per-ride cap (1 sent) and handling of repeated cancelled countdowns (none vs. a cap/cooldown).
- **O3** Stale policy (30 min; never auto-send after) — or send with stronger "delayed" wording.
- **O4** Include the manual "Call 911" button (recommended: yes, never for drills).
- **O5** Unknown-outcome retry (accept a rare duplicate over a silent loss).
- **O6** Provider confirmation (Twilio vs. alternative) and who pays/holds the account.
- **O7** Permission to add a one-line read-only ride-id accessor to `RideSessionViewModel`.
- **O8** Non-US numbers (not v1).
- **O9** Acceptance bar for the experimental motion detector.
- **O10** Disarm while paused (recommended) vs. armed in all active states.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| False positives (potholes, drops) | Alert fatigue, contacts annoyed | Countdown + one-tap cancel; suppression; cap; detector off by default; measure before enabling |
| False negatives | Rider assumes protection that didn't happen | Honest copy and acknowledgement; foreground-only limitation stated; no reliability claims |
| App closed/suspended | No alert | Documented; local-notification backup; v2 options |
| Provider/registration lead time | Production blocked | Trial route for the demo; registration is production work |
| Anonymous-auth abuse (spam) | Cost, harassment | Caps, fixed template, per-recipient caps, kill switch, spend cap; App Attest later |
| Cloud dependency for a safety feature | Outage ⇒ no alert | Opt-in, labeled non-guaranteed; composer fallback; core recording unaffected |
| Stranger receives a text (typo/wrong number) | Privacy/annoyance | Intro/test verification, STOP honored, cooldowns |
| Message drift between iOS and backend | Inconsistent text | Shared golden cases in the contract appendix, `templateVersion` |
| Privacy-script regex collisions with disclaimers | Failing save hook | Phrase disclaimers to avoid rule 4 patterns |
| Accidental real 911 call in the demo | Embarrassment/harm | Call button hidden for drills |
| Time pressure | Partial feature | Demo tiers in `tasks.md` (Tier 0 iOS-only vs. Tier 1 with backend) |
| Rear-mounted phone (see `../rear-camera/`): the rider cannot tap the phone to cancel the countdown | Cancel unreachable; a false alert or a missed cancel | Cancel must also be reachable on the wrist (`cancelCrashCountdown` remote command, rear-camera task 30); ride mode exits to full brightness and the countdown is spoken aloud; consent copy states that without a watch the phone must be reachable. Motion-based detection (tasks 32–33) must be field-tested on a seat-post mount: the phone is on the bike, not the rider, so vibration and "drop" signatures differ. |
| Background location now enabled for ride GPS (rear-camera O-CAM2) | O1(b) premise changes: the app can stay alive while locked | v1 stays (a)+(c) as approved; (b) becomes cheap to adopt (no Always authorization needed, GPS already running) and can be reopened in task 35. `FootageBuffer` (task 34) is delivered by the rear-camera spec (task 30 there). |
