# Whoosh — Privacy & Permissions Boundaries

Whoosh handles two highly sensitive data types: **precise location** and **camera video**
(rear-mounted recording, opt-in; see `.kiro/specs/rear-camera/`). These rules are non-negotiable
and apply to all code, copy, and the web dashboard.

## Data Handling

- **Local-first.** Rides are recorded and stored on-device (SwiftData). Every core feature
  (record, summary, history, delete) works with no network and no account.
- **Cloud sync is opt-in.** Uploading rides to Supabase (for the web dashboard) is off by
  default and enabled by an explicit user toggle with a plain explanation of what is sent.
- **What may be uploaded:** finished-ride summaries, the (privacy-trimmed) route, and later
  near-miss **events** (time, coordinate, kind, confidence, position hint; never a clip id,
  thumbnail, or any footage reference). Never raw camera video or frames. Separately, and only under the independent
  crash-alert consent, the transient request needed to send a crash alert or test message (see
  "Emergency contacts and crash alerts").
- **Privacy zones.** Before upload, trim the first and last stretch of the route (default
  ~0.1 mi / 160 m) so the rider's home or work isn't exposed. The local copy stays complete.
- **No analytics or tracking SDKs.** The only third-party dependency allowed to touch the
  network is the pinned Supabase client, and only for opt-in ride sync or opt-in crash alerts
  (see "Emergency contacts and crash alerts").
- **Network invariant:** while neither ride sync nor crash alerts is enabled, the app makes no
  network requests. Network code lives only in `Services/Sync` and `Services/Notification`.
- **Minimal identity.** Supabase anonymous sign-in is the default. No email, name, or
  other PII is collected for the hackathon build.
- **User owns their data.** Users can view and delete any ride. Local deletion is real
  deletion. If the ride was synced, deleting it also requests remote deletion.

## Backend Security (Supabase)

- **Row Level Security on every table.** Users may insert, read, and delete only their own
  rows (`user_id = auth.uid()`).
- **Keys:** the app ships only the public anon key. The `service_role` key never appears in
  the app or the Git repo. Server-side use (if any) lives in Role C's environment.
- **Secrets stay out of Git.** URL and anon key live in a gitignored `Secrets.xcconfig`;
  `Secrets.example.xcconfig` is committed with placeholder values.
- **Public website data must be deliberate.** If the dashboard shows rides publicly, it
  reads from an explicit, reviewed view (e.g., aggregated or trimmed routes), never from raw
  tables with RLS bypassed.

## Rear camera footage (opt-in; added October 24, 2026)

Applies to rear-mounted recording (`.kiro/specs/rear-camera/`). It is **off by default**. This
section replaces the earlier "no camera permission in the MVP" rule: the MVP as shipped never asks
for the camera, and the camera is now requested **only when the rider turns on "Record rear
camera"**.

| Data | Where | Rules |
| ---- | ----- | ----- |
| Rolling segments (the ring buffer, ~10 min by default) | **Device only**, app storage, excluded from backups, protection class that allows writing while locked after first unlock | Bounded by minutes and bytes; oldest deleted first; **deleted when the ride ends** unless pinned; orphans purged on launch |
| Saved clips (pinned: manual, detection event, crash event) and thumbnails | **Device only**, same protections | Attached to the ride; the rider can view and delete one, all for a ride, or all clips; deleting a ride deletes its clips; auto-expire after a retention period (default 30 days, open decision O-CAM4) |
| Test recording from Mount & frame | Device temp storage | Deleted right after playback |
| Near-miss event records | Device (SwiftData) with the ride | Event fields only; an optional **local** clip id that never leaves the device |
| Audio | **Off by default** | Microphone permission only if the rider enables audio; conversations may be captured, so guidance is shown |

Rules:

- **Never automatic upload or sharing.** Footage is not synced, not attached to crash messages, not
  linked by URL, not written to logs or crash reports, not placed in shared containers. Network-layer
  code (`Services/Sync`, `Services/Notification`) must not reference camera, clip, or footage types
  (enforced by the privacy script).
- **Export is explicit.** Saving a clip to Photos happens only on a per-clip rider action, copies
  (never moves), and asks for **add-only** Photos access at that moment.
