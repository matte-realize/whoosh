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

1. A polished SwiftUI app foundation with clear navigation.
2. A ride-recording flow: start, pause, resume, stop.
3. Continuous GPS tracking during a ride (foreground, screen-on).
4. A map view that displays the recorded route.
5. A ride summary (distance, duration, average speed, route map).
6. Local persistence of rides (SwiftData). The core flow needs no network and no account.
7. A modular architecture with service protocols ready for camera-based
   detection and haptic warnings to be added later.

Units are US customary (miles, mph, feet). The team is in Boston and the judges are US-based.

## Stretch for the demo (nice to have, never blocking)

- Opt-in sync of finished rides to Supabase so Role C's web dashboard can show them.
  The demo must still work in airplane mode.

## Explicitly NOT in the MVP demo

These are designed-for but not implemented or not demo-critical:

- Camera capture and on-device hazard detection (protocol defined, no shipping model)
- Haptic/audio collision warnings (alert manager defined, driven by stub detector)
- Background location tracking (foreground-only for the reliable demo path)
- Email/password accounts, routing/directions services
- Near-miss reporting, infrastructure analysis, safer-route recommendations
- Smartwatch companion app

## Guiding Principles

- **Safety features run on-device.** Immediate alerts must not depend on a network.
- **Never block a ride.** Camera or detection failures must not stop GPS recording.
- **Honest about detection.** Do not claim the app reliably predicts collisions until
  detection performance has been measured. UI and copy frame detection as experimental.
- **Privacy first.** Location and camera data are sensitive. Keep them on-device by
  default and ask only for permissions a feature actually needs, when it needs them.
- **Degrade gracefully.** Permission denial, GPS loss, camera failure, low battery, and
  interrupted rides are expected states, not crashes.
