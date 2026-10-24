# Whoosh — Product Overview

Whoosh is an iOS cycling safety app built for the Hackachusetts hackathon. Its goal is
to make cycling safer and more accessible using a phone the rider already owns, with no
specialized hardware.

## Vision

Long term, Whoosh aims to provide:

- Real-time vehicle hazard warnings from a rear-facing camera
- Haptic and audio alerts that don't require looking at the screen
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
    camera permission.

Units are US customary (miles, mph, feet). The team is in Boston and the judges are US-based.

## Stretch for the demo (nice to have, never blocking)

- Opt-in sync of finished rides to Supabase so Role C's web dashboard can show them.
  The demo must still work in airplane mode.

## Explicitly NOT in the MVP demo

These are designed-for but not implemented or not demo-critical:

- Camera capture and on-device hazard detection (protocol defined, no shipping model). Rear
  vehicle detection appears only as a visible, non-functional, experimental placeholder (Home
  card, ride-screen "off" chip, Settings "Soon" row) that never requests camera permission.
- Haptic/audio collision warnings (alert manager defined, driven by stub detector)
- Background location tracking (foreground-only for the reliable demo path)
- Email/password accounts, routing/directions services
- Near-miss reporting, infrastructure analysis, safer-route recommendations
- Smartwatch companion app
- User-changeable units (units are read-only "Miles · mph" in the MVP Settings)

## Guiding Principles

- **Safety features run on-device.** Immediate alerts must not depend on a network.
- **Never block a ride.** Camera or detection failures must not stop GPS recording.
- **Honest about detection.** Do not claim the app reliably predicts collisions until
  detection performance has been measured. UI and copy frame detection as experimental.
- **Privacy first.** Location and camera data are sensitive. Keep them on-device by
  default and ask only for permissions a feature actually needs, when it needs them.
- **Degrade gracefully.** Permission denial, GPS loss, camera failure, low battery, and
  interrupted rides are expected states, not crashes.
