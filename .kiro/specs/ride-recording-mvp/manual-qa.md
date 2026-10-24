# Whoosh — Manual QA Checklist (iPhone 14, iOS 17)

This checklist covers the device/simulator verifications that unit tests and the
`build-for-testing` pass cannot prove. It collects every `_Pending device check:_`
note from `tasks.md`, grouped by screen, plus the resilience and privacy flows
from tasks 24–25. Walk through it on the primary demo device (iPhone 14) before
the demo.

Legend: `[ ]` not yet verified · `[x]` verified on device.

---

## Pre-flight

- [ ] App builds and launches on the iPhone 14 with the Apple Developer signing
      team (no provisioning errors).
- [ ] Full `xcodebuild test` suite passes (orchestrator runs it once).
- [ ] First launch shows Home (not a crash, not a blank screen).

---

## Home dashboard

- [ ] Wordmark, "Ready to ride?", This-Week stats card, Recent rides, rear-
      detection placeholder card, "Start Ride" button, and "GPS ready" chip all
      render per mockup 1.
- [ ] With seeded/real rides: weekly miles, ride count, total active time, and
      the Mon–Sun 7-bar chart match the actual rides.
- [ ] Empty state (no rides this week): card shows zeros, chart is empty but not
      broken, Recent shows "Your first ride will show up here."
- [ ] "See all ›" opens History.
- [ ] Rear-detection card is inert and **never** prompts for camera permission.
- [ ] VoiceOver: wordmark, stats, chart summary, Start Ride, and the chips are
      all reachable and announce sensibly.
- [ ] Dynamic Type at XXL / Accessibility sizes: Home text scales without
      clipping the Start Ride button off-screen.

## Location permission & denied state

