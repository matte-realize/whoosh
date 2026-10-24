# Vision Subagent Tasks — Whoosh (Teammate B)

Status: PROPOSAL from Role C, not agreed with Teammate B. Written October 24, 2026.
Companion to `team-plan.md` (Teammate B's checkpoints) and the iOS design's detection seam
(`design.md`, "HazardDetector" section). Same format as `backend-subagent-tasks.md`: each task
is a self-contained brief for one `general-task-execution` subagent. Tasks marked **HUMAN** are
not delegated.

Who owns what: `team-plan.md` says C provides dataset and eval tooling, and B owns the
detector. So V1 (labeling spec) and V2 (eval scripts) are C's handoff to B, and V0 and V3–V6
are B's. B may change or drop any of them. Do not treat this file as B's plan until B agrees.

Progress (October 24, 2026):

| Task | State |
| ---- | ----- |
| V1 labeling spec, manifest template | Authored: `vision/LABELING.md`, `vision/README.md`, `vision/.gitignore`, `vision/data/MANIFEST.example.csv` |
| V2 eval scripts | Done and run: `vision/eval/` (`python3 run_toy.py` passes 107 checks) |
| V0, V3–V6 | Not started (B's call) |

## 1. What B delivers

From `team-plan.md`: a type conforming to `HazardDetector` that runs a vehicle-detection model
on-device from the rear camera and emits `HazardDetection` events, plus measured performance
numbers so the app's copy stays honest. B never imports app code; the iOS owner owns injection,
debouncing in the UI layer, and `AlertManager` playback.

The seam (copied from `design.md`; the iOS owner's task 17 owns the canonical version):

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

Contract rules that bind every task below: runs on-device, never blocks or slows ride recording,
inference work stays off the main actor, only `onDetection` hops back to it. The contract
freeze is a 3-way OK at Checkpoint 1 and has not happened yet. If the shape changes, only
`HazardContract.swift` (task V4) and the golden fixtures (task V3) change.

B emits no location. The iOS app attaches the nearest route point when it logs a near miss
(Role C's `near_misses` table: `kind`, `confidence`, `position_hint`, `occurred_at` come from
`HazardDetection`).

## 2. Where it lives and what must stay out of Git

New top-level folder `vision/`:

```
vision/
  README.md
  .gitignore          data/, clips, frames, *.mp4, *.mov, model weights, .venv
  MODEL_CHOICE.md     shortlist with verified licenses (task V0)
  LABELING.md         what counts as a positive, label format (task V1)
  data/               NOT in Git. Raw clips and frames.
  eval/               metrics + report scripts (task V2)
  detector/           baseline runner (task V3 input) and the approach rules prototype
  WhooshVision/       Swift package (tasks V4–V5)
  REPORT.md           measured numbers and the claims they allow (task V6)
```

Privacy rules from `privacy.md` apply: rear-camera video shows people, faces, and license
plates. Raw clips and frames never go in Git or a public bucket (`team-plan.md`: keep training
data off any public bucket). Only derived numbers, label files without images, and code are
committed. Detection is "experimental" in all copy.

## 3. What this machine can and cannot do

| Capability | State | Consequence |
| ---------- | ----- | ----------- |
| Swift toolchain | Swift 6.4 is installed | Subagents can try `swiftc -typecheck` on pure Swift files. Unverified for Vision/Core ML/AVFoundation imports. |
| Xcode | `xcodebuild` reports only Command Line Tools are active | No iOS SDK build, simulator, device install, or Core ML model compile from the agent. If Xcode is installed but not selected, `sudo xcode-select -s /Applications/Xcode.app` (yours to run). |
| Python | System Python is 3.9.6 | Current ML packages may not support it. Get a newer Python in a venv (HUMAN, e.g. with `uv`). Stdlib-only scripts still run here. |
| Network / installs | Blocked in the agent sandbox (Homebrew install failed earlier) | Subagents author code; you run anything that downloads weights or packages. |
| Camera and iPhone 14 | Yours | Recording clips and the on-device run are HUMAN. |

Rule for every brief: authoring only unless the brief says a command is safe to run. No
installs, no sudo, no sandbox changes, no network from the shell.

## 4. Decisions needed (defaults proposed)

| Decision | Default if you say "go" | Why |
| -------- | ----------------------- | --- |
| Model license path | Start from a permissively licensed pretrained detector, chosen in V0 | Ultralytics YOLO is AGPL-3.0: using it without an Enterprise License means open-sourcing the whole solution, including app code and fine-tuned weights ([discussion](https://community.ultralytics.com/t/yolov11-agpl-license-for-on-premises-use/1529), [license page](https://www.ultralytics.com/license)). That is workable only if the team publishes the whole repo. Your call. |
| Training data | Self-collected rear-facing clips, plus public data only for sanity checks | BDD100K is a front-facing dashcam set, and its download page sends commercial users to UC Berkeley licensing, so read its terms first ([BDD100K](http://bdd-data.berkeley.edu/download.html)). I did not search for a rear-facing cyclist dataset. |
| Detection approach | Pretrained object detector plus "approaching" rules (box growth over frames, class, left/center/right from box position) | No time to train a model from scratch. Rules are tunable against your clips. |
| Prototype language | Python first for tuning, Swift port checked against shared golden fixtures | Fast iteration on clips, and two implementations that provably agree. |
| Canonical contract file | iOS task 17 owns it; B keeps a mirror `HazardContract.swift` and deletes it on integration | Avoids duplicate type names in the app. |

## 5. Subagent task briefs

### V0. Model shortlist with verified licenses

Goal: produce `vision/MODEL_CHOICE.md` so the license decision is made on facts.

- Research 3–5 pretrained object detectors that can export to Core ML and detect cars, trucks,
  buses, and motorcycles (COCO-style classes), including Ultralytics YOLO as the baseline for
  comparison. For each: code license, weights license, any restriction on commercial or
  closed-source app use, Core ML export path, approximate model size and published input size.
- Cite a source URL for every license claim. If a license cannot be confirmed from a primary
  source, write "unverified" rather than guessing.
- End with a recommendation for a permissive option and a separate one for "if we open-source
  everything". Do not download anything. Writes only `vision/MODEL_CHOICE.md` (create the folder).
- Needs: web search and fetch. No shell commands required.

### V1. Labeling spec, clip protocol, and dataset manifest

Goal: define what "positive" means before anyone records or labels.

- `vision/LABELING.md`: definition of a positive event for a rear-facing bike camera (a
  vehicle behind the rider closing in, with a time window); what is not a positive (parked cars,
  vehicles passing on the opposite side); label format (a per-clip CSV or JSON with
  `clip_id, t_start_s, t_end_s, label, side`, plus optional per-frame boxes); how to handle
  ambiguous cases; minimum clip count and variety for a meaningful sample (daylight, dusk,
  rain if possible, different roads); phone mount position and orientation notes.
- `vision/data/MANIFEST.example.csv` (columns only, with two fake rows): clip id, date, location
  type, lighting, mount, fps, resolution, who recorded it, consent noted, source. Real
  manifests stay out of Git.
- `vision/.gitignore` as described in section 2. Also add the privacy rules (no faces or plates
  shared, no public buckets) to `vision/README.md`, along with the folder map.
- Writes only inside `vision/`. No data is created.

### V2. Evaluation metrics and report scripts

Goal: honest numbers from labeled clips, using only the Python standard library so they run
on this machine's Python 3.9.

- `vision/eval/metrics.py`: box IoU, greedy matching, per-class precision/recall, and
  event-level precision/recall/F1 (an event counts as detected if a predicted event falls
  within a configurable tolerance window of a labeled one), false alarms per hour of footage,
  and median detection lead time.
- `vision/eval/report.py`: reads predictions and labels (formats from V1), prints a Markdown
  table, and always prints the sample size (clips, events, hours) next to every number.
- Verification: a hand-built toy example in `vision/eval/toy/` whose expected output you can
  compute by hand, and a short script that runs it and compares. Run it with `python3`. Do not
  add third-party imports.
- Depends on: V1.

### V3. Approach rules prototype and golden fixtures

Goal: turn per-frame vehicle boxes into `HazardDetection`-shaped events, tunable in Python.

- `vision/detector/approach_rules.py` (stdlib only): input is a list of per-frame detections
  (`t, class, confidence, box x/y/w/h normalized`); output is events (`t, kind="vehicle",
  confidence, position_hint`). Rules: ignore boxes below a confidence floor and classes that
  are not vehicles; flag "approaching" when box height or area grows beyond a threshold over a
  sliding window; position hint from box center x (left/center/right thirds); cooldown so one
  vehicle yields one event. All thresholds in one `config.json`, none hard-coded.
- `vision/detector/golden/`: 6–10 small JSON cases (input detections, config, expected events)
  covering: no vehicles, parked/static box, steady approach, fast pass, two vehicles, jitter
  that must not trigger, and cooldown behavior. These are the shared source of truth the Swift
  port in V4 must reproduce exactly.
- A runner `run_golden.py` that checks every case; run it with `python3` and report results.
- Depends on: V1 (event definition).

### V4. Swift package: contract mirror, rules port, detector shell

Goal: the code the iOS owner will inject, written to compile without the app.

- `vision/WhooshVision/Package.swift` (Swift tools version matching the installed 6.x, iOS 17
  platform) and sources:
  - `HazardContract.swift`: the mirror from section 1, with a header comment that it must be
    deleted when merged into the app.
  - `ApproachRules.swift`: a Foundation-only port of V3 with the same config keys and
    `Sendable` value types. No SwiftUI, no CoreLocation.
  - `CoreMLVehicleDetector.swift`: conforms to `HazardDetector`. Holds a Vision
    `VNCoreMLRequest` over a model passed in at init (no model file in the package), runs
    inference on a dedicated actor or `@concurrent` work, delivers `onDetection` on the main
    actor, drops frames when busy instead of queueing, and treats any camera or model failure as
    "stop silently", never a crash and never touching ride recording.
  - `CameraFrameSource.swift`: AVFoundation capture that starts only when `start()` is called
    and requests camera permission at that moment, not earlier. Rear camera, low resolution
    preset, frame rate capped to what the detector sustains.
- Verification, all authoring-level: try `swiftc -typecheck` on the Foundation-only files
  (`HazardContract.swift`, `ApproachRules.swift`). If it works for the framework-importing
  files too, say so; if not, say that they are unverified. Do not run `swift build` or create an
  Xcode project.
- A `GoldenTests` target that loads V3's golden JSON and asserts identical events (Swift
  Testing, matching `tech.md`). Author it; it cannot run without Xcode or a working test
  toolchain, so report that explicitly.
- Depends on: V3.

### V5. Standalone harness app sources

Goal: the "tiny standalone harness" from `team-plan.md`, as source files ready to drop into an
Xcode project.

- `vision/Harness/` with SwiftUI sources: a camera preview, a start/stop button, a list of the
  latest `HazardDetection` events with timestamp, kind, confidence, and position hint, an
  on-screen frames-per-second and inference-time readout, and a recorder that writes the
  events to a JSON file for comparison with V2's labels. The harness depends on the
  `WhooshVision` package only.
- `vision/Harness/README.md`: exact Xcode steps (new iOS 17 app, add the local package, add the
  model, `NSCameraUsageDescription` text from `privacy.md`, signing for the iPhone 14).
- No `.xcodeproj` is generated. Creating the project is HUMAN (H3).
- Depends on: V4.

### V6. Performance report template and summarizer

Goal: make the final numbers hard to overstate.

- `vision/REPORT.md` template with sections for dataset description (sample sizes,
  conditions), event-level precision/recall, false alarms per hour, lead time, on-device
  frames per second, inference time, and thermal/battery observations over a fixed-length run
  on the iPhone 14. Each number has a "measured on / how" line.
- A section "Claims this supports" with the exact allowed phrasing, such as "experimental
  vehicle detection; in our test of N clips, ...", and a list of claims it does not support
  (no "prevents" or "predicts" collisions; no performance claims outside tested conditions).
- Depends on: V2.

### H1. HUMAN: environment

Install a current Python in a venv, select Xcode with `xcode-select`, and confirm the iPhone 14
is set up for development. Everything that downloads weights or packages runs from your
terminal, not the agent's.

### H2. HUMAN: record and label clips

Record the rear-facing clips per `LABELING.md`, keep them off Git and off public storage,
label them, and fill the real manifest. This is the work the team's numbers depend on; plan
for a few hours rather than minutes.

### H3. HUMAN: baseline run, Xcode wiring, on-device measurement

Run the chosen pretrained detector over your clips (script from V3's input format), feed the
output through V2 for the first precision/recall numbers (Checkpoint 1: no reliability
claims). Then create the Xcode harness project from V5, convert/export the model to Core ML,
run on the iPhone 14, and fill in `REPORT.md` (Checkpoint 2–3).

## 6. Order and checkpoints

```
V0 ─────────────────────────────┐ (feeds the H3 model choice)
V1 ─┬─ V2 ───────────── V6      │
    └─ V3 ─ V4 ─ V5 ────────────┴─ H3
H1, H2 in parallel with V0–V3
```

- Checkpoint 1 ("it records"): V0–V3 authored, H2 started, first offline numbers from H3's
  baseline run. No reliability claims.
- Checkpoint 2 ("it shows"): V4–V5 authored, harness running on the phone, events visible.
- Checkpoint 3 ("it warns"): tuned thresholds, `REPORT.md` filled in, handoff to the iOS owner.

V0, V1 can start immediately and in parallel. V2 and V3 can run in parallel once V1 lands.

## 7. Handoff to the iOS owner (done when)

- `WhooshVision` compiles in Xcode and the golden tests pass.
- The conforming `CoreMLVehicleDetector` takes the model at init; the app supplies it.
- `HazardContract.swift` is removed in favor of the app's task 17 types, with no other change.
- `REPORT.md` states what the numbers support. The app's copy uses that wording.
- The camera permission is requested only when the user turns detection on.
