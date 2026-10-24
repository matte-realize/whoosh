# HazardDetection Contract — Whoosh

**Status: DRAFT, awaiting the 3-way OK** (iOS owner, Teammate B, Role C). Drafted by Role C
because `team-plan.md` makes C responsible for keeping the contracts honest. Nothing here is
frozen until all three people have said OK in writing (a line in the sign-off table below).

Version: 0.1 (draft, October 24, 2026)

The canonical Swift types belong to the iOS app (spec task 17, `design.md`, "HazardDetector").
This document records what each field means and who is responsible for what, so the detector
(B), the app (iOS) and the backend/website (C) agree. If this file and the Swift types
disagree, fix this file in the same change.

## The shape

```swift
struct HazardDetection: Sendable {
    let timestamp: Date
    let kind: String                      // open string, e.g. "vehicle"
    let confidence: Double                // 0...1
    let relativePositionHint: String?     // "left" | "center" | "right" | nil
}

protocol HazardDetector {
    var onDetection: ((HazardDetection) -> Void)? { get set }
    func start()
    func stop()
}
```

## Field meanings

| Field | Meaning | Rules |
| ----- | ------- | ----- |
| `timestamp` | When the detector decided the event occurred (wall-clock, from the frame time it used). | UTC instant. Stored as `near_misses.occurred_at`. |
| `kind` | What was detected. | Open string. MVP value: `"vehicle"`. New values need a line here first. The database stores any non-empty text. |
| `confidence` | The detector's score for this event. | 0...1. The database rejects values outside it. Not a calibrated probability: say "score" in any UI or copy. |
| `relativePositionHint` | Where the vehicle is relative to the rider. | `"left"`, `"center"`, `"right"`, or `nil`. Anything else must not be emitted (the database rejects it). |

## Decisions this draft proposes (each needs a yes/no)

1. **Rider frame, not image frame.** `left` and `right` are the rider's left and right while
   facing forward. The rear camera image is turned around: rider-left is the right side of the
   image. The detector (B) does the flip, not the app. This matches `side` in
   `vision/LABELING.md` section 3.2, and `vision/eval/` compares predictions to labels in the
   rider frame without flipping anything.
2. **One event per vehicle approach.** The detector emits one `HazardDetection` per approaching
   vehicle (it de-duplicates internally). The app owns alert behavior on top of that (cooldown,
   whether to vibrate), and the near-miss log keeps what the detector emitted.
3. **No location in the detection.** The detector does not know where the bike is. When the
   app logs a near miss it attaches the nearest accepted route point as `latitude` and
   `longitude` (that is how `near_misses` is defined).
4. **No images ever.** A detection carries no frame, crop, or video. Nothing the detector
   produces is uploaded except these four fields plus the location the app adds.
5. **Threading.** The detector does its work off the main actor and delivers `onDetection` on
   the main actor. It never blocks or slows ride recording, and any camera or model failure
   makes it stop silently.
6. **Camera permission** is requested only when the user turns detection on, never earlier.

## Mapping to the backend

| App / detector | `near_misses` column | Notes |
| -------------- | -------------------- | ----- |
| `timestamp` | `occurred_at` | `timestamptz`, UTC |
| `kind` | `kind` | `text not null` |
| `confidence` | `confidence` | `float8`, check `between 0 and 1` |
| `relativePositionHint` | `position_hint` | check `left`, `center`, `right`, or null |
| nearest route point (added by the app) | `latitude`, `longitude` | `float8 not null` |
| the ride being recorded | `ride_id` | must belong to the same user (enforced by RLS) |

The MVP app does not upload near misses. The sync work in iOS tasks 21–23 covers `rides` only.
The website shows near-miss markers from fixtures until a public near-miss view is decided
(see `supabase-contract.md`, "Open items").

## Honest-copy rule

Detection is experimental. No copy, UI, or pitch says it prevents or predicts collisions.
Performance numbers come only from `vision/REPORT.md` and are quoted with their sample size.

## Changing this contract

Any change needs the same 3-way OK, a version bump here, and a matching change to the Swift
types (iOS task 17), the golden fixtures (B), and `near_misses` if a column is involved (C).

## Sign-off

| Person | Role | OK (date) | Notes |
| ------ | ---- | --------- | ----- |
| | iOS owner | | |
| | Teammate B (vision) | | |
| | Teammate C (backend) | | |

Fill in the names and dates when each person agrees. Then change the status line to
**Agreed** and set the version to 1.0.
