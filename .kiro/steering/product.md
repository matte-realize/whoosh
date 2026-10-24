# Whoosh — Product Overview

Whoosh is an iOS cycling safety app built for the Hackachusetts hackathon. Its goal is
to make cycling safer and more accessible using a phone the rider already owns, with no
specialized hardware.

## Vision

Long term, Whoosh aims to provide:

- Rear-facing camera recording from a seat-mounted phone (in scope next), then real-time vehicle
  hazard warnings from the same frames
- Haptic and audio alerts that don't require looking at the screen (wrist haptics via an Apple
  Watch companion is the recommended path for a rear-mounted phone)
- GPS ride tracking and ride summaries
- Near-miss logging and reporting
- Bike-infrastructure analysis
- Safer-route recommendations
- Smartwatch alerts

## MVP Scope (what must work in the demo)

1. A polished SwiftUI app foundation with a `NavigationStack` and Home as the hub (History and
   Settings pushed from Home; the active ride is a non-dismissible full-screen cover; the
   finished-ride summary is dismissed with "Done").
2. A ride-recording flow: start, tap pause/resume, and a press-and-hold "Stop" (~1s with
   visible progress, plus a VoiceOver custom action) so a ride is never ended by accident.
3. Continuous GPS tracking during a ride (foreground, screen-on).
4. A map view that displays the recorded route, with an active-ride screen limited to three
   numbers (ride time, distance, speed) and an amber "signal lost" banner.
5. A ride summary (distance, duration, average speed, route map) reused as history detail.
6. A Home dashboard: a This-Week stats card (total miles, ride count, total active time, and a
   Mon–Sun weekday chart from a pure `WeeklyStats` function) and a Recent rides list.
7. Ride history grouped by month (header with ride count + total miles), each row showing a
   sync-status indicator (icon + text; "On device" until sync exists), with swipe-to-delete.
8. A Settings screen: a functional GPS-accuracy control (Balanced / High, persisted),
   read-only units (Miles · mph), and a "Delete all rides" destructive action.
9. Local persistence of rides (SwiftData), including a real `deleteAll`. The core flow needs
   no network and no account.
10. A shared design system / theme (color tokens, SF Pro with tabular metric numerals, shared
    components) and the principles: three numbers max while riding, thumb-zone 60pt+ controls,
    icon + text for every state. Light app chrome, dark ride screen.
11. A modular architecture with service protocols ready for camera-based detection and haptic
    warnings to be added later, plus a visible, non-functional, experimental rear-detection
    placeholder (Home card, ride-screen "off" chip, Settings "Soon" row) that never requests
    camera permission. _Update:_ the MVP as shipped never requests the camera; camera permission is
    now requested only when the rider enables **rear camera recording** (see the rear-mounted camera
    section below). The placeholders stay until a real detector exists.

Units are US customary (miles, mph, feet). The team is in Boston and the judges are US-based.

## Stretch for the demo (nice to have, never blocking)

- Opt-in sync of finished rides to Supabase so Role C's web dashboard can show them.
  The demo must still work in airplane mode.

## Post-MVP opt-in safety feature: emergency contacts and crash response

Specified in `.kiro/specs/crash-response/` (requirements, design, tasks) with the backend
contract in `.kiro/team/crash-alert-contract.md`. It is **off by default**, **opt-in**, and
**not part of the MVP scope above**; the MVP ride flow is unchanged and never depends on it.

- A rider sets up one to three trusted emergency contacts, gives separate, versioned consent
  (with the exact message shown), and can test the workflow and change or remove contacts.
- If the crash-detection service identifies a *probable* crash during a ride, Whoosh preserves
  the timestamp and best available location, runs an audible, visual, and haptic countdown with a
  very large "I'm OK — Cancel" control, and, if not cancelled, texts the contacts a map link, the
  time, and a clear statement that **a crash was detected but an injury has not been confirmed**.
  The attempt and its delivery status are recorded on-device.
- Automatic texting uses a backend SMS provider (an iOS app cannot send an SMS silently); the
  native composer is only a rider-initiated fallback. Provider credentials never ship in the app.
