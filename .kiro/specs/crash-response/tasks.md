# Implementation Plan — Whoosh Emergency Contact and Crash Response

Small, ordered, verifiable tasks. **No code exists for this feature yet and none may be written
until the owner approves this spec** (`requirements.md`, `design.md`, this file) and, for the
network tasks, Role C marks `../../team/crash-alert-contract.md` **Agreed**.

Spec status: **APPROVED** by the iOS owner (October 24, 2026) with the recommended answers to
O1–O10 (`design.md`, "Owner resolution"). Tier 0 iOS tasks may proceed; Tier 1 tasks still wait
for the contract to be Agreed.

This plan is separate from the ride-recording MVP plan (`../ride-recording-mvp/tasks.md`, tasks
1–28). Task numbers here are independent; cross-spec references say "MVP task N".

## Conventions

- `(test-first)` — write failing unit tests from the referenced acceptance criteria, then
  implement until green (the existing `.kiro/hooks/test-first-before-task.json` applies).
- `_Requirements:_` maps the task to acceptance criteria in `requirements.md`.
- `_Depends on:_` lists prerequisite task numbers (`C#` = Role C backend task, `B#` = Teammate B).
- Each task is one reviewable commit or small PR. **Commits are made by the owner**, never by
  an automated agent unless asked.
- **Owner tags:** `[iOS]` iOS app owner · `[Role C]` backend/data owner · `[Teammate B]`
  detection/vision owner (optional, stretch) · `[Owner]` product decision.
- **Priority tags:** `[DEMO]` blocks the live demo · `[IMPORTANT]` expected but the demo can run
  without it · `[STRETCH]` valuable, never blocking · `[FUTURE]` documented follow-up.
- Run the unit suite (`scripts/test.sh`) before marking a task done. Tasks touching real audio,
  haptics, Keychain, notifications, MessageUI, or the network also need the device check named in
  the task and an entry in `manual-qa.md` (task 27).
- **Copy rule for every task:** disclaimer text must pass `scripts/privacy-check.sh` rule 4 — use
  "cannot guarantee detection or delivery", never "cannot prevent a crash" (the rule also scans
  code comments).

## Demo tiers

| Tier | What the judges see | Needs | Tasks |
| ---- | ------------------- | ----- | ----- |
| **Tier 0 — iOS only** | Set up a contact + consent → Simulate crash → full-screen audible/visual countdown → cancel (nothing sent) **or** expire → "Alert not sent" → one-tap composer fallback prefilled with the exact message → log entry. Works in airplane mode. | iOS tasks only (no backend) | 1–24, 26, 27, 29 |
| **Tier 1 — with backend** | Same flow, but on expiry a real SMS ("WHOOSH DEMO - NOT REAL …") arrives on a verified teammate phone, and delivery status updates on screen. | Tier 0 + tasks 25, 28 + Role C C1–C10 | + 25, 28, C1–C10 |

If the backend or SMS provider is unavailable on demo day, Tier 0 still demonstrates the entire
safety workflow and the composer fallback (rehearse the kill switch, C10).

---

## Phase 0 — Gate

- [x] 0. `[Owner]` `[DEMO]` Review and approve the spec; resolve open decisions
  - Read `requirements.md`, `design.md`, this plan, and the contract draft. Decide O1–O10 (or
    accept the recommended defaults) and record the answers in `design.md` "Decisions".
  - Confirm the provider (O6) and who holds the account.
  - _Verify:_ spec status changed to "Approved"; open decisions marked resolved.
  - _Requirements:_ 1 (scope), 21 (follow-ups)

## Phase 1 — Pure core (no frameworks, test-first)

- [x] 1. `[iOS]` `[DEMO]` Domain models and tuning constants (Foundation only)
  - Add `CrashEvent`, `CrashEventState`, cancel/outcome reason enums, `EmergencyContact`,
    `ContactVerification`, `ConsentRecord`, `CrashAlertSettings`, `CountdownState` (absolute
    deadline, derived `remaining`), `LocationSnapshot`, `CrashAlertRecord`, `AlertAttempt`,
    `CrashMessageKind`, and `CrashResponseTuning` with the defaults and ranges from `design.md`.
  - Models import Foundation only; value types are `Equatable`, `Codable`, `Sendable` where
    they cross actors.
  - _Verify:_ models compile in the test target; tuning clamps the countdown to 15–60 s.
  - _Requirements:_ 6.1, 6.2, 6.8, 7.2, 8.2, 11.1, 11.2
  - _Depends on:_ 0

- [x] 2. `[iOS]` `[DEMO]` Update `scripts/privacy-check.sh` for the new feature
  - Rule 1: allow network API names in `Services/Notification` as well as `Services/Sync`;
    change the message to "no network unless ride sync or crash alerts is enabled".
  - Add rules from `design.md` "Privacy and network invariants": provider-credential patterns
    anywhere under `Whoosh/`; `tel:`/`telprompt:` outside `Features/Emergency/`; `MessageUI`/
    `MFMessageComposeViewController` outside `Support/Representables/`; `CoreMotion` outside
    `Services/Crash/`; Keychain `SecItem` APIs outside `Services/Contacts/`; `AVAudioSession`
    outside `Services/Alerts/`; positive claims that emergency services were notified or that
    help is on the way. Camera rule unchanged.
  - Update the header comment and the `privacy-guard-on-save` hook **description text** only if
    the owner wants it in sync (the hook itself already runs the script).
  - _Verify:_ run the script against temporary sample files placed under paths such as
    `Whoosh/Services/Notification/…` and `Whoosh/Services/Crash/…` (allowed) and under
    `Whoosh/Features/Ride/…` (violations are reported); delete the samples; the full run on
    the current tree still prints OK.
  - _Requirements:_ 14.2, 16.2, 16.3, 17.1, 7.7
  - _Depends on:_ 0
  - _Note:_ this edits `scripts/`, which the spec-writing job did not touch; do it as the first
    code-adjacent commit so every later task is guarded.

