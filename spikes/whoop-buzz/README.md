# Spike: can the iPhone buzz a WHOOP 5.0?

Throwaway experiment, October 24, 2026. Sends the 5.0 `RUN_ALARM` command to a WHOOP 5.0 strap over
BLE and logs everything the strap says back. Answers one question: does the strap buzz, and does
it need anything besides the hello first?

Sources for the protocol (none verifies the 5.0 buzz on hardware):
- Frame format and `RUN_ALARM` data `[2, alarmID]`: `b-nnett/goose`, `Rust/core/src/protocol.rs` and
  `GooseSwift/GooseBLEClient.swift`.
- Hello bytes, UUIDs, and the 4.0 haptic command (`RUN_HAPTICS_PATTERN`, 79): `dbuffel/Whoop-Mac`,
  `docs/PROTOCOL.md`.

## Status

- `Shared/WhoopFrame.swift` passes 17 checks, including **rebuilding the known 16-byte hello byte
  for byte** from the command builder, which confirms the envelope and both CRCs:
  `swiftc -swift-version 6 Shared/WhoopFrame.swift Checks/main.swift -o /tmp/whoopcheck && /tmp/whoopcheck`
- The app compiles for the iOS Simulator. It has **never run against a real strap.** The simulator
  has no Bluetooth, so it needs a real iPhone.

## Run it

```
xcodegen generate && open WhoopBuzzSpike.xcodeproj
```

Pick your iPhone, run (signing team `Z87CXCTTK6` is set in `project.yml`).

1. **Close the official WHOOP app first** (force-quit it). The strap probably accepts one
   connection at a time. If the scan finds nothing, that is the first suspect.
2. Wear the strap or hold it, tap **Scan**, tap the strap in the list. The log should list the
   services and characteristics. iOS may show a Bluetooth pairing prompt; accept it.
3. Wait for "Ready", tap **1. Send hello** (a pairing prompt on this first write is expected; accept it), then **2. BUZZ: RUN_ALARM**.
4. Tap **Copy log** and paste it back, buzz or no buzz. The `←` lines are the strap's replies; a
   `COMMAND_RESPONSE` with the same seq as the command means it was accepted.

## How to read the result

| Outcome | Meaning |
| ------- | ------- |
| Strap buzzes | The 5.0 buzz works. Build the real `WhoopAlertSink`. |
| `COMMAND_RESPONSE` arrives, no buzz | Accepted but the data is wrong. Try the alternates (alarm id 1, haptics pattern 0 or 2). |
| No response at all | Not bonded, hello not accepted, or frame rejected. Check the log for write errors and whether the notify subscriptions succeeded. |
| Scan finds nothing | Strap is held by the WHOOP app or another phone. |

All commands sent are non-destructive. Reboot, firmware, trim, and DFU commands are deliberately
not in the builder.
