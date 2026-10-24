# Whoosh Vision

Work area for Teammate B: experimental on-device detection of vehicles approaching a bike's
rear camera, plus the data, labeling rules, and evaluation needed to measure it honestly.

The detector will plug into the iOS app through the `HazardDetector` seam described in
`.kiro/specs/ride-recording-mvp/design.md`. This folder never imports app code.

## Folder map

Status as of this writing. "Planned" means not created yet.

```
vision/
  README.md           exists   this file
  .gitignore          exists   keeps data, media, and model files out of Git
  LABELING.md         exists   what counts as a positive, label format, recording protocol
  data/               exists   private, NOT in Git except MANIFEST.example.csv
    MANIFEST.example.csv  exists   column layout with two fake rows
  MODEL_CHOICE.md     planned  model shortlist with verified licenses (task V0)
  eval/               planned  metrics and report scripts (task V2)
  detector/           planned  baseline runner and approach-rules prototype (task V3)
  WhooshVision/       planned  Swift package (tasks V4 and V5)
  Harness/            planned  standalone SwiftUI harness sources (task V5)
  REPORT.md           planned  measured numbers and the claims they allow (task V6)
```

## Privacy rules

These follow `.kiro/steering/privacy.md`. Rear-camera video shows faces, license plates,
and bystanders.

- Raw clips and frames never go in Git, in a public bucket, or on a shared link.
- Share clips only with teammates, on private storage.
- Real manifests and label files (`MANIFEST.csv`, `events.csv`, `boxes.jsonl`) reference
  private clips and are git-ignored. Commit only code, docs, fake examples, and derived
  numbers.
- Never publish a frame with a readable plate or a face. Do not show clips in the demo
  without blurring or consent.
- Get consent from anyone deliberately recorded (for example a teammate acting as a driver).
- Delete raw clips after the hackathon unless everyone agrees to keep them.

Full details are in `LABELING.md`, section 7.

## Wording rule: detection is experimental

- Call it "experimental vehicle detection".
- Never say it prevents or predicts collisions.
- Make no performance claim until the number is measured and reported in `REPORT.md`, with
  the sample size and conditions next to it. Until then, say nothing more than "we tried it
  on N clips".

The same rule applies to the app, the web dashboard, and the pitch.

## Related documents

- `.kiro/team/team-plan.md`: team roles and checkpoints.
- `.kiro/team/vision-subagent-tasks.md`: the task briefs (V0 to V6, H1 to H3) for this
  folder.