- [x] 3. `[iOS]` `[DEMO]` Phone normalization and GSM-7 sanitizer (test-first)
  - `E164Normalizer`: US/Canada NANP only; strip punctuation and a leading `1`/`+1`; reject
    invalid area/exchange codes and N11/non-geographic patterns; clear error cases.
  - `GSM7Sanitizer`: map smart quotes/dashes, strip unsupported characters and emoji, collapse
    whitespace, enforce the rider-label charset and 20-character limit.
  - Unit tests (parameterized): valid formats, parentheses/dashes/spaces, too short/long,
    non-US numbers rejected, label cases from contract Appendix A.3.
  - _Requirements:_ 2.3, 2.4, 2.9, 10.3
  - _Depends on:_ 1

- [x] 4. `[iOS]` `[DEMO]` `CrashMessageBuilder` with golden tests (test-first)
  - Pure builder per `design.md` "Message template" and contract Appendix A: kinds
    `crash_alert`, `drill`, `test`, `intro`, `all_clear`; time/offset formatting with a fixed
    English locale; location block variants; age/accuracy formatting; delay clause; returns text,
    character count, and SMS segment count; drops the Google Maps line if > 612 characters.
  - Unit tests: **every golden case G1–G9 verbatim**, all rows of Appendix A.3 (offsets incl.
    half-hour zones, age boundaries 10/11/59/60/3599/3600, delay boundaries 59/60/119/120, cap
    fallback, DST-adjacent dates), GSM-7 only (assert no non-GSM character in any output).
  - _Requirements:_ 10.1–10.9, 12.9, 17.4
  - _Depends on:_ 1, 3
  - _Note:_ golden strings are copied from the contract appendix; any wording change bumps
    `templateVersion` in both places.

- [x] 5. `[iOS]` `[DEMO]` Pure policies: location snapshot, retry/stale, arming (test-first)
  - `LocationSnapshotPolicy`: current (≤ 10 s) / last known / unavailable (none or older than
    30 min); send-time refresh picks the newer fix.
  - `RetryPolicy`: backoff 5/15/30/60 s then 60 s, max 6 attempts, stale-limit check.
  - `CrashArming`: truth table of ride state, consent current, acknowledged, label present,
    reachable-contact count, enabled flag; armed only in `recording`/`signalLost`.
  - _Requirements:_ 5.4, 7.2, 7.3, 7.4, 12.1, 12.2, 12.5
  - _Depends on:_ 1

- [x] 6. `[iOS]` `[DEMO]` `CrashStateMachine` pure reducer (test-first)
  - Implement the transition function (state × event × context → state × effects as data) for
    all 34 rows of the design's transition table, including: suppression window, per-ride cap
    counting *sent* only, cancel-vs-deadline tie (expiry wins), non-cancellable in-flight send,
    stale handling, relaunch rows, undefined transitions as no-ops.
  - Unit tests: one test per table row, plus property-style checks: no sequence of events
    produces two `dispatch send` effects for one event; effects never include a call/dial action.
  - _Requirements:_ 6.1–6.9, 8.4, 8.10, 12.1–12.6, 13.5, 13.6, 17.1, 19.2, 19.3, 19.6
  - _Depends on:_ 1, 5

## Phase 2 — Seams, fakes, and stores

- [x] 7. `[iOS]` `[DEMO]` Detector, footage, and ride-context seams with fakes (test-first)
  - `CrashDetector` (+ `NoopCrashDetector`, `FakeCrashDetector` that emits on command with
    confidence/source/`isDrill`); `FootageBuffer` (+ `NoopFootageBuffer`, `FakeFootageBuffer`);
    read-only `RideContext` (+ `FakeRideContext`: ride state, freshest accepted fix, optional ride id).
  - Contract documented in doc comments: on-device, non-blocking, never stops recording, no
    camera access, no footage ever leaves the device.
  - _Verify:_ fakes behave as scripted; Noop emits nothing.
  - _Requirements:_ 5.1, 5.2, 5.7, 5.8, 7.5, 7.6, 7.7, 7.8, 19.1
  - _Depends on:_ 1

- [x] 8. `[iOS]` `[DEMO]` Notifier, scheduler, feedback, and connectivity protocols with fakes (test-first)
  - `CrashNotifier` (send + status; typed retryable/non-retryable errors with Whoosh error
    codes; **no field that can carry footage or free text**), `NoopCrashNotifier`,
    `FakeCrashNotifier` (scriptable success, per-code failure, timeout, delayed delivery status,
    call recording); `CrashNotificationScheduler` + fake; `CountdownFeedback` + `Noop`/`Fake`
    (records begin/tick/end); `ConnectivityMonitor` + `FakeConnectivityMonitor`.
  - _Verify:_ each fake's scripting API is covered by a small test; call counts are exposed.
  - _Requirements:_ 8.5, 8.7, 9.2, 9.3, 9.8, 12.1, 13.3, 19.1
  - _Depends on:_ 1

- [x] 9. `[iOS]` `[DEMO]` Stores: contacts, consent/settings, crash records — protocols and in-memory fakes (test-first)
  - `EmergencyContactStore` (+ `InMemory`): add/update/remove/removeAll, max 3, editing a number
    resets verification, orphan purge hook.
  - `ConsentStore` (+ UserDefaults implementation + in-memory) and `CrashAlertSettings`
    persistence: versioned consent, acknowledgement, revoke; rider label; enabled flag.
  - `CrashAlertRepository` protocol (+ `InMemoryCrashAlertRepository`): save, most-recent-first,
    get, delete, deleteAll, purge older than retention, active-event lookup.
  - Unit tests for each, including max-contacts, verification reset, consent version bump
    disarming (via `CrashArming`), real deletion.
  - _Requirements:_ 2.2, 2.5, 2.6, 2.10, 3.1, 3.6, 3.7, 11.1, 11.5, 11.9
  - _Depends on:_ 1, 5

