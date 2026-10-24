# Whoosh — Privacy & Permissions Boundaries

Whoosh handles two highly sensitive data types: **precise location** and, in the future,
**camera video**. These rules are non-negotiable and apply to all code, copy, and the web
dashboard.

## Data Handling

- **Local-first.** Rides are recorded and stored on-device (SwiftData). Every core feature
  (record, summary, history, delete) works with no network and no account.
- **Cloud sync is opt-in.** Uploading rides to Supabase (for the web dashboard) is off by
  default and enabled by an explicit user toggle with a plain explanation of what is sent.
- **What may be uploaded:** finished-ride summaries, the (privacy-trimmed) route, and later
  near-miss events. Never raw camera video or frames.
- **Privacy zones.** Before upload, trim the first and last stretch of the route (default
  ~0.1 mi / 160 m) so the rider's home or work isn't exposed. The local copy stays complete.
- **No analytics or tracking SDKs.** The only third-party dependency allowed to touch the
  network is the pinned Supabase client, and only for opt-in sync.
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

## Permissions

Request the minimum permission, as late as possible, with honest usage strings.

| Permission           | When requested                         | Info.plist key                                 |
| -------------------- | -------------------------------------- | ---------------------------------------------- |
| Location (WhenInUse) | First time the user starts a ride      | `NSLocationWhenInUseUsageDescription`          |
| Location (Always)    | Only if/when background tracking ships | `NSLocationAlwaysAndWhenInUseUsageDescription` |
| Camera               | Only when the user enables detection   | `NSCameraUsageDescription`                     |

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

## Honesty in Copy

- Do not describe detection as able to "prevent" or "predict" collisions. Use language like
  "experimental vehicle detection" until performance is measured.
- Do not imply data leaves the device when it does not, and vice versa. The sync toggle says
  exactly what is uploaded.
- The same rules apply to the web dashboard and the pitch.