- **Other people are in the footage.** Faces and license plates of other road users and pedestrians
  can appear. The enable screen and Settings say so, retention is short, deletion is easy, and no
  clip is shared by the app. Recording and audio-recording laws vary by place; copy mentions this
  as information only, never as legal advice.
- **Role C's database receives near-miss events only, never video** or anything derived from it
  (no thumbnails, frames, or clip ids).
- **No hiding.** Ride mode dims the screen to save power; the red recording dot stays visible and
  system camera/location indicators are never hidden or imitated.
- **Silent degradation is not allowed for recording.** With the phone out of the rider's sight, any
  camera stop, interruption, heat/storage/battery reduction, or permission loss is announced on the
  eyes-free surface (watch/audio) and noted in the ride summary.

## Apple Watch companion (opt-in, post-MVP; added October 24, 2026)

_Amended by watch-companion A10 (October 24, 2026)._ Applies to the Apple Watch companion
(`.kiro/specs/watch-companion/`). It is **off by default**, opt-in, and post-MVP; every phone flow
behaves exactly as before when no watch is present. The watch is **phone-authoritative**: it displays
what the phone publishes, sends typed commands, and plays haptics. It records no ride, holds no ride
data, and decides no state transition.

### What the watch may receive, hold, and send

| Data | Where | Rules |
| ---- | ----- | ----- |
| Ride status (state, elapsed duration, distance and speed **rounded**, camera state + reason codes, battery percentages, counts) | Transient over WatchConnectivity; the system keeps the latest context | Only the allowlisted `WireRideStatus` fields. **No coordinates, route, map data, video, frames, thumbnails, clip ids, contact names or numbers, or message text.** |
| Crash countdown on the watch | Watch memory | Event id, relative remaining time, drill flag, **contact count**, phase. Never names, numbers, or location. |
| Notice log | Watch memory, current ride only | Kind, time-into-ride, reason code. Discarded at the next ride; never persisted. |
| Last ride summary | Small local record on the watch | Totals and counts only. No route, no location, no contacts. |
| Watch settings | Watch `UserDefaults` | Default-save-to-Health, "also play a sound", complication opt-in. |
| Workout (optional) | Apple Health, on the rider's own devices | **Write-only workout type**; Whoosh reads no Health data, uploads no workout; the rider chooses Save or Discard. |
| Wire diagnostics | Watch memory / local log | Ids, types, and outcome codes only; never payload content; never a shared container or upload. |

Rules:

- **Nothing leaves the rider's own devices.** The link is device to device over WatchConnectivity; the
  **watch app makes no network requests**, ever, and the watch target contains no networking, analytics,
  or tracking SDK (enforced by `scripts/privacy-check.sh`, extended to scan `WhooshWatch/` and
  `Packages/WhooshWire/Sources`).
- **Wire privacy rule:** the wire payload carries enums, rounded numbers, booleans, and identifiers only —
  **no free-form text and no sensitive field**. A pure allowlist test (PR-1) serializes every wire type
  and fails on any field outside the allowlist or any string longer than a short code.
- **Confined frameworks.** `import WatchConnectivity` only in
  `Whoosh/Services/Remote/WCSessionWireLink.swift` and `WhooshWatch/Services/Link/`; HealthKit /
  `HKWorkoutSession` only in `WhooshWatch/Services/Workout/` and the single phone file that calls
  `startWatchApp` (`Whoosh/Services/Remote/WatchLauncher.swift`); WatchKit haptic calls
  (`WKInterfaceDevice.play`) only in `WhooshWatch/Services/Haptics/`. The shared package
  (`Packages/WhooshWire`) imports Foundation only. The network layers (`Services/Sync`,
  `Services/Notification`) must not reference wire types.
- **Write-only Health.** HealthKit authorization is requested only to **share** the cycling workout type,
  reads nothing, and is asked for when the rider first starts a watch-supported ride or taps "Set up
  watch alerts", after an in-app explanation. The rider chooses Save or Discard.
- **Honest about the wrist.** Haptics are a cue, not a guarantee: a watch may be on a locked screen, in a
  muted mode, or low on battery. Copy says the rear-vehicle cue is experimental and that Whoosh **cannot
  guarantee detection or delivery**; it never says "warning", "collision", or "danger" for the cue.