- [x] 10. `[iOS]` `[DEMO]` SwiftData `CrashAlertRepository` (test-first)
  - `CrashAlertRecordEntity` (`@Model`; attempts encoded as a blob like ride points) and
    `SwiftDataCrashAlertRepository` with the same contract as the in-memory fake.
  - Tests against an in-memory `ModelContainer`: save/list ordering/get/delete/deleteAll/purge,
    permanence across reload, corrupt-record skip, no full phone number in any stored field.
  - Confirm that adding the new `@Model` to the container does not disturb existing ride data
    (device check in task 26).
  - _Requirements:_ 11.1, 11.3, 11.5, 11.9
  - _Depends on:_ 9

- [x] 11. `[iOS]` `[DEMO]` `KeychainEmergencyContactStore` (test-first where possible)
  - Single Keychain item (JSON blob), accessibility `AfterFirstUnlockThisDeviceOnly`, no
    iCloud sync; fresh-install marker in app-container storage and orphan purge on first launch;
    errors map to "no contacts" without crashing. Only file allowed to use Keychain APIs.
  - Unit tests with a unique test service name and cleanup (runs in the test host), including
    purge-on-fresh-install logic via an injected marker store.
  - _Verify (device):_ delete and reinstall the app ⇒ contacts are gone; locked-after-first-
    unlock read works.
  - _Requirements:_ 2.7, 2.8, 16.1
  - _Depends on:_ 9

## Phase 3 — Coordinator and ride integration

- [x] 12. `[iOS]` `[DEMO]` `CrashResponseCoordinator` core flow (test-first)
  - `@Observable`, MainActor coordinator composing the reducer with all seams, `Clock`, and an
    injectable ID factory: detector signal → evidence capture (timestamp, UTC offset, location
    snapshot, footage preserve) → countdown with absolute deadline (timer via `Clock`, feedback
    ticks, backup notification scheduled/cancelled) → cancel / expire / send now → single
    notifier dispatch → `sent` → record persisted at every transition. Exposes read-only state
    for views (state, remaining seconds, recipients, banner kind).
  - Unit tests (fakes only): **false positives** FP-1…6, **cancellation** CC-1…7, **unavailable
    GPS** GPS-1…4, **duplicates** DUP-1…4 (double signal, double Send now, repeated dispatch
    guard, notifier called ≤ 1 per event), never-call safety test, drill flag path.
  - _Requirements:_ 5.3, 5.4, 6.1–6.9, 7.1–7.4, 8.1–8.4, 8.8–8.11, 9.1, 9.4–9.7, 11.1, 17.1, 19.2–19.4, 19.6
  - _Depends on:_ 4, 5, 6, 7, 8, 9

- [x] 13. `[iOS]` `[DEMO]` Coordinator: failures, offline queue, stale, composer-fallback state, polling (test-first)
  - Offline at expiry → `queuedOffline`, retry on connectivity restore and backoff, delayed
    wording, stale limit → `stale`; retryable vs non-retryable error handling per the contract
    table; unknown-outcome single retry (O5); partial per-recipient failure; status polling
    schedule (immediate, 5 s × 60 s, 15 s to 10 min, foreground only) updating attempts and
    contact verification (`reachable`/`undeliverable`/`optedOut`); monotonic statuses;
    consent revoked while queued → cancelled.
  - Unit tests: NET-1…5, BE-1…10, DEL-1…3 (undelivered after sent), F-COMP-1 flag, flapping
    connectivity sends once.
  - _Requirements:_ 4.5, 9.3–9.5, 11.2, 11.4, 11.8, 12.1–12.10, 14.10, 19.5, 19.7
  - _Depends on:_ 12

- [x] 14. `[iOS]` `[DEMO]` Coordinator: persistence and relaunch recovery (test-first)
  - Persist state and deadline on every transition; on launch reconcile via
    `CrashAlertRepository.activeEvent()`: countdown with time left resumes; deadline passed →
    `recoveryPrompted`; `sending` resumes with the same `crashEventId`; `queuedOffline` resumes
    within the stale limit, else `stale`; resting states untouched; suppression window and cap
    honored across relaunch.
  - Unit tests REL-1…4 using a "relaunch" helper that rebuilds the coordinator over the same
    in-memory repository.
  - _Requirements:_ 6.3, 13.4, 13.5, 13.6, 19.6
  - _Depends on:_ 12, 13

- [x] 15. `[iOS]` `[DEMO]` `RideSessionBridge` and arming wiring (test-first)
  - Observe `RideSessionViewModel` (`rideState`, `points`) via Observation tracking and publish
    `RideContext`; start/stop the detector when `CrashArming` flips; **no change to ride
    internals** (if O7 approved: add only a read-only `currentRideID` accessor).
  - Unit tests with the real `RideSessionViewModel` + `FakeLocationTracker` + `TestClock`:
    armed while recording/signalLost, disarmed while paused/idle/finished, latest accepted fix
    exposed, consent/contact changes re-evaluate arming, ride recording behavior unchanged (run
    the existing ride tests untouched).
  - _Requirements:_ 5.4, 5.8, 7.5, 13.1
  - _Depends on:_ 5, 7, 12

## Phase 4 — UI (thin views over tested view models)

