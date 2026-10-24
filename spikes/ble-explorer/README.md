# Spike: what does this Bluetooth device offer, and can we make it alert?

Throwaway experiment, October 24, 2026. Use it as soon as the team has a device (the WHOOP, a
Bluetooth vibration gadget, a tracker, a watch-like band). It answers two questions with
evidence instead of guesses:

1. What services and characteristics does the device expose to a phone?
2. Is there a characteristic we can write to that makes it vibrate or beep?

Status of the code:
- `Shared/BLEFormat.swift` (hex, property names, UUID labels) compiles under Swift 6 and passes
  18 checks. Run them here with no Xcode:
  `swiftc -swift-version 6 Shared/BLEFormat.swift Checks/main.swift -o /tmp/blecheck && /tmp/blecheck`
- `iPhone/` has **never been compiled or run.** It needs Xcode, the iOS SDK, and a real iPhone
  (the simulator has no Bluetooth). Expect a few compile errors on the first build.
- Nothing has been tested against any real device.

## Step 0: no code needed, do this first

Install a free Bluetooth inspector on the iPhone (nRF Connect for Mobile and LightBlue are the
common ones; I did not check their current store listings). Scan, connect to the device, and
look at its services. This takes minutes and gives the same answers this spike gives. Build
the spike only if you want to script the write tests below or keep results in one place.

## The standard "make it alert" service

The Bluetooth SIG defines the **Immediate Alert** service (`1802`) with an **Alert Level**
characteristic (`2A06`). Writing 1 means mild alert and 2 means high alert; 0 stops it. A
device that implements it can be told to beep or vibrate with no custom protocol. Whether a
given product implements it, and what it does when it does, varies by product. The explorer
labels that characteristic so it is easy to spot, and offers write buttons for 0x00, 0x01
and 0x02 on any writable characteristic.

If a device has `1802 / 2A06`, the custom handlebar-device contract in
`.kiro/team/vibration-alert-proposal.md` (section 6) may be unnecessary.

## Setup in Xcode (about 15 minutes)

Unverified against your Xcode version.

1. New project: iOS App, SwiftUI, name `BLEExplorerSpike`. Pick your Apple Developer team.
2. Add `Shared/BLEFormat.swift`, `iPhone/BLEExplorer.swift` and `iPhone/ExplorerView.swift` to the
   target. Make `ExplorerView` the root view in the app entry point.
3. Target → Info → add `NSBluetoothAlwaysUsageDescription` with a plain sentence, for example
   "Whoosh Bluetooth test: scans for nearby devices to see what they offer. Nothing is stored
   or uploaded."
4. Build Settings → Swift Language Mode: 5.
5. Run on a real iPhone and allow the Bluetooth permission.

## Test protocol

Record what happened, not what you expected. Repeat each test at least 3 times and note how
many times it worked. Note the device model, firmware if shown, iOS version, and distance.

| # | Test | How | Record |
| - | ---- | --- | ------ |
| B1 | Visible | Scan with the device on and idle, then in its "pairing" or "broadcast" mode if it has one | Does it appear? Under what name? Signal strength at 1 m and 5 m |
| B2 | Services | Connect, wait for discovery | The full list of services, with properties for each characteristic. Paste the screen or the log |
| B3 | Identity | Read Device Information (`180A`) characteristics if present | Manufacturer, model, firmware strings, if the device shares them |
| B4 | Alert service | Look for `1802` and `2A06` | Present or absent |
| B5 | Write test | On any characteristic with a write property, write 0x01, then 0x02, then 0x00 | Did the device vibrate or beep? Did the write succeed or fail? Which characteristic? Do not write to characteristics you do not recognize on a device you care about |
| B6 | Reconnect | Disconnect, move out of range for a minute, come back | Does it reconnect, and how fast? |
| B7 | Second connection | With the vendor's own app also connected (for example the WHOOP app), try to connect from the explorer | Does it connect, fail, or disappear from the scan? |

## What to expect from WHOOP, and what is not known

- WHOOP can broadcast heart rate over the standard heart rate service when the rider turns
  Heart Rate Broadcast on in the WHOOP app (see `.kiro/team/vibration-alert-proposal.md` for
  sources). The strap may not appear in a scan, or may not accept a second connection, unless
  that is on or the vendor app is closed. Test B7 records which.
- I found no public way for a third-party app to trigger the WHOOP haptic. If B2 shows no
  writable characteristic besides ones for other purposes, that agrees. Do not write to
  unidentified WHOOP characteristics hoping to find the haptic: that is a way to confuse the
  strap's firmware, and it is outside what the vendor supports.
- The team's band is a **WHOOP 5.0**. Turn on Heart Rate Broadcast in the WHOOP app (Device
  Settings) before test B1, or the band may not show up. Recording what it exposes (B2) is fine;
  leave its other characteristics alone (see above).

## Reading the results

- **B4 present and B5 buzzes:** the standard service works on that device. Use it. The app's
  `AlertManager` implementation would be a small central that writes `2A06`.
- **B5 buzzes on a custom characteristic:** record its UUIDs and bytes. That becomes the
  contract for the app, and the proposal's section 6 gets filled in with real values.
- **No writable alert characteristic:** that device is not an alert channel. Use the Apple
  Watch spike (`spikes/watch-haptics/`) or phone haptics and audio.
- **Latency:** this spike does not measure it. Do not quote "instant". Measure it with a
  stopwatch or video of the write and the buzz, repeat it, and report the sample size.

## Not covered

- Pairing and bonding flows, background Bluetooth, and state restoration.
- Android.
- Reading any health data. The explorer's Read and Subscribe buttons show raw bytes only, and
  the log stays in memory.