- [ ] First "Start Ride" with `notDetermined` shows the system When-In-Use
      prompt with the honest usage string ("Whoosh uses your location to record
      your cycling route and show your ride map.").
- [ ] Deny permission → Home swaps to the denied state: plain explanation, the
      numbered 1-2-3 Open-Settings help, an "Open Settings" button that deep-links
      to the app's Settings, and a "View past rides" button.
- [ ] "View past rides" still opens History while denied (no dead-end).
- [ ] Return from Settings after granting → Home updates to the dashboard with no
      app restart (live authorization change).
- [ ] Device-wide Location Services off → same non-blocking denied path.
- [ ] VoiceOver: the denied explanation and both buttons are reachable/labeled.

## Active ride screen

- [ ] Presented as a **non-dismissible full-screen cover** — a swipe-down does
      NOT abandon the ride.
- [ ] Screen stays dark; route draws live on a short walk/ride; the map auto-
      follows and tolerates a manual pan (recenter button returns follow).
- [ ] At most three numbers: ride time (large), distance, speed. Ride time ticks
      each second and **freezes while paused**.
- [ ] Pause then Resume: single taps; paused reuses the same layout and shows the
      "Paused" chip (icon + text).
- [ ] **Hold-to-stop:** a quick tap does NOT stop the ride (shows the "Hold to
      stop" hint); a ~1s hold with visible rising progress stops it; releasing
      early cancels with no state change.
- [ ] Haptics: a light impact at the start of the hold, a success tap on
      completion.
- [ ] **VoiceOver Stop custom action:** with VoiceOver on, the "Stop ride" custom
      action on the Stop control finalizes the ride without the timed hold.
- [ ] Signal-lost: let GPS stall (e.g., airplane mode briefly) → the amber "GPS
      signal lost — Your ride continues. Resuming…" banner appears; recovers when
      updates resume. VoiceOver announces the banner.
- [ ] State is always icon + text, never color alone.
- [ ] Screen stays awake while the ride screen is visible (idle timer disabled).
- [ ] Dynamic Type: the three metrics and Pause/Stop controls remain legible and
      do not truncate at large sizes.

## Ride summary

- [ ] After Stop, the summary shows distance, duration, average speed, and the
      full-route map for the just-finished ride.
- [ ] A zero/one-point ride shows a friendly "No route recorded" placeholder and
      sensible zeros (no NaN, no empty map crash).
- [ ] Sync-status row shows "On device" (icon + text) — sync is not built.
- [ ] "Done" returns to Home and the new ride appears in stats/recent.
- [ ] Opening a past ride from History reuses the same summary view.

## History

- [ ] Rides grouped by month under a header showing the month's ride count and
      total miles; months newest-first, rides newest-first.
- [ ] Each row shows date, distance, duration, and an "On device" sync indicator.
- [ ] Swipe-to-delete reveals Delete; confirming removes the ride permanently —
      it does NOT reappear after relaunch.
- [ ] Tapping a row opens its summary.
- [ ] Empty state is friendly (not a blank list / error).
- [ ] Persistence: finished rides survive an app relaunch.

## Settings

- [ ] GPS accuracy (Balanced / High) persists and survives relaunch; the chosen
      value applies to the next ride.
- [ ] "Units · Miles · mph" is read-only.
- [ ] "Delete all rides" → confirmation alert → wipes all history (verified after
      relaunch). A failure (if any) shows plain copy, never raw error text.
- [ ] Sync rows ("Sync rides to Whoosh map", "Privacy zone · 0.1 mi",
      "Identity · Anonymous") are disabled with "Coming soon".
- [ ] "Rear vehicle detection · Soon" row is disabled and **never** prompts for
      camera.
- [ ] VoiceOver: every row is labeled; disabled rows announce "coming soon".

---

## Resilience (task 24 / Requirement 11)

- [ ] **Permission revoked mid-ride:** revoke Location in Settings during a ride →
      the app stops appending points, shows "Location access turned off — Your
      ride is saved. Hold Stop to finish." (calm, actionable), and the user can
      stop & save the collected data. No crash, no lost ride.
- [ ] **Low Power Mode:** enable Low Power Mode, then start a ride → the app keeps
      recording at reduced (balanced) accuracy and does not crash. Toggle Low
      Power Mode mid-ride → the app keeps running (next location request uses the
      gentler accuracy).
- [ ] **Thermal throttling:** under a hot-device condition the app continues
      functioning at reduced accuracy (hard to force; spot-check it does not
      crash under sustained use).
- [ ] **Tracking released on stop:** after stopping a ride, Location indicator
      (status-bar arrow) turns off within a few seconds — no leaked tracking.
- [ ] **Storage fallback notice:** (hard to force) if the SwiftData store can't be
      created, the app still launches and shows the "Ride saving unavailable"
      notice instead of crashing.
- [ ] **Interrupted-ride recovery:** background the app mid-ride and force-quit,
      then relaunch → the "Finish your interrupted ride?" alert offers Save /
      Discard; Save finalizes the collected points into history.
- [ ] No user-facing message ever shows raw framework error text.

## Privacy & offline (task 25 / Requirements 9, 10.4)

- [ ] **Airplane mode full flow:** with Wi-Fi/cellular off, the complete
      record → summary → history → delete flow works end to end.
- [ ] No network activity while sync is off (sync is not built; verify no
      unexpected connections, e.g., via Console/Instruments if convenient).
- [ ] No camera permission prompt anywhere in the app.
- [ ] Delete and Delete-all are real, permanent local deletions (confirmed after
      relaunch).
- [ ] Copy never claims the app predicts/prevents/guarantees avoiding collisions;
      rear-detection is framed as "Experimental · coming soon".
- [ ] `Config/Secrets.xcconfig` is gitignored; only the example file is committed;
      no keys appear in source.

---

## Accessibility spot check (Requirement 10)

- [ ] VoiceOver: every interactive control across all screens has a meaningful
      label/trait.
- [ ] State banners (signal lost, paused) are announced, not just shown.
- [ ] The Stop press-and-hold has a working VoiceOver "Stop ride" custom action.
- [ ] Dynamic Type (up to Accessibility sizes) does not truncate primary ride
      metrics or controls; primary ride controls are ≥60pt touch targets.
- [ ] No state relies on color alone (icon + text everywhere).