- [x] 16. `[iOS]` `[DEMO]` Emergency setup hub and contact editor
  - `Support/Representables/ContactPickerView` (ContactsUI) and `MessageComposeView` (MessageUI)
    wrappers; `EmergencySetupView` + view model (rider label, contact list with verification
    state, entry points); `ContactEditorView` + view model (picker or manual entry, E.164
    validation errors, max 3, edit/remove). No Contacts permission requested.
  - Tests (test-first for view models): validation and error text mapping, add/edit/remove,
    verification-reset on number change, limit message.
  - _Verify (device):_ picker works without a permission prompt; VoiceOver and Dynamic Type pass.
  - _Requirements:_ 2.1–2.10, 18.5
  - _Depends on:_ 3, 9, 11

- [x] 17. `[iOS]` `[DEMO]` Consent screen and flow
  - `ConsentView` + view model: plain-language "what is / isn't sent", precise-location and
    not-privacy-zone-trimmed notice, SMS-not-encrypted notice, STOP explanation, foreground-only
    limitation, **live message preview** from `CrashMessageBuilder`, two controls (data-use
    consent and not-a-guarantee acknowledgement), revoke path with "Delete my contacts" offer.
    Requests notification authorization only when the rider enables alerts, after an in-app
    explanation.
  - Tests: version gating, acknowledgement required, revoke disarms and cancels queued alert
    (through the coordinator), copy passes the privacy script.
  - _Requirements:_ 1.1–1.4, 3.1–3.8, 13.2, 13.3, 13.7, 16.5, 16.8
  - _Depends on:_ 4, 9, 16

- [x] 18. `[iOS]` `[DEMO]` Intro and test message flow
  - `TestAlertView` + view model: offer intro on contact add; "Send a test" per contact;
    per-contact progress (queued → sent → delivered / undelivered / failed with plain reason);
    cooldown and quota messages; offline explanation; trial-restriction explanation; contact
    becomes `reachable` only after `sent`/`delivered`.
  - Tests with `FakeCrashNotifier` for every status/error path; works in previews.
  - _Requirements:_ 4.1–4.8, 2.5, 15.6
  - _Depends on:_ 8, 13, 16, 17

- [x] 19. `[iOS]` `[DEMO]` `SystemCountdownFeedback` (audio + speech + haptics)
  - `AVAudioSession` playback category (ducking), spoken prompts, per-second tone in the last 10
    s, warning haptics once per second, idempotent `end`, session released on end/cancel; failures
    degrade silently to visual-only. Only file allowed to touch `AVAudioSession`.
  - _Verify (device):_ audible with the silent switch on; ducks other audio; releases the
    session on cancel; haptics foreground only.
  - _Requirements:_ 8.5, 8.6, 8.7
  - _Depends on:_ 8

- [x] 20. `[iOS]` `[DEMO]` Countdown takeover and root host
  - `CrashCountdownView` (very large numeral, headline with icon, sentence with contact labels,
    **≥ 80 pt full-width "I'm OK — Cancel"**, separate "Send now", manual "Call 911" hidden
    for drills, fine print) and `CrashCountdownHost` as a root overlay above the
    `NavigationStack` and the active-ride cover; modal for accessibility; screen kept awake;
    flashing-safe; Reduce Motion variant; VoiceOver announcements at start, every 10 s, last 5 s.
  - Tests: view-model/coordinator-driven (remaining text, drill hides the call button,
    announcement schedule). Previews for light/dark, Dynamic Type, Reduce Motion.
  - _Verify (device):_ one-handed cancel; cannot be swiped away; works from Home and from the
    ride screen; contrast checked with the Accessibility Inspector.
  - _Requirements:_ 8.1–8.4, 8.6, 8.8, 8.9, 8.12, 17.2, 17.3, 18.1–18.4
  - _Depends on:_ 12, 19

- [x] 21. `[iOS]` `[DEMO]` Status screen, composer fallback, manual 911, local notifications
  - `CrashAlertStatusView`: per-contact status with icon + text, queued/stale/failed banners,
    **"Tap to text <contact> now"** composer fallback (prefilled by the builder with delay
    wording; Copy/Share when `canSendText` is false), "I'm OK — cancel alert" (queued only),
    `EmergencyCallButton` (the only place using `tel:`), not-a-guarantee note.
  - `CrashNotificationScheduler` implementation over `UNUserNotificationCenter` (backup prompt at
    the deadline, "alert not sent" notice; cancel on cancel/send).
  - Tests: banner/action selection per state, fallback availability, copy passes privacy script.
  - _Verify (device):_ notification appears when the app is backgrounded at the deadline;
    composer opens prefilled and never sends without a tap; `tel:` shows the system confirmation.
  - _Requirements:_ 8.11, 11.6, 11.7, 12.1, 12.3, 12.8, 12.9, 13.3, 17.2, 17.3
  - _Depends on:_ 13, 16, 20

- [x] 22. `[iOS]` `[IMPORTANT]` Crash alert log, Settings entry, and state chips
  - `CrashAlertLogView` + view model (most-recent-first, icon + text, detail, delete one/all
    with real deletion, footage-reference delete when present); Settings → "Crash alerts" row
    pushing the setup hub; small "Crash alerts on/off" chip on Home and the ride screen
    (icon + text, no extra ride number).
  - Tests: ordering, delete, retention purge, chip state mapping.
  - _Requirements:_ 7.9, 11.5, 11.7, 11.9, 16.7, 18.6
  - _Depends on:_ 10, 16

