# Proposal: Vibration alerts for the rear-vehicle caution (for the iOS owner)

Status: PROPOSAL from Role C, October 24, 2026. Nothing in `.kiro/specs/` has been edited.
Nothing here has been built or tested.

## 1. The problem

The caution alert should be felt, not seen: the rider should not need to look at a screen.
The team planned to use a WHOOP for this. A WHOOP band cannot do it:

- WHOOP 4.0 and 5.0 have a haptic alarm, but I found no public way for a third-party app to
  trigger it. A WHOOP community [feature request](https://www.community.whoop.com/t/feature-request-api-access-to-whoop-alarm-functionality/6594)
  asks for that ability, which suggests it does not exist. WHOOP's developer API is for reading
  recovery, sleep and workout data from their cloud, not for commanding the strap.
- The one thing WHOOP exposes to other apps over standard Bluetooth is heart rate broadcast.
  That has no vibration part, and it is not needed for this feature.
- The WHOOP model the team has is not known yet. If it turns out to be a model with an
  officially supported way to trigger haptics, this proposal changes. Check the model first.

Do not build on the WHOOP for alerts unless someone finds a documented way.

## 2. The seam that already exists

From `design.md`:

```swift
enum AlertKind { case cautionRearVehicle }
protocol AlertManager {
    // Haptic/audio alert. MUST never block or stop ride recording.
    func fire(_ kind: AlertKind)
}
```

The MVP ships `StubAlertManager`. Every option below is another `AlertManager` implementation,
so none of them touches the ride state machine, the detector, or the backend. The iOS owner
chooses which one is injected at the composition root, and can combine them.

## 3. Options

| Option | Extra hardware | Bluetooth code | Feel | Main risks |
| ------ | -------------- | -------------- | ---- | ---------- |
| A. Phone haptics (Core Haptics) | None | None | Only if the phone is on the rider's body or a handlebar mount that transmits vibration | May not be felt in a bag or a loose mount. |
| B. Audio cue through the rider's earbuds or helmet speaker | None | None (normal Bluetooth audio) | Audible | Traffic noise; some riders do not wear earbuds; audio ducking must not drown out ambient sound. |
| C. Apple Watch haptic | An Apple Watch the rider already owns | None directly (watch app, WatchConnectivity) | Strong wrist tap | Needs a watch app, which the product steering lists as not in the MVP. A mirrored phone notification only reaches the watch when the phone is locked, so it is not a reliable ride cue. |
| D. Custom Bluetooth vibration device (handlebar or glove) | A microcontroller board with a vibration motor, plus a way to power it | Yes: the phone is a Bluetooth central and writes to a custom characteristic | Reliable, placed where the team wants | Hardware must exist and be built; breaks the "no specialized hardware" goal; unmeasured connection latency; extra permission and pairing UX. |

## 4. Recommended order

1. **A and B first.** They need no hardware and no Bluetooth code, and they cover a demo. Ship
   them as `PhoneHapticAlertManager` and `AudioAlertManager`, with a small
   `CompositeAlertManager` that fires both.
2. **D only if the team has hardware and time.** It is the one that needs the Bluetooth
   integration you asked about. Keep it behind its own `AlertManager` implementation, with the
   phone alerts as the fallback, so a dropped connection never means a silent alert.
3. **C is a later milestone.** It matches the product vision (smartwatch alerts) but is a
   separate app target.

Open question for the team: does anyone have a microcontroller board, a Bluetooth vibration
device, or an Apple Watch available for the demo? That decides whether D or C is realistic.

**Update, October 24, 2026:** the team has an Apple Watch and chose to test option C first. A
throwaway experiment is in `spikes/watch-haptics/` (README has the test protocol). Its results
decide whether the watch is a workable alert channel. What research suggests, still to be
checked on the real watch: a watch app plays haptics in the background only during an active
workout session, and a plain phone notification does not reach the watch while the phone
screen is on. The WHOOP model is still unknown and is parked. Options A and B stay as the
fallback.

## 5. Rules every option follows

- `fire(_:)` returns immediately and never blocks, slows, or stops ride recording. Any failure
  (Bluetooth off, device out of range, haptics unavailable) is swallowed and logged, and the
  ride continues.
- Cooldown and debouncing live above the alert manager (iOS owns them), so a stream of
  detections does not become a stream of vibrations.
- The alert is a caution cue, never a collision warning in the copy. Detection stays
  "experimental" in the UI and the pitch.
- The camera permission and any Bluetooth permission are requested only when the user turns
  the related feature on. The Bluetooth usage string (`NSBluetoothAlwaysUsageDescription`)
  must say what the device is for and that nothing is sent to the cloud.
- Foreground, screen-on is the supported ride path in the MVP. Bluetooth in the background
  needs the `bluetooth-central` background mode, which the MVP does not enable.

## 6. Draft contract for option D (only if it is chosen)

First check whether the hardware already supports the Bluetooth SIG's standard Immediate Alert
service (`1802`, Alert Level characteristic `2A06`; write 0 = stop, 1 = mild, 2 = high). If it
does, use it and skip the custom contract below. `spikes/ble-explorer/` finds out in minutes.
Whether a device actually vibrates on it is up to the product: test, do not assume.

The phone is the Bluetooth central and the vibration device is the peripheral.

- One custom service with one write characteristic. The UUIDs are placeholders: generate real
  ones with `uuidgen` and record them here before anyone writes firmware.
  - Service UUID: `[generate]`
  - Command characteristic UUID: `[generate]`, properties: write without response
- One-byte command payload:

| Byte value | Meaning |
| ---------- | ------- |
| `0x00` | Stop vibrating |
| `0x01` | Short caution pulse pattern |
| `0x02` | Reserved |

- The peripheral advertises the service UUID and a name starting with `Whoosh`. The phone scans
  for that service only.
- The device vibrates for a fixed, short time on its own and then stops, so a lost connection
  can never leave it buzzing.
- A battery level characteristic is optional and not needed for the demo.
- Connection latency is **not measured**. Do not claim "instant" in any copy. Measure it on
  the real hardware and put the number, with its conditions, in the test notes before quoting it.

## 7. What each person would do

| Who | Work |
| --- | ---- |
| iOS owner | `AlertManager` implementations, composition-root choice, cooldown, settings, permissions. For D: a `CoreBluetooth` central wrapper behind a protocol with a fake, like `LocationTracking`. |
| Teammate B | No change. The detector's output is the same. |
| Role C | No schema change, and no data leaves the device for alerts. If alert events were ever logged, that goes through the existing `near_misses` table, not new columns. |
| Whoever has hardware | Build and test the device for D against section 6. |

## 8. Decisions needed

1. Which options: A and B only, or also D, or also C?
2. What hardware or watch does the team actually have?
3. What WHOOP model is it, and is anyone confident it can be made to vibrate from an app?
