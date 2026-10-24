# Whoosh Vision: Evaluation Scripts

Event-level metrics for the experimental vehicle detector. Python standard library only
(written for Python 3.9). No installs, no network. Task V2 in
`.kiro/team/vision-subagent-tasks.md`.

| File | Purpose |
| ---- | ------- |
| `metrics.py` | Pure functions: box IoU, event matching, precision/recall/F1, false alarms per hour, lead time, side confusion. |
| `report.py` | CLI. Reads labels and predictions, prints a Markdown report. |
| `run_toy.py` | Runs the toy case and edge cases with asserts. Exits nonzero on failure. |
| `toy/` | Hand-built example: `labels_toy.csv`, `predictions_toy.json`, `clips_toy.csv`. Totals are worked out by hand in the comment at the top of `run_toy.py`. |

## How to run

```sh
cd vision/eval
python3 run_toy.py        # self-check; prints PASS or FAIL per check
python3 report.py --labels toy/labels_toy.csv --predictions toy/predictions_toy.json --footage-seconds 360
python3 report.py --labels toy/labels_toy.csv --predictions toy/predictions_toy.json --clips toy/clips_toy.csv
```

`report.py` options:

| Option | Meaning |
| ------ | ------- |
| `--labels` | `events.csv` (required). |
| `--predictions` | Predictions JSON (required). |
| `--footage-seconds N` | Total footage evaluated, in seconds, including clips with no events. Needed for false alarms per hour. |
| `--clips CLIPS.csv` | Alternative to `--footage-seconds`: columns `clip_id,duration_s`. Footage is the sum, and the clip count in the report comes from this file. Every clip in the labels and predictions must be listed. |
| `--tolerance-s` | Matching tolerance in seconds. Default 1.0. |
| `--min-confidence C` | Drop predictions with confidence below `C` before matching. The report says how many were dropped. |
| `--show-rates-anyway` | Print rates even when there are fewer than 20 labeled events. The warning stays. Meant for checking the tool, not for quoting. |

Give exactly one of `--footage-seconds` and `--clips`. Bad input prints `error: ...` lines
(with line numbers for CSV rows) and exits with status 2.

## Formats

### Labels: `events.csv`

Exactly the format in `../LABELING.md` section 3.1. Header required, columns
`clip_id,t_start_s,t_end_s,label,side,vehicle_class,close_pass,notes`. `side` is in the
rider's frame: the rider's left is the right side of a backward-facing video image
(section 3.2). Real label files are git-ignored. Use a different file name for fakes, as in
`toy/labels_toy.csv`.

### Predictions: JSON list

```json
[
  { "clip_id": "clip_0001", "t_s": 9.0, "kind": "vehicle", "confidence": 0.9, "position_hint": "left" }
]
```

| Field | Type | Notes |
| ----- | ---- | ----- |
| `clip_id` | string | Same ids as the labels. |
| `t_s` | number >= 0 | Seconds from clip start. A single timestamp, not a window. |
| `kind` | string | Must be `"vehicle"`. |
| `confidence` | number 0 to 1 | Used only by `--min-confidence`. |
| `position_hint` | `"left"`, `"center"`, `"right"`, or `null` | May be omitted (read as `null`). Must already be in the rider's frame. The detector flips image coordinates. These scripts never flip anything. |

### Clips: `clips.csv` (optional)

Columns `clip_id,duration_s`. One row per clip, including clips with no events.

## The matching rule

Predictions and labels are matched one-to-one within the same `clip_id`.

1. A prediction matches a label if its time window overlaps the label window, or its
   time `t_s` lies in `[t_start_s - tolerance_s, t_end_s + tolerance_s]`. A prediction is a
   single timestamp, so "overlap" means `t_start_s <= t_s <= t_end_s`, which the tolerance
   interval already covers. Boundaries are inclusive.
2. Predictions are processed sorted by `(clip_id, t_s)`. Each takes the free matching label
   with the smallest distance to its window (ties: earlier start).
3. A label or prediction is used at most once. An unmatched prediction is a false positive,
   including a second prediction near a label that an earlier one already took. An unmatched
   label is a false negative.

Greedy matching is deterministic, not optimal: an early prediction can take a label that a
later one would fit better. Confidence is not used in matching.

## What each metric means, and what it does not

| Metric | Definition | What it does not tell you |
| ------ | ---------- | ------------------------- |
| True positives, false negatives, false positives | Counts from the matching above. | Nothing about why a miss happened. |
| Precision | TP / (TP + FP). Undefined (shown as "undefined") with no predictions. | Not the share of alerts a rider would find useful. A duplicate prediction on one event counts as a false positive. |
| Recall | TP / (TP + FN). Undefined with no labeled events. | Only covers events the labelers marked, on these clips. |
| F1 | 2TP / (2TP + FP + FN). Undefined if precision or recall is undefined. | It hides the trade-off between the two. Read the counts. |
| False alarms per hour | FP / (footage seconds / 3600). Undefined with zero footage. | Depends on how much quiet footage was recorded. A few minutes of footage gives a very noisy rate. |
| Lead time | Labeled `t_start_s` minus prediction `t_s`. Positive means before the labeled start, negative means late. | A matched lead never exceeds the tolerance, because earlier predictions are false positives. It says nothing about how much warning a rider would have, and it is not distance or time to impact. |
| Side confusion | Counts of (labeled side, predicted hint) for matched events, plus "missed". | Only as good as the `side` labels. If the detector reports image-left/right, left and right look swapped here. That is a detector bug to fix, not something this tool corrects. |
| Box IoU | Intersection over union of two normalized boxes. Zero-area boxes give 0.0. | Not used by `report.py` yet. It is there for the frame-level evaluation with `boxes.jsonl`. |

"Undefined" is always printed as undefined (`None` in code), never as 0 and never as NaN.

## Sample sizes come first

Every report starts with clips, labeled events, predicted events, and footage hours, and
every rate has its counts next to it (for example "4 of 7 predictions matched a labeled
event"). Quote the counts, not the percentage alone.

The report follows the tiers in `../LABELING.md` section 4:

| Labeled events | What the report does |
| -------------- | -------------------- |
| Fewer than 20 | Prints a warning that results are anecdotal and withholds every rate. Counts and lead times are still shown. The only claim this supports is "we tried it on N clips". |
| 20 to 49 | Prints a note: anecdotal, quote counts, not a single percentage. |
| 50 or more | Prints a note: still one bike, one phone, and these roads and conditions only. |

Other reminders:

- Do not tune thresholds and report numbers on the same clips without saying so.
- `--show-rates-anyway` does not make a small sample bigger.
- Nothing here supports a claim that the detector prevents or predicts collisions.
  Detection is experimental.