- [x] 23. `[iOS]` `[DEMO]` Simulate crash (drill) and developer tools
  - `DebugCrashSimulator`; **Simulate crash** runs the real coordinator and notifier with the
    `drill` template, hides Call 911, is labeled in the log, does not consume the real-alert cap,
    and obeys the test/drill quota.
  - **The "Developer / demo tools" toggle and the Simulate-crash entry point are now owned by
    the global Demo mode spec (`../demo-mode/`, Demo Req 6 / 10; design D31), not a separate
    Crash-alerts toggle.** This task builds `DebugCrashSimulator` and the drill coordinator path;
    the demo-tools UI, the single toggle, and the arming-bypass-for-drills wiring live in Demo
    mode (Demo task 12). When Demo mode is not present/enabled, keep a minimal in-spec dev-tools
    entry only if needed for standalone crash testing.
  - Tests: DRILL-1; drill template selected; real-alert counters unaffected.
  - _Requirements:_ 5.3, 17.3, 19.9
  - _Depends on:_ 12, 20

- [x] 24. `[iOS]` `[DEMO]` `NWPathConnectivityMonitor`
  - Wrap `NWPathMonitor` behind `ConnectivityMonitor`; makes no requests; delivers changes on the
    main actor; used only as a retry trigger (request outcomes remain ground truth).
  - _Verify (device):_ airplane mode on/off changes `isOnline` and triggers the queued retry.
  - _Requirements:_ 12.1, 16.2
  - _Depends on:_ 8

## Phase 5 — Network integration and wiring

- [ ] 25. `[iOS]` `[DEMO — Tier 1]` `SupabaseCrashNotifier`
  - **Blocked until** the contract is **Agreed** and Role C C4–C6 are deployed to staging.
  - Add `supabase-swift` pinned to an exact version (shared with MVP task 28; whichever lands
    first adds it) and a shared client/anonymous-session provider; implement send and status
    against the contract: headers, JSON, 10 s timeout, error body → typed errors per the
    contract's client-behavior table, session pre-warm at ride start (online) and refresh-once on
    `401`. Network work runs off the main actor. Only file(s) under `Services/Notification/`
    touch the network.
  - Tests with an injected transport double (no real network): success, each error code,
    malformed body, timeout, partial recipients, `deduplicated`, header/URL correctness, no
    footage/free-text fields possible.
  - _Requirements:_ 3.9, 9.2, 9.3, 14.1–14.5, 14.7, 14.10, 16.2, 16.3
  - _Depends on:_ 8, 13, C1, C4, C5, C6

- [x] 26. `[iOS]` `[DEMO]` Composition root, project capability, and app wiring
  - `AppEnvironment`: build the coordinator, bridge, stores, repository (add the crash record
    entity to the `ModelContainer`), notifier (Noop when crash alerts are off or the contract is
    not wired; Supabase when enabled), feedback, scheduler, connectivity; `preview(…)` uses fakes.
    `WhooshApp`: mount `CrashCountdownHost`, route notification taps to the status screen, run
    launch reconciliation (task 14).
  - Project: add the Time Sensitive Notifications capability via `project.yml` and regenerate
    once (the iOS owner owns the project file); no background modes; no new usage strings.
  - _Verify (device):_ existing rides still load after the container change; full ride flow
    unchanged; app launches with crash alerts off exactly as the MVP (PRIV-1: no network, no
    sign-in).
  - _Requirements:_ 1.5, 13.1, 13.4, 16.2
  - _Depends on:_ 10, 14, 15, 20, 21, 22, 23, 24

- [x] 27. `[iOS]` `[DEMO]` Integration tests, manual QA checklist, Tier 0 device run
  - End-to-end tests over the real coordinator + bridge + real `RideSessionViewModel` with fakes
    (full ride → detector signal → countdown → expire → sent/queued/failed → record/log).
  - Create `.kiro/specs/crash-response/manual-qa.md` (same format as the MVP checklist):
    audio with the silent switch on, haptics, screen-awake, VoiceOver, Dynamic Type, Reduce
    Motion, backgrounding mid-countdown, notification backup, composer fallback, airplane mode,
    Keychain reinstall purge, Call 911 confirmation (not completed), drill hides 911.
  - Run the **Tier 0** demo script on the iPhone 14 and tick the checklist.
  - _Pending device check:_ the integration tests and `manual-qa.md` (including the Tier 0 demo
    script) are done; the on-device Tier 0 run on the iPhone 14 is still to be completed by the
    owner and ticked in `manual-qa.md`.
  - _Requirements:_ 19.1–19.11, 12.10
  - _Depends on:_ 26

- [ ] 28. `[iOS]` `[DEMO — Tier 1]` Live trial-SMS end-to-end
  - With Role C staging and verified demo numbers: intro → test → drill via Simulate crash →
    real SMS received → status updates to `delivered`; try offline queue, kill-switch fallback,
    duplicate-tap, and timeout injection.
  - Record screenshots/notes in `manual-qa.md`; confirm no provider credential exists in the repo
    or app (grep + privacy script).
  - _Requirements:_ 4.3, 9.1–9.5, 14.1–14.9, 15.4, 19.11
  - _Depends on:_ 25, 26, 27, C10

- [x] 29. `[iOS]` `[IMPORTANT]` Resilience, accessibility, and privacy compliance pass
  - Accessibility: VoiceOver on every emergency screen, countdown announcements, Dynamic Type at
    accessibility sizes, Reduce Motion, contrast, ≥ 60/80 pt targets, icon + text statuses.
  - Privacy: confirm no network while crash alerts and ride sync are both off; contacts only in
    Keychain; no numbers/bodies in logs; honest copy everywhere (Requirement 1); deletion paths
    are real; amended invariant documented in `privacy.md`.
  - Resilience: Keychain error, persistence error on a transition, audio-session failure,
    notification permission denied, expired session while offline.
  - _Requirements:_ 1.1–1.5, 16.1–16.9, 18.1–18.6, 2.7
  - _Depends on:_ 26

---

## Stretch and future (never block the demo)

