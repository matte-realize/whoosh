# Spike: can an iPhone app buzz an Apple Watch during a ride?

Throwaway experiment, October 24, 2026. It lives outside the app (`Whoosh/`) on purpose. Its
purpose is to answer questions with measurements before anyone designs the real watch alert
(option C in `.kiro/team/vibration-alert-proposal.md`).

Status of the code:
- `Shared/HapticMessage.swift` compiles under Swift 6 and passes 14 round-trip and bad-input
  checks (run with `swiftc` here; no Xcode needed).
- `iPhone/` and `Watch/` have **never been compiled or run.** They need Xcode and the iOS and
  watchOS SDKs, which are not installed on the machine that wrote them. Expect a few compile
  errors on the first build; they are most likely API-name slips.

## What is known from research, and what is not

Sources are Apple Support and Apple developer forum threads, not Apple's reference docs, and
forum answers can be outdated. The point of the spike is to check them on your watch.

| Claim | Source | Status |
| ----- | ------ | ------ |
| A watch app can play haptics in the background only during an active workout session | Apple developer forums, thread 772780 | Test T4 |
| iPhone notifications mirror to the watch only when the iPhone is locked or asleep | [Apple Support](https://support.apple.com/en-us/108369) | During a ride the phone screen is on, so a plain phone notification will not buzz the watch. Test T6 |
| `sendMessage` reaches the watch app only when it is reachable (foreground, or high priority in the background such as a workout) | Apple developer forums, thread 723158 | Test T3, T4 |
| One forum thread reports `isReachable` false during a workout when the app is not displayed | Apple developer forums, thread 83612 (old, watchOS 4 era) | Test T4 |

## Setup in Xcode (about 20 minutes)

These steps are from memory and unverified against your Xcode version.

1. New project: iOS App, SwiftUI, name `WatchHapticSpike`. Add a watchOS target: File → New →
   Target → watchOS → Watch App (companion to the iPhone app). Pick your Apple Developer team
   for both targets so they install on real devices.
2. Add the files:
   - `Shared/HapticMessage.swift` to **both** targets.
   - `iPhone/*.swift` to the iPhone target. Make `PhoneContentView` the root view in the app
     entry point.
   - `Watch/*.swift` to the watch target. Make `WatchContentView` the root view.
3. Watch target → Signing & Capabilities → add **HealthKit**. In the watch target's Info.plist add
   `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` with a plain sentence such
   as "Used to keep the haptic test running during a cycling workout."
4. Both targets → Build Settings → Swift Language Mode: 5 (the spike's code is not written for
   strict concurrency).
5. Run on a real paired iPhone and Apple Watch. The simulator does not reproduce haptics or
   wrist-down behavior.
6. On the watch, allow the Health permission when asked.

## Test protocol

Record every result in the table below. Write what happened, not what you expected. A single
trial is an anecdote: repeat each test at least 5 times and write down how many of 5 worked.

Before you start: note the watch model, watchOS version, iPhone model, iOS version, and watch
battery percent. Turn Do Not Disturb and Focus off.

| # | Test | How | Record |
| - | ---- | --- | ------ |
| T1 | Feel | On the watch, tap each pattern in "Feel each haptic here", worn normally, then over a jacket sleeve or glove, then on a rough road while riding | Which patterns you can tell apart; which one you would notice while riding; which you would miss |
| T2 | Phone to watch, app on screen | Watch app visible, phone sends each pattern | Did it buzz (x of 5)? Median round trip shown on the phone |
| T3 | Wrist down, no workout | Watch app opened once, then drop the wrist so the screen sleeps, phone sends | x of 5 buzzed. Does the log show FAILED? |
| T4 | Wrist down, workout running | Start the cycling workout on the watch, drop the wrist, phone sends | x of 5 buzzed. Does the reply say "workout on"? |
| T5 | Phone app in foreground, screen on, as mounted on a bike | Same as T4 with the phone unlocked and the spike app on screen | x of 5 buzzed |
| T6 | Mirrored notification baseline (optional) | Schedule a normal local notification on the phone with its screen on, then with it locked | Did the watch buzz in each case? |
| T7 | Connection loss | During T4, switch the phone to airplane mode (Bluetooth back on, Wi-Fi off), then walk 10 m away | When does it start failing, and does it recover on its own? |
| T8 | Long run | Run a cycling workout for 30 minutes with the phone sending 'notification' every 5 s | Watch battery percent before and after; any dropped buzzes in the log |

## Reading the results

- **T4 passes (x of 5 near 5 of 5, repeated):** a watch companion app running a workout is a
  workable alert channel, and the next step is a design in the app spec.
- **T4 fails but T2 passes:** messages only work with the watch app in the foreground. The
  rider would have to keep the watch app on screen. That is a weak alert channel; say so.
- **T6 shows no buzz with the phone screen on:** confirms that plain notifications will not
  work during a ride.
- **Round trip numbers:** the phone logs them using only its own clock. They include the
  watch's reply, so they overestimate the one-way delay. Quote them with the conditions and
  sample size, or not at all.
- **Cost to flag:** a workout session also turns on the watch's sensors and affects battery.
  T8 measures that. It is a cost to the rider's watch, not a free alert.

## Not covered by this spike

- Starting the watch app's workout from the phone automatically (`HKHealthStore.startWatchApp`).
- Heart rate or any health data. The spike reads none and saves no workout to Health.
- Anything about WHOOP. The team's WHOOP 5.0 is covered in `spikes/ble-explorer/` and
  `.kiro/team/vibration-alert-proposal.md`.
- Production concerns: pairing flow, permissions copy, cooldown, fallbacks. Those go through
  the app owner and the `AlertManager` seam.

## Wording rule

Alerts are a caution cue from experimental detection. No copy says the watch warns of or
prevents collisions.