- Crash detection is **experimental** (Apple's system Crash Detection is not available to apps).
  The demo uses a clearly labeled "Simulate crash" path; any motion-based detector is a stretch
  that stays off until its false-positive behavior is measured.
- Whoosh **never automatically calls or texts emergency services** and is **not a guaranteed
  emergency-response service**: it cannot guarantee detection or delivery. Copy says so in setup,
  consent, the countdown, and the status screens.
- Pre-crash camera footage, if it ever exists, stays on the device and is never uploaded or
  sent in a message. Crash alerts work only while the app is open during an active ride (v1).

## Rear-mounted camera recording (in scope — next feature, opt-in)

Specified in `.kiro/specs/rear-camera/` (requirements, design, tasks; **draft, awaiting owner
approval**). The rider clips the phone onto a holder on the back of the seat with the phone's back
camera facing rearward. Whoosh records the road behind the bike (dashcam-style rolling segments in
a bounded on-device buffer) while GPS tracks the ride. **Recording ships first, without the vision
model**; Teammate B's detector later consumes the same frames. This changes earlier assumptions:

- **The phone is not the in-ride UI.** The rider can neither see nor touch a rear-mounted screen.
  The ride is started and the camera framed on the phone first ("Mount & frame"); in-ride controls
  and alerts move to another surface. The **recommended in-ride surface is an Apple Watch
  companion** (pause/resume, save clip, stop, live time/distance, wrist haptics for rear-vehicle and
  camera warnings, cancel for the crash countdown) plus audio cues. The watch app is a separate
  follow-up spec (open decision O-CAM1); this feature defines the seams it needs.
- **"Record when the screen is off" is done with ride mode, not the background.** iOS does not let
  a third-party app keep a camera session running while the app is backgrounded or the phone is
  locked. Ride mode keeps the app in the foreground with a true-black, minimum-brightness,
  touch-locked screen so the phone looks off while camera and GPS run. If the phone locks anyway,
  video stops cleanly and the rider is told; GPS continues because the `location` background mode is
  recommended now (open decision O-CAM2).
- **Clips, not a firehose.** Footage is a bounded ring buffer; clips are saved on demand (manual,
  detection event, crash event), attached to the ride, viewable and deletable in the app, and
  exported to Photos only by explicit action. Footage never leaves the device. Role C's database
  receives near-miss **events** only, never video.
- **Camera trouble is never silent.** The rider cannot see the screen, so every stop or degradation
  (heat, storage, battery, interruption) is announced on the eyes-free surface and noted in the
  summary.

The MVP ride flow is unchanged when rear camera recording is off.

## Apple Watch companion (specified — draft, opt-in, post-MVP)

Specified in `.kiro/specs/watch-companion/` (requirements, design, tasks; **draft, awaiting owner
approval**). With the phone rear-mounted, the wrist is the only surface the rider can see and touch
during a ride, so the watch app provides: live ride time/distance/speed and camera/link state; pause,
resume, press-and-hold stop, "Save clip", and an armed start from the wrist; distinct wrist haptics for
the experimental rear-vehicle cue and camera/battery notices; and the crash-countdown Cancel (drills
labeled DEMO). The phone stays authoritative; the watch only displays, requests, and plays haptics.

- A cycling workout session keeps the watch app running with the wrist down. This is the design's central
  bet; a **feasibility spike gates all production watch code**, with fallbacks down to phone audio.
- Nothing about the ride (location, route, video, contacts) is sent to the watch beyond what it displays,
  and nothing leaves the rider's own devices. Honest framing: haptics are a cue, not a guarantee.
- The owner's Apple Watch SE is the target (watchOS 10 and later). A Garmin fenix 6x and a Whoop are
  **out of scope**.
- Without a watch every flow works as before (phone audio, ride-mode unlock).

## Explicitly NOT in the MVP demo

These are designed-for but not implemented or not demo-critical:

- On-device hazard detection (protocol defined, no shipping model). Rear vehicle detection appears
  only as a visible, non-functional, experimental placeholder (Home card, ride-screen "off" chip,
  Settings "Soon" row) until a real detector exists. _Update:_ camera **capture and recording** are
  now in scope as a separate opt-in feature (section above); only the detection model remains
  future.
- Haptic/audio collision warnings (alert manager defined, driven by stub detector). _Update:_ the
  `AlertSink` fan-out seam and the audio/watch channels are specified in the rear-camera spec.
- Background location tracking (foreground-only for the reliable demo path). _Update:_ the
  rear-camera spec recommends enabling the `location` background mode now (open decision O-CAM2) so
  the route survives an accidental lock.
- Email/password accounts, routing/directions services
- Near-miss reporting, infrastructure analysis, safer-route recommendations (near-miss **events**
  are recorded locally by the rear-camera spec; upload is a future task)
- Smartwatch companion app (_recommended_ as the in-ride surface for a rear-mounted phone). _Update:_
  now specified as a draft in `.kiro/specs/watch-companion/` (see the section above); still post-MVP
  and opt-in
- User-changeable units (units are read-only "Miles · mph" in the MVP Settings)
- Emergency contacts and crash alerts (post-MVP opt-in feature; see the section above)

## Guiding Principles

- **Safety features run on-device.** Immediate alerts must not depend on a network.
- **Never block a ride.** Camera or detection failures must not stop GPS recording.
- **Honest about detection.** Do not claim the app reliably predicts collisions until
  detection performance has been measured. UI and copy frame detection as experimental.
- **Privacy first.** Location and camera data are sensitive. Keep them on-device by
  default and ask only for permissions a feature actually needs, when it needs them.
- **Opt-in safety features are never guarantees.** Anything that notifies other people
  (crash alerts) needs separate, versioned consent, shows exactly what is sent, offers a one-tap
  cancel, and never claims reliable detection, guaranteed delivery, or that help is coming.
- **Degrade gracefully.** Permission denial, GPS loss, camera failure, low battery, and
  interrupted rides are expected states, not crashes.
- **Rear-mounted means eyes-free.** With the phone on the seat post the screen is not an in-ride
  UI: start and frame before mounting, put in-ride control and alerts on the wrist or audio, and
  never let a camera problem go unannounced.
- **Footage is the rider's, on the rider's phone.** Video stays on the device, is never uploaded
  automatically or sent in a message, and is easy to delete; the database receives events, not
  video. Other road users appear in footage, so retention is short and guidance is clear.