- [ ] 30. `[iOS]` `[STRETCH]` All-clear follow-up ("Tell contacts I'm OK")
  - Reducer row 25 + status-screen action + `all_clear` request (Appendix A, G9); idempotent;
    shares the test/drill quota; recorded in the same record. Tests with the fake notifier.
  - _Requirements:_ 20.1–20.3, 11.6
  - _Depends on:_ 25 (or fake-only), C11

- [ ] 31. `[iOS]` `[STRETCH]` Countdown length setting
  - Settings control (15 / 30 / 45 / 60 s) persisted in `CrashAlertSettings`, clamped by tuning;
    consent preview text reflects it.
  - _Requirements:_ 8.2
  - _Depends on:_ 16

- [ ] 32. `[Teammate B]` or `[iOS]` `[STRETCH]` Motion-detector signal core (pure, test-first)
  - Windowed impact + speed-drop + stillness scoring per `design.md`; every threshold in
    `CrashResponseTuning`; tests against synthetic and recorded traces (pothole, drop, phone
    bump, hard stop, simulated crash); no framework imports.
  - _Requirements:_ 5.5, 5.6, 19.7
  - _Depends on:_ 7

- [ ] 33. `[Teammate B]` or `[iOS]` `[STRETCH]` `MotionCrashDetector` adapter and field testing
  - Core Motion adapter behind `CrashDetector` (armed only while riding; battery-aware sampling;
    local-only candidate log, nothing uploaded); off by default and labeled experimental.
  - Field test on real rides; record measured triggers per hour in `design.md` "Measured
    results"; the owner sets the acceptance bar (O9) before any UI offers it.
  - _Verify (device):_ battery impact measured; no permission prompt (confirm).
  - _Requirements:_ 5.5, 5.6, 5.7
  - _Depends on:_ 32, 26

- [ ] 34. `[Teammate B]` or `[iOS]` `[FUTURE]` Real `FootageBuffer`
  - Rolling pre-crash buffer fed by the detection pipeline (only if camera detection exists and
    is enabled); saves locally on crash; never uploaded; deletable from the log.
  - _Requirements:_ 7.6–7.9, 21.5

- [ ] 35. `[Owner]` `[FUTURE]` Apple Critical Alerts application; background-location decision
  - Apply to Apple for the entitlement (health/safety use case) and decide on background
    location (O1(b)); both are follow-ups requiring separate specs.
  - _Requirements:_ 21.1, 21.2

- [ ] 36. `[iOS]` + `[Role C]` `[FUTURE]` Server-side countdown design (v2) and hardening
  - Write a v2 design for option (d), App Attest/DeviceCheck, additional regions.
  - _Requirements:_ 21.3, 21.4, 21.6, 15.7

- [ ] 37. `[iOS]` `[FUTURE]` `SafetyKitCrashDetector` adapter + Simulator test (test-first)
  - **Blocked until** the SafetyKit entitlement is granted (task 38). Add
    `Services/Crash/SafetyKitCrashDetector.swift` behind the existing `CrashDetector` protocol —
    the only file importing SafetyKit. Gate it on `SACrashDetectionManager.isAvailable` and the
    user's `authorizationStatus` / `requestAuthorization` (requested only when crash alerts are
    enabled, honest purpose string). Map each `SACrashDetectionEvent` to a `CrashDetector` signal
    (`source = "safetykit"`, `isDrill = false`) into the existing coordinator/reducer; **dedupe**
    events the OS re-reports across **background launches** by event date/identity (funnel into
    the existing `crashEventId` idempotency, reducer rows 2–6/30); handle the launch where the
    system wakes the app in the background after an event. Do **not** use
    `SAEmergencyResponseManager` (Req 17). When the entitlement/availability/authorization is
    absent, the app behaves exactly as today (no change). Add the entitlement to `project.yml`
    and regenerate once.
  - Tests: Apple's **iOS Simulator** crash-event test path; a fake SafetyKit source driving the
    adapter; dedupe across a simulated relaunch/background-launch; availability/authorization
    gating produces no signal; coordinator path unchanged. Mark all SafetyKit behavior
    **"verify against current Apple docs"** in comments.
  - _Verify (device/Simulator):_ Simulator-triggered crash event reaches the countdown with the
    `drill`-free real path; on an unentitled build the detector is inert.
  - _Requirements:_ 5.9, 13.2 (partial mitigation), 6.2, 6.3
  - _Depends on:_ 7, 12, 26, 38
  - _Note:_ SafetyKit targets **severe vehicular** crashes and may not fire for a bicycle fall
    (verify); it is an additional *source*, not a replacement for the countdown-and-cancel UX,
    the simulator drill, or the experimental motion heuristic.

