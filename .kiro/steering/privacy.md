# Whoosh — Privacy & Permissions Boundaries

Whoosh handles two highly sensitive data types: **precise location** and, in the future,
**camera video**. These rules are non-negotiable and apply to all code, copy, and the web
dashboard.

## Data Handling

- **Local-first.** Rides are recorded and stored on-device (SwiftData). Every core feature
  (record, summary, history, delete) works with no network and no account.
- **Cloud sync is opt-in.** Uploading rides to Supabase (for the web dashboard) is off by
  default and enabled by an explicit user toggle with a plain explanation of what is sent.
- **Public sharing is a separate opt-in.** Making synced rides visible on the public Whoosh
  website is controlled by a separate global setting ("Share new rides on the Whoosh website"),
  off by default and available only while cloud sync is on. It applies only to rides finished
  while it is on (not retroactive), shows a plain-language confirmation of what becomes visible
  (trimmed route, distance, time, average speed; no name or account), and each ride shows its
  own sharing state. Sync and sharing are different promises and keep separate consent.
- **What may be uploaded:** finished-ride summaries, the (privacy-trimmed) route, and later
  near-miss events. Never raw camera video or frames. Separately, and only under the independent
  crash-alert consent, the transient request needed to send a crash alert or test message (see
  "Emergency contacts and crash alerts").
- **Privacy zones.** Before upload, trim the first and last stretch of the route (default
  ~0.1 mi / 160 m) so the rider's home or work isn't exposed. The local copy stays complete.
- **No analytics or tracking SDKs.** The only third-party dependency allowed to touch the
  network is the pinned Supabase client, and only for opt-in ride sync or opt-in crash alerts
  (see "Emergency contacts and crash alerts").
- **Network invariant:** while neither ride sync nor crash alerts is enabled, the app makes no
  background or automatic network requests. The one exception is a **user-initiated** remote
  delete or unshare of a ride that was uploaded earlier: it runs only at the moment the user
  asks, never in the background, and shows a retryable error if offline (so a ride the user
  asked to remove or stop sharing does not silently stay in the cloud or public). Network code
  lives only in `Services/Sync` and `Services/Notification`.
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
| Pre-crash footage (future) | **Device only** | Never uploaded, never linked or attached in a message, deletable from the crash log. |
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
| Camera               | Only when the user enables detection   | `NSCameraUsageDescription`                     |
| Notifications (time-sensitive) | When the rider enables crash alerts, after an in-app explanation (backup prompt only) | runtime authorization; Time Sensitive capability |
| Contacts             | **Never requested.** Contacts are chosen with the system picker or typed in. | — |
| Motion               | Not expected for the experimental raw-accelerometer detector (verify) | — |

Usage description strings must plainly state the purpose, e.g.:

- Location: "Whoosh uses your location to record your cycling route and show your ride map."
- Camera: "Whoosh uses the rear camera to experimentally detect approaching vehicles. Video
  is processed on your device and is not uploaded."

## Degradation Rules

The app must remain usable when permissions are denied, hardware fails, or the network is
down:

- **Location denied:** Show a clear explanation and a button to open Settings. The app still
  opens and shows ride history. No crash, no dead-end.
- **Camera denied or unavailable:** Detection features disable themselves silently. Ride
  recording is unaffected.
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
- Do not imply data leaves the device when it does not, and vice versa. The sync toggle says
  exactly what is uploaded.
- Whoosh is **not a guaranteed emergency-response service**: it may fail to detect a crash, may
  send false alerts, cannot guarantee message delivery, and does not contact emergency services.
  Say so in setup, consent, the countdown, and the status screens. Phrase disclaimers so they
  pass `scripts/privacy-check.sh` ("cannot guarantee detection or delivery").
- The same rules apply to the web dashboard and the pitch.