- **Silent degradation is not allowed.** With the phone rear-mounted, any camera stop, interruption, or
  loss is announced on the eyes-free surface (watch or audio) and noted in the ride summary; when the
  watch is not ready the announcement uses phone audio.

## Emergency contacts and crash alerts

Applies to the opt-in crash-response feature (`.kiro/specs/crash-response/`, backend contract
`.kiro/team/crash-alert-contract.md`). It is **off by default**, post-MVP, and independent of
ride sync. These rules are non-negotiable.

### What is stored where

| Data | Where | Notes |
| ---- | ----- | ----- |
| Emergency contact names and phone numbers (E.164) | **Device only**, in the Keychain (`AfterFirstUnlockThisDeviceOnly`) | Never in SwiftData, `UserDefaults`, logs, iCloud, or backups that leave the device. Orphaned Keychain items are purged on a fresh install. Max 3 contacts, US/CA numbers in v1. |
| Consent record (version, timestamp, acknowledgement), rider label, feature toggle | Device (`UserDefaults`) | No contact data. |
| Crash alert records (event id, time, location snapshot, countdown outcome, per-contact status, masked numbers = last 2 digits) | Device (SwiftData) | Deletable one by one or all; real deletion. Full phone numbers are not stored here. |
| Pre-crash footage (a pinned clip from the rear-camera ring buffer; real once rear camera recording ships) | **Device only** | Never uploaded, never linked or attached in a message, deletable from the crash log (deleting the record's footage deletes the clip). |
| Backend audit rows (hashed recipient, last 2 digits, status, error code, timestamps, template/consent version, location *status* only) | Supabase, RLS own-rows | **Retained 30 days**, then purged; the rider can delete earlier. The backend does **not** persist plaintext numbers, message bodies, or coordinates. |
| Rate-limit counters | Supabase | No PII beyond a keyed recipient hash; purged after 48 hours. |

### What may be sent, and when

- A contact's phone number goes to the crash-alert backend (and from there to the SMS provider)
  **only** when an introduction, test, drill, crash alert, or all-clear message is being sent,
  over TLS, authenticated with the anonymous Supabase session. Provider credentials never exist
  in the app or the repo; they live only in Edge Function secrets.
- A crash alert contains: the rider's chosen label (first name or nickname), the crash time and
  UTC offset, the last known or current location as map links, and the statement that a crash
  was detected but an injury has not been confirmed. The location is **precise and not trimmed
  by the ride-sync privacy zone**, because a contact needs it; the consent screen says so.
- **Never sent:** camera video or frames, footage links, ride history or routes, the contact
  list, or any free-form text from the client. The backend renders fixed templates.
- Text messages are not end-to-end encrypted and are processed by the SMS provider and carriers;
  the consent screen says so. Provider-side message-log retention is reviewed and documented by
  Role C.
- Ride sync and crash alerts have **separate consents**; enabling one never enables the other.

### Consent

- Explicit, separately recorded, **versioned** consent that lists exactly what is and is not
  sent, shows the exact message text, and includes a separate acknowledgement that Whoosh is not
  a guaranteed emergency-response service. A material text change bumps the version and
  disables automatic alerts until re-accepted.
- Consent can be revoked at any time; revoking disables automatic alerts immediately, cancels
  any queued unsent alert, and offers to delete the contacts.
- Introduction messages tell each contact who added them and how to reply STOP; opt-outs are
  honored and surfaced to the rider.

### Behavior rules

- The app **never automatically calls or texts emergency services**. A rider-tapped "Call 911"
  button is the only allowed path, and it is hidden for demo drills.
- The native SMS composer is a rider-initiated fallback only; the app never claims to send
  silently from the rider's number.
- One crash event can produce at most one message per recipient (idempotency key
  `crashEventId`, client state machine, backend unique constraint).
- Cost/abuse controls (recipient limits, quotas, kill switch) are part of the privacy design:
  they stop the feature from being used to message strangers.
- Copy never claims reliable crash detection, guaranteed delivery, or that help is coming.

## Permissions

Request the minimum permission, as late as possible, with honest usage strings.

| Permission           | When requested                         | Info.plist key                                 |
| -------------------- | -------------------------------------- | ---------------------------------------------- |
| Location (WhenInUse) | First time the user starts a ride      | `NSLocationWhenInUseUsageDescription`          |
| Location (Always)    | Only if/when background tracking ships | `NSLocationAlwaysAndWhenInUseUsageDescription` |
| Camera               | Only when the rider first enables **Record rear camera** (after an in-app explanation) | `NSCameraUsageDescription` |
| Microphone           | Only if the rider enables optional audio recording (off by default) | `NSMicrophoneUsageDescription` |
| Photos (add-only)    | Only at the first explicit "Save to Photos" export of a clip | `NSPhotoLibraryAddUsageDescription` |
| Background location mode | Declared now (open decision O-CAM2) so the route survives a lock; used only while a ride is active, with the background-location indicator; **When-In-Use** authorization, no Always prompt | `UIBackgroundModes` = `location` |
| Notifications (camera paused) | Lazily, after rear camera recording is enabled, with an in-app explanation; denial only removes this notice channel | runtime authorization |
| Notifications (time-sensitive) | When the rider enables crash alerts, after an in-app explanation (backup prompt only) | runtime authorization; Time Sensitive capability |
| HealthKit (watch): share workout type only | When the rider first starts a watch-supported ride or taps "Set up watch alerts", after an in-app explanation; reads nothing (confirm whether the share key is required with an empty read set) | `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` on the watch target _(watch-companion A10)_ |
| Notifications (watch): crash-cancel backup | Only when crash alerts are enabled and the watch is used, after an in-app explanation | runtime authorization on the watch _(watch-companion A10)_ |
| Contacts             | **Never requested.** Contacts are chosen with the system picker or typed in. | — |
| Motion               | Not expected for the experimental raw-accelerometer detector (verify) | — |

Usage description strings must plainly state the purpose, e.g.:

- Location: "Whoosh uses your location to record your cycling route and show your ride map."
- Camera: "Whoosh uses the rear camera to record video of the road behind you during rides.
  Video is saved on your device and is not uploaded."
- Microphone (only if audio is enabled): "Whoosh can record sound with your ride video. Audio is
  saved on your device and is not uploaded."
- Photos (add-only): "Whoosh saves a ride clip to your photo library only when you choose to
  export it."

## Degradation Rules

The app must remain usable when permissions are denied, hardware fails, or the network is
down:

- **Location denied:** Show a clear explanation and a button to open Settings. The app still
  opens and shows ride history. No crash, no dead-end.
- **Camera denied or unavailable:** Recording and detection do not run, and the state is **visible
  and calm** (Settings and Mount & frame explain it; mid-ride loss is announced on the eyes-free
  surface), never silent. Ride recording is unaffected.
- **Camera interrupted, hot, low on storage or battery:** reduce or stop the camera, tell the rider,
  keep GPS recording, and note the gap in the summary. A locked or backgrounded phone cannot keep
  recording video (iOS interrupts it); GPS continues through the `location` background mode.
- **GPS signal lost mid-ride:** The ride continues; the tracker enters a "signal lost" state,
  surfaces it in the UI, and resumes when signal returns. No data corruption.
- **Offline / Supabase unreachable:** Rides save locally and are marked pending; sync retries
  later. Recording and history are never blocked by sync.
- **Crash alerts offline or failing:** the alert is queued and retried; the rider sees a clear
  "not sent" banner with a one-tap "I'm OK — cancel alert" and a prefilled "Tap to text
  <contact> now" fallback. Past a stale limit the alert is never sent automatically. A crash
  alert failure never affects ride recording.
- **Consent missing or revoked:** nothing automatic ever happens; at most a prompt.

## Honesty in Copy

- Do not describe detection as able to "prevent" or "predict" collisions. Use language like
  "experimental vehicle detection" until performance is measured.
- Recording is for the rider's own records. Do not call footage "evidence", do not promise that
  any incident will be captured, and do not describe ride mode as hiding the camera.
- Do not imply data leaves the device when it does not, and vice versa. The sync toggle says
  exactly what is uploaded.
- Whoosh is **not a guaranteed emergency-response service**: it may fail to detect a crash, may
  send false alerts, cannot guarantee message delivery, and does not contact emergency services.
  Say so in setup, consent, the countdown, and the status screens. Phrase disclaimers so they
  pass `scripts/privacy-check.sh` ("cannot guarantee detection or delivery").
- The same rules apply to the web dashboard and the pitch.