- [ ] 38. `[Owner]` `[FUTURE]` Apply for the SafetyKit crash-detection entitlement
  - Apply to Apple for `com.apple.developer.severe-vehicular-crash-event` (the request form for
    SafetyKit crash detection; verify the current process and criteria against Apple's docs).
    Record the justification (opt-in rider-safety crash alerts), the single-app-per-device
    implication, and that the separate `SAEmergencyResponseManager` entitlement is **not**
    requested (Whoosh never auto-contacts emergency services, Req 17). Configure the capability
    in the provisioning profile once granted. This has Apple-side lead time and is a follow-up,
    not demo-blocking; the demo uses the `DebugCrashSimulator` drill (Demo mode) with no
    entitlement.
  - _Verify:_ entitlement granted and present in the signed build's capabilities; `isAvailable`
    returns true on a supported device.
  - _Requirements:_ 5.9, 21 (follow-ups)

---

## Role C — backend tasks (`[Role C]`)

These implement `../../team/crash-alert-contract.md`. Role C writes the code; none is written in
this job. Cite the contract section in each PR.

- [ ] C1. `[Role C]` `[DEMO]` Review the contract and mark it **Agreed** (v1.0) with the iOS owner
  - Resolve section 14 open items that block the build (provider, retention defaults, limits).
  - _Requirements:_ 14.1 · _Contract:_ all

- [ ] C2. `[Role C]` `[DEMO]` Provider account and trial setup
  - Create the provider account; **trial mode** with verified demo numbers; sender number or
    messaging service; geographic permissions US/CA; spend cap and usage alerts; auto-recharge
    off; review provider message-log retention/redaction; document the production registration
    path (10DLC / toll-free) and lead time. Credentials only in the password manager and Edge
    Function secrets — never Git or the app.
  - _Requirements:_ 14.2, 14.9, 15.5, 16.6 · _Contract:_ 10, 11, 12

- [x] C3. `[Role C]` `[DEMO]` Database migration, RLS, and retention
  - Tables `crash_alert_events`, `crash_alert_deliveries`, `crash_alert_counters`,
    `crash_alert_config`; unique constraints; RLS (own-row `select`; no client writes; no
    client access to counters/config); scheduled purge (30-day audit, 48-hour counters).
  - _Verify:_ another anonymous user cannot read your rows; clients cannot write.
  - _Done:_ `supabase/migrations/20261024150000_crash_alerts.sql` (tables, unique keys, RLS
    select-own policies, no-policy RLS on counters/config, service-role grants, indexes,
    `purge_crash_alert_data()`; pg_cron schedule noted in the migration).
  - _Requirements:_ 14.4, 14.5, 14.7, 16.6 · _Contract:_ 9

- [x] C4. `[Role C]` `[DEMO]` `send-crash-alert` Edge Function
  - Validate (5.3), idempotency insert-then-send (5.4), keyed recipient hash, template rendering
    per Appendix A, provider call with the status-callback URL and validity limits, response
    shape (5.5), PII-free logging.
  - _Done:_ `supabase/functions/send-crash-alert/index.ts` + `_shared/` (validation.ts,
    message.ts, hash.ts, twilio.ts, limits.ts, env.ts, http.ts). Insert-before-send unknown-
    outcome policy, 409 on immutable-field mismatch, per-recipient dedupe, segment cap.
  - _Requirements:_ 3.9, 9.2, 10.8, 14.3–14.5, 14.8, 15.1, 15.3 · _Contract:_ 5, 12, Appendix A
  - _Depends on:_ C2, C3

- [x] C5. `[Role C]` `[DEMO]` `sms-status-callback` Edge Function
  - Signature validation, monotonic/sticky status updates, idempotent for duplicates and
    out-of-order callbacks, error-code mapping, always-200 after a valid signature.
  - _Done:_ `supabase/functions/sms-status-callback/index.ts` (X-Twilio-Signature validated over
    CALLBACK_BASE_URL+path before any DB access; `canApplyStatus` monotonic/sticky; unknown sid
    ⇒ 200). Deploy with `--no-verify-jwt` (see functions/README.md).
  - _Requirements:_ 14.6, 4.5 · _Contract:_ 7
  - _Depends on:_ C3, C4

- [ ] C6. `[Role C]` `[DEMO]` `crash-alert-status` and `delete-crash-audit` Edge Functions
  - Per-user status reads; rider-scoped delete (refuses events younger than 1 hour).
  - _Partial:_ `crash-alert-status` done (`supabase/functions/crash-alert-status/index.ts`:
    JWT + RLS own-rows read, 404 `unknown_event`). `delete-crash-audit` NOT yet implemented.
  - _Requirements:_ 11.4, 14.7, 16.7 · _Contract:_ 6, 8
  - _Depends on:_ C3

- [x] C7. `[Role C]` `[DEMO]` Rate limits, caps, kill switch, and config
  - All limits from contract section 10 backed by `crash_alert_counters` and `crash_alert_config`
    (tunable without deploy); the global kill switch and trial-mode flag; `429` bodies with scope.
  - _Done:_ `_shared/limits.ts` (per-user + per-recipient + global/burst caps via counters),
    `_shared/env.ts` `loadConfig`/`envKillSwitchOn`, config columns in the migration, `429`
    bodies carry `scope`/`retryAfterSeconds`, `503 service_disabled` on kill switch.
  - _Requirements:_ 15.1–15.5 · _Contract:_ 10, 11
  - _Depends on:_ C3, C4

- [x] C8. `[Role C]` `[DEMO]` Contract test suite
  - Golden-message parity with Appendix A (all G1–G9 and A.3), validation matrix, idempotency
    (duplicate, race, immutable-field mismatch → 409, unknown outcome retry), callback ordering
    (duplicate/out-of-order/sticky terminal), caps, kill switch, no PII in logs.
  - _Done (pure units):_ `supabase/functions/tests/` — `message_test.ts` (G1–G9 byte-exact +
    segment counts + A.3), `validation_test.ts` (§5.3 matrix + NANP), `twilio_test.ts`
    (status/error maps, monotonic/sticky, X-Twilio-Signature vs Twilio's documented vector),
    `hash_test.ts`. Deno was unavailable in the build env (so `deno test` was not run here);
    every pure module was transpiled with esbuild and run under Node against the same assertions
    (message 30/30, validation 22/22, twilio 18/18, hash 4/4) and type-checks clean under
    `tsc --strict`. _Still needed on a live DB:_ idempotency race, caps, and kill-switch
    integration tests.
  - _Requirements:_ 10.2, 14.5, 14.6, 15.1–15.4, 19.7 · _Contract:_ all
  - _Depends on:_ C4–C7

- [ ] C9. `[Role C]` `[IMPORTANT]` Secrets, observability, and scanning
  - Secrets set and rotated per environment; PII-free structured logs; alert on error rate and
    spend; secret/dependency scanning on the functions repo.
  - _Requirements:_ 14.2, 14.8 · _Contract:_ 12
  - _Depends on:_ C4

- [ ] C10. `[Role C]` `[DEMO]` Staging environment and demo support
  - A staging project (or flag) iOS can target; verified recipient list; rehearsed **kill-switch
    flip and recovery**; quota reset procedure for demo day; a fallback script if the provider
    is down ("show Tier 0").
  - _Requirements:_ 15.4, 19.9 · _Contract:_ 11, 14
  - _Depends on:_ C4–C7

- [x] C11. `[Role C]` `[STRETCH]` `all_clear` kind support
  - Render G9; require an existing `crash_alert` event for the same user; shared quota.
  - _Done:_ `all_clear` renders G9 (`_shared/message.ts`); `send-crash-alert` requires a prior
    `crash_alert` event for the user (else `422 no_prior_crash_alert`) and counts against the
    shared test/drill quota (`limits.ts` treats it as a test-type kind).
  - _Requirements:_ 20.1–20.3 · _Contract:_ 5.1
  - _Depends on:_ C4

- [ ] C12. `[Role C]` `[FUTURE]` Production readiness
  - Sender registration (10DLC or toll-free verification), App Attest/DeviceCheck, opt-out sync,
    provider DPA, regional expansion, server-side countdown design input.
  - _Requirements:_ 15.7, 21.3, 21.6

---

## Proposed order of implementation

1. **Gate:** 0 (owner decisions) and C1 (contract Agreed) in parallel.
2. **iOS foundation (no backend needed):** 1 → 2 → 3 → 4 → 5 → 6 (pure core), then 7, 8, 9, 10, 11
   (seams and stores). The privacy script (2) lands first so later tasks are guarded.
3. **Role C in parallel:** C2 → C3 → C4 → C5 → C6 → C7 → C8 → C9 → C10.
4. **Coordinator and ride integration:** 12 → 13 → 14 → 15.
5. **UI:** 16 → 17 → 18 (setup/consent/test), 19 → 20 → 21 (countdown/status), then 22, 23, 24.
6. **Wire and prove Tier 0:** 26 → 27 (Tier 0 demo run) → 29.
7. **Tier 1:** 25 (after C1, C4–C6) → 28 (after C10).
8. **Stretch:** 31, 30 (with C11), then 32 → 33; 34–36 are follow-ups.

Critical path to a safe Tier 0 demo: 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 15, 16, 17, 19, 20, 21, 23,
26, 27. Critical path to Tier 1 adds 24, 25, 28 and C1–C10.

## Kiro hooks

- **Existing, still sufficient:** `privacy-guard-on-save` runs `scripts/privacy-check.sh` on every
  saved Swift file; after task 2 it also enforces the new rules (network only in
  `Services/Sync` and `Services/Notification`, no `tel:` outside `Features/Emergency/`, composer
  and Core Motion/Keychain/audio confined to their folders, no provider secrets). `run-tests-after-task`
  and `test-first-before-task` apply unchanged.
- **Optional new hooks (not created in this job; add only if wanted):**
  - `crash-template-golden-guard` — `PostFileSave` on the message builder or its tests runs only
    the golden-message tests, since template drift between iOS and the backend is the most likely
    silent failure.
  - `crash-contract-agreed-reminder` — `PreTaskExec` reminder for tasks 25 and 28 that
    `crash-alert-contract.md` must be **Agreed** and that no provider credential may enter the app.

## Definition of done (per task)

1. Code matches the layering table (no illegal imports); framework access is behind a protocol
   with a fake.
2. New or changed logic has unit tests from the referenced acceptance criteria; the full suite is
   green (`scripts/test.sh`).
3. Device verification done and logged in `manual-qa.md` where the task calls for it.
4. No new first-party compiler warnings.
5. Privacy invariants intact: contacts only in Keychain; no network unless ride sync or crash
   alerts is enabled; no footage or free text in any request; no provider credentials; honest copy
   (Requirement 1) passing `scripts/privacy-check.sh`.
6. The workflow layers contain no call/dial action; "Call 911" exists only as a rider-tapped
   control in `Features/Emergency/` and is hidden for drills.

## Traceability (requirement → tasks)

| Req | Tasks |
| --- | ----- |
| 1 Positioning | 0, 17, 20, 21, 29 |
| 2 Contacts | 1, 3, 9, 11, 16, 29 |
| 3 Consent | 9, 17, 25, C4 |
| 4 Intro/test | 13, 18, C5 |
| 5 Detection | 7, 15, 23, 32, 33, 37, 38 |
| 6 Lifecycle | 1, 6, 12, 14 |
| 7 Evidence | 5, 7, 12, 22, 34 |
| 8 Countdown | 12, 19, 20, 21, 31 |
| 9 Notification | 8, 12, 13, 25, C4 |
| 10 Message | 3, 4, C4, C8 |
| 11 Records | 9, 10, 13, 21, 22 |
| 12 Fallbacks | 5, 6, 13, 21, 24, 27 |
| 13 Execution | 14, 15, 17, 21, 26 |
| 14 Backend | 2, 25, C1–C9 |
| 15 Cost/abuse | 18, C2, C4, C7, C8, C10, 36 |
| 16 Privacy | 2, 11, 17, 22, 25, 26, 29, C3 |
| 17 Emergency services | 2, 4, 6, 12, 20, 21, 23 |
| 18 Accessibility | 16, 20, 22, 29 |
| 19 Testing/demo | 6, 7, 8, 12, 13, 14, 23, 27, 28, C8, C10 |
| 20 All-clear | 30, C11 |
| 21 Future | 0, 33, 34, 35, 36, 37, 38, C12 |
