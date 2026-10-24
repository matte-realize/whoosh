#!/usr/bin/env python3
"""Run the hand-built toy case through the same functions report.py uses.

    python3 run_toy.py

Prints PASS or FAIL per check and exits 0 only if every check passes. Standard library
only. Reads toy/labels_toy.csv, toy/predictions_toy.json and toy/clips_toy.csv.

Hand-computed expected values (tolerance 1.0 s, footage 3 clips x 120 s = 360 s)
--------------------------------------------------------------------------------
Labels (clip, window, side):
  L1 clip_0001 [10.0, 15.0] left     L4 clip_0002 [60.0, 64.0] left
  L2 clip_0001 [40.0, 45.0] center   L5 clip_0003 [30.0, 34.0] right
  L3 clip_0002 [20.0, 24.0] right
Predictions (clip, t_s, hint):
  P1 clip_0001  9.0 left    -> L1: 9.0 is exactly 10.0 - 1.0, inside tolerance. lead 10.0 - 9.0   = +1.0
  P2 clip_0001 41.5 center  -> L2: inside [40, 45].                          lead 40.0 - 41.5  = -1.5 (late)
  P3 clip_0002 20.0 right   -> L3: inside [20, 24].                          lead 20.0 - 20.0  =  0.0
  P4 clip_0002 21.0 right   -> L3 is already used by P3, no free label       => false positive (duplicate)
  P5 clip_0002 90.0 left    -> nothing within [59, 65] or [19, 25]           => false positive
  P6 clip_0003 29.5 left    -> L5: 29.5 >= 30.0 - 1.0, inside tolerance.     lead 30.0 - 29.5  = +0.5
  P7 clip_0003 100.0 null   -> nothing near L5                               => false positive
  L4 gets no prediction                                                      => false negative

Counts:      TP = 4 (P1-L1, P2-L2, P3-L3, P6-L5); FN = 1 (L4); FP = 3 (P4, P5, P7).
             Check: TP + FP = 7 predictions; TP + FN = 5 labeled events.
Precision:   4 / (4 + 3) = 4/7 = 0.571428...
Recall:      4 / (4 + 1) = 4/5 = 0.8
F1:          2*4 / (2*4 + 3 + 1) = 8/12 = 0.666666...
False alarms per hour: 3 / (360 / 3600) = 3 / 0.1 = 30.0
Lead times (processing order): [+1.0, -1.5, 0.0, +0.5]
Median lead: sorted [-1.5, 0.0, 0.5, 1.0]; mean of middle two = (0.0 + 0.5) / 2 = 0.25
Before / at / after labeled start: 2 (P1, P6) / 1 (P3) / 1 (P2).
Side confusion (labeled side, hint): (left,left)=1 (L1), (center,center)=1 (L2),
  (right,right)=1 (L3), (right,left)=1 (L5, the mismatch), (left,missed)=1 (L4).
  Side agreement: 3 of 4.

Variants:
  tolerance 0.5: P1 (9.0 < 10.0 - 0.5 = 9.5) no longer matches, so L1 becomes a false
                 negative and P1 a false positive. P6 (29.5 = 30.0 - 0.5) still matches
                 (boundary is inclusive). TP = 3 (P2, P3, P6), FN = 2 (L1, L4),
                 FP = 4 (P1, P4, P5, P7).
  min_confidence 0.5: drops P7 (0.4) only, so predictions = 6, TP = 4, FN = 1, FP = 2.
"""

from __future__ import annotations

import contextlib
import io
import math
import os
import sys
from typing import Callable, List, Optional

import metrics
import report
from metrics import LabeledEvent, PredictedEvent

HERE = os.path.dirname(os.path.abspath(__file__))
TOY = os.path.join(HERE, "toy")

_results = []  # type: List[bool]


def check(name: str, actual: object, expected: object, places: Optional[float] = None) -> None:
    """Compare and record. Floats are compared within 1e-9; None must equal None."""
    if isinstance(expected, float) and isinstance(actual, float):
        ok = math.isclose(actual, expected, rel_tol=0, abs_tol=1e-9 if places is None else places)
    else:
        ok = actual == expected
    if isinstance(actual, float) and math.isnan(actual):
        ok = False
    _results.append(ok)
    print("%s  %s: expected %r, actual %r" % ("PASS" if ok else "FAIL", name, expected, actual))


def check_true(name: str, condition: bool) -> None:
    _results.append(bool(condition))
    print("%s  %s" % ("PASS" if condition else "FAIL", name))


def check_raises(name: str, exc: type, fn: Callable[[], object]) -> None:
    try:
        fn()
    except exc:
        check_true(name, True)
    except Exception as other:  # wrong exception type
        check_true("%s (got %r)" % (name, other), False)
    else:
        check_true("%s (nothing raised)" % name, False)


def toy_case() -> None:
    print("== toy case ==")
    labeled = report.load_labels(os.path.join(TOY, "labels_toy.csv"))
    predicted = report.load_predictions(os.path.join(TOY, "predictions_toy.json"))
    durations = report.load_clips(os.path.join(TOY, "clips_toy.csv"))
    footage = sum(durations.values())
    check("labeled events", len(labeled), 5)
    check("predicted events", len(predicted), 7)
    check("clips in clips_toy.csv", len(durations), 3)
    check("footage seconds", footage, 360.0)

    ev = report.evaluate(labeled, predicted, footage, 1.0, None, list(durations))
    s = ev.scores
    check("true positives", s.true_positives, 4)
    check("false negatives", s.false_negatives, 1)
    check("false positives", s.false_positives, 3)
    check("precision 4/7", s.precision, 4.0 / 7.0)
    check("recall 4/5", s.recall, 0.8)
    check("f1 8/12", s.f1, 8.0 / 12.0)
    check("false alarms per hour", ev.fa_per_hour, 30.0)
    check("lead times", ev.leads, [1.0, -1.5, 0.0, 0.5])
    check("median lead", ev.median_lead, 0.25)
    check("unmatched labels (L4 = index 3)", ev.result.unmatched_labels, [3])
    check("unmatched predictions (P4,P5,P7)", ev.result.unmatched_predictions, [3, 4, 6])
    check(
        "matched pairs (label index, prediction index)",
        [(m.label_index, m.prediction_index) for m in ev.result.matches],
        [(0, 0), (1, 1), (2, 2), (4, 5)],
    )
    check(
        "side confusion",
        ev.confusion,
        {
            ("left", "left"): 1,
            ("center", "center"): 1,
            ("right", "right"): 1,
            ("right", "left"): 1,
            ("left", "missed"): 1,
        },
    )
    check("side agreement", metrics.side_agreement(ev.confusion), (3, 4))
    check("clips counted from clips file", ev.n_clips, 3)

    # Same case without a clips file: clip count comes from labels and predictions.
    ev_nc = report.evaluate(labeled, predicted, 360.0, 1.0)
    check("clips counted without clips file", ev_nc.n_clips, 3)

    # Variants.
    ev_t = report.evaluate(labeled, predicted, 360.0, 0.5)
    check("tolerance 0.5 TP/FN/FP", (ev_t.scores.true_positives, ev_t.scores.false_negatives, ev_t.scores.false_positives), (3, 2, 4))
    ev_c = report.evaluate(labeled, predicted, 360.0, 1.0, 0.5)
    check("min_confidence 0.5 predicted count", ev_c.n_predicted, 6)
    check("min_confidence 0.5 dropped", ev_c.n_dropped_by_confidence, 1)
    check("min_confidence 0.5 TP/FN/FP", (ev_c.scores.true_positives, ev_c.scores.false_negatives, ev_c.scores.false_positives), (4, 1, 2))

    # Rendering: 5 labeled events is below 20, so rates are withheld.
    text = report.render_markdown(ev)
    check_true("render: sample-size section comes first", text.index("## Sample size") < text.index("## Event metrics") < text.index("## Lead time") < text.index("## Side confusion"))
    check_true("render: warning line for < 20 events", "WARNING: only 5 labeled events" in text and "No rates should be quoted" in text)
    check_true("render: rates withheld below 20", "0.571" not in text and "0.800" not in text and "30.00" not in text)
    check_true("render: counts next to rates", "4 of 7 predictions" in text and "4 of 5 labeled events" in text and "3 false positives in 0.1000 hours" in text)
    check_true("render: lead counts", "2 of 4 matched events" in text and "1 of 4 matched events" in text)
    check_true("render: side agreement", "Side agreement: 3 of 4" in text)
    check_true("render: no nan or inf", "nan" not in text.lower() and "inf" not in text.lower())
    forced = report.render_markdown(ev, show_rates_anyway=True)
    check_true("render: --show-rates-anyway shows rates and keeps warning", "0.571" in forced and "0.800" in forced and "0.667" in forced and "30.00" in forced and "WARNING" in forced)

    # CLI end to end on the toy files.
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--clips", os.path.join(TOY, "clips_toy.csv")])
    check("CLI --clips exit code", code, 0)
    check_true("CLI --clips output matches render", out.strip() == text.strip())
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--footage-seconds", "360"])
    check("CLI --footage-seconds exit code", code, 0)


def run_cli(argv: List[str]) -> tuple:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = report.main(argv)
        except SystemExit as exc:  # argparse errors
            code = int(exc.code) if exc.code is not None else 0
    return code, out.getvalue(), err.getvalue()


def edge_cases() -> None:
    print("== edge cases ==")
    lab = [LabeledEvent("c", 10.0, 15.0, "left")]
    pred = [PredictedEvent("c", 12.0, 0.9, "left")]

    # Empty labels, some predictions: every prediction is a false positive.
    r = metrics.match_events([], pred, 1.0)
    s = metrics.event_scores(r)
    check("empty labels: TP/FN/FP", (s.true_positives, s.false_negatives, s.false_positives), (0, 0, 1))
    check("empty labels: precision is 0.0 (defined)", s.precision, 0.0)
    check("empty labels: recall is None", s.recall, None)
    check("empty labels: f1 is None", s.f1, None)

    # Empty predictions, some labels: every label is a false negative.
    r = metrics.match_events(lab, [], 1.0)
    s = metrics.event_scores(r)
    check("empty predictions: TP/FN/FP", (s.true_positives, s.false_negatives, s.false_positives), (0, 1, 0))
    check("empty predictions: precision is None", s.precision, None)
    check("empty predictions: recall is 0.0 (defined)", s.recall, 0.0)
    check("empty predictions: f1 is None", s.f1, None)
    check("empty predictions: side confusion has 'missed'", metrics.side_confusion(r.matches, lab), {("left", "missed"): 1})

    # Both empty.
    r = metrics.match_events([], [], 1.0)
    s = metrics.event_scores(r)
    check("both empty: precision/recall/f1", (s.precision, s.recall, s.f1), (None, None, None))
    check("both empty: lead times", metrics.lead_times(r.matches), [])
    check("both empty: median lead is None", metrics.median_lead_time([]), None)
    check("both empty: side confusion", metrics.side_confusion(r.matches, []), {})
    ev = report.evaluate([], [], 0.0, 1.0)
    text = report.render_markdown(ev)
    check_true("both empty: report renders with warning, no nan/inf", "WARNING: only 0 labeled events" in text and "nan" not in text.lower() and "inf" not in text.lower())
    check_true("both empty: undefined shown for lead time", "lead time is undefined" in text)

    # TP = 0 with both sides non-empty: F1 is a real 0.0.
    s = metrics.scores_from_counts(0, 2, 3)
    check("TP=0, FN=2, FP=3: precision/recall/f1", (s.precision, s.recall, s.f1), (0.0, 0.0, 0.0))

    # Zero / negative / non-finite footage.
    check("zero footage -> None", metrics.false_alarms_per_hour(3, 0.0), None)
    check("negative footage -> None", metrics.false_alarms_per_hour(3, -5.0), None)
    check("nan footage -> None", metrics.false_alarms_per_hour(3, float("nan")), None)
    check("zero footage with zero FP -> None (not 0)", metrics.false_alarms_per_hour(0, 0.0), None)
    check("positive footage, zero FP -> 0.0", metrics.false_alarms_per_hour(0, 3600.0), 0.0)
    check("1800 s, 3 FP -> 6.0", metrics.false_alarms_per_hour(3, 1800.0), 6.0)
    ev0 = report.evaluate(lab, pred, 0.0, 1.0)
    check("evaluate with zero footage: fa_per_hour", ev0.fa_per_hour, None)
    check_true("report with zero footage prints 'undefined'", "undefined" in report.render_markdown(ev0, show_rates_anyway=True))

    # Zero-area and degenerate boxes.
    check("zero-width box", metrics.box_iou((0.1, 0.1, 0.0, 0.5), (0.1, 0.1, 0.5, 0.5)), 0.0)
    check("zero-height box", metrics.box_iou((0.1, 0.1, 0.5, 0.0), (0.1, 0.1, 0.5, 0.5)), 0.0)
    check("both zero-area, identical", metrics.box_iou((0.2, 0.2, 0.0, 0.0), (0.2, 0.2, 0.0, 0.0)), 0.0)
    check("negative size", metrics.box_iou((0.2, 0.2, -0.1, 0.3), (0.2, 0.2, 0.3, 0.3)), 0.0)
    check("nan value", metrics.box_iou((float("nan"), 0.0, 0.5, 0.5), (0.0, 0.0, 0.5, 0.5)), 0.0)
    check("identical boxes", metrics.box_iou((0.1, 0.1, 0.4, 0.4), (0.1, 0.1, 0.4, 0.4)), 1.0)
    check("disjoint boxes", metrics.box_iou((0.0, 0.0, 0.2, 0.2), (0.5, 0.5, 0.2, 0.2)), 0.0)
    check("boxes touching on an edge", metrics.box_iou((0.0, 0.0, 0.5, 0.5), (0.5, 0.0, 0.5, 0.5)), 0.0)
    check("half-overlapping unit boxes: 0.5 / 1.5", metrics.box_iou((0.0, 0.0, 1.0, 1.0), (0.5, 0.0, 1.0, 1.0)), 1.0 / 3.0)
    check("contained box: 0.01 / 0.04", metrics.box_iou((0.0, 0.0, 0.2, 0.2), (0.05, 0.05, 0.1, 0.1)), 0.25)

    # Matching rules.
    one = [LabeledEvent("c", 10.0, 15.0, "left")]
    check_true("boundary before start is inclusive", len(metrics.match_events(one, [PredictedEvent("c", 9.0)], 1.0).matches) == 1)
    check_true("boundary after end is inclusive", len(metrics.match_events(one, [PredictedEvent("c", 16.0)], 1.0).matches) == 1)
    check_true("outside tolerance does not match", len(metrics.match_events(one, [PredictedEvent("c", 8.99)], 1.0).matches) == 0)
    check_true("tolerance 0: inside window still matches", len(metrics.match_events(one, [PredictedEvent("c", 12.0)], 0.0).matches) == 1)
    check_true("tolerance 0: just outside does not", len(metrics.match_events(one, [PredictedEvent("c", 9.99)], 0.0).matches) == 0)
    check_true("float boundary 12.4 - 1.0 = 11.4", len(metrics.match_events([LabeledEvent("c", 12.4, 14.0)], [PredictedEvent("c", 11.4)], 1.0).matches) == 1)
    check_true("different clip never matches", len(metrics.match_events(one, [PredictedEvent("other", 12.0)], 1.0).matches) == 0)
    r = metrics.match_events(one, [PredictedEvent("c", 12.0), PredictedEvent("c", 12.5)], 1.0)
    check("duplicate prediction: one TP, one FP", (len(r.matches), r.unmatched_predictions), (1, [1]))
    # Input order must not matter: sorted by clip_id then time.
    r = metrics.match_events(one, [PredictedEvent("c", 12.5), PredictedEvent("c", 12.0)], 1.0)
    check("input order does not change which prediction wins", (r.matches[0].prediction_index, r.unmatched_predictions), (1, [0]))
    # Two overlapping labels, two predictions: one-to-one.
    two = [LabeledEvent("c", 10.0, 14.0), LabeledEvent("c", 12.0, 16.0)]
    r = metrics.match_events(two, [PredictedEvent("c", 13.0), PredictedEvent("c", 13.5)], 0.0)
    check("two labels, two predictions: both matched", (len(r.matches), r.unmatched_labels, r.unmatched_predictions), (2, [], []))
    check_raises("negative tolerance raises ValueError", ValueError, lambda: metrics.match_events(one, [], -1.0))
    check_raises("nan tolerance raises ValueError", ValueError, lambda: metrics.match_events(one, [], float("nan")))

    # Unknown side and null hint are counted, not dropped.
    r = metrics.match_events([LabeledEvent("c", 1.0, 2.0, "unknown")], [PredictedEvent("c", 1.5, 0.9, None)], 1.0)
    conf = metrics.side_confusion(r.matches, [LabeledEvent("c", 1.0, 2.0, "unknown")])
    check("unknown side + null hint cell", conf, {("unknown", "none"): 1})
    check("agreement ignores unknown/none", metrics.side_agreement(conf), (0, 0))


def input_validation() -> None:
    print("== input validation (error messages, no stack traces) ==")
    header = "clip_id,t_start_s,t_end_s,label,side,vehicle_class,close_pass,notes\n"

    def label_errors(body: str, head: str = header) -> List[str]:
        try:
            report.parse_labels((head + body).splitlines(True), "L")
        except report.InputError as exc:
            return exc.messages
        return []

    msgs = label_errors("c1,5.0,4.0,approach,left,car,,\n")
    check_true("t_end <= t_start names line 2", len(msgs) == 1 and msgs[0].startswith("L line 2:") and "greater than" in msgs[0])
    msgs = label_errors("c1,1.0,2.0,approach,left,car,,\nc1,abc,2.0,approach,left,car,,\n")
    check_true("non-numeric t_start names line 3", len(msgs) == 1 and msgs[0].startswith("L line 3:") and "not a number" in msgs[0])
    msgs = label_errors("c1,1.0,2.0,approach,up,car,,\n")
    check_true("bad side", len(msgs) == 1 and "side" in msgs[0] and "line 2" in msgs[0])
    msgs = label_errors("c1,1.0,2.0,approach,left,tank,maybe,\n")
    check_true("bad vehicle_class and close_pass both reported", len(msgs) == 2)
    msgs = label_errors("c1,1.0,2.0,approach,left,car\n")
    check_true("short row names line 2", len(msgs) == 1 and "wrong number of fields" in msgs[0] and "line 2" in msgs[0])
    msgs = label_errors("c1,nan,2.0,approach,left,car,,\n")
    check_true("nan rejected", len(msgs) >= 1 and "not a number" in msgs[0])
    msgs = label_errors("", head="clip_id,t_start_s,t_end_s,label,side\n")
    check_true("missing header columns listed", len(msgs) == 1 and "missing column" in msgs[0] and "vehicle_class" in msgs[0])
    check_true("empty file", label_errors("", head="") == ["L: file is empty (a header row is required)"])
    check("valid header-only file parses to no events", report.parse_labels(header.splitlines(True), "L"), [])
    check("quoted notes with comma parse", len(report.parse_labels((header + 'c1,1.0,2.0,approach,left,car,,"a, b"\n').splitlines(True), "L")), 1)

    def pred_errors(text: str) -> List[str]:
        try:
            report.parse_predictions(text, "P")
        except report.InputError as exc:
            return exc.messages
        return []

    check_true("invalid JSON names line", any("line 1" in m and "invalid JSON" in m for m in pred_errors("[{")))
    check_true("non-list top level", pred_errors("{}") == ["P: top level must be a JSON list of objects"])
    msgs = pred_errors('[{"clip_id":"c","t_s":1,"kind":"vehicle","confidence":1.5,"position_hint":"up"}]')
    check_true("bad confidence and hint reported with item index", len(msgs) == 2 and all("item 0" in m for m in msgs))
    check_true("bool t_s rejected", len(pred_errors('[{"clip_id":"c","t_s":true,"kind":"vehicle","confidence":0.5}]')) == 1)
    check_true("missing position_hint is allowed", pred_errors('[{"clip_id":"c","t_s":1,"kind":"vehicle","confidence":0.5}]') == [])
    check("empty list parses", report.parse_predictions("[]", "P"), [])

    # CLI: user mistakes exit 2 and print "error:" without a traceback.
    code, out, err = run_cli(["--labels", os.path.join(TOY, "does_not_exist.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--footage-seconds", "10"])
    check_true("missing file: exit 2, readable error, no traceback", code == 2 and "error: cannot read" in err and "Traceback" not in err)
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json")])
    check_true("no footage: exit 2", code == 2 and "--footage-seconds" in err)
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--footage-seconds", "10", "--clips", os.path.join(TOY, "clips_toy.csv")])
    check_true("both footage sources: exit 2", code == 2 and "not both" in err)
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--footage-seconds", "-1"])
    check_true("negative footage: exit 2", code == 2)
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--footage-seconds", "360", "--min-confidence", "2"])
    check_true("bad min-confidence: exit 2", code == 2)
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--footage-seconds", "0"])
    check("zero footage via CLI: exit code", code, 0)
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "predictions_toy.json"), "--footage-seconds", "0", "--show-rates-anyway"])
    check_true("zero footage via CLI: false alarms shown as undefined", code == 0 and "| False alarms per hour | undefined |" in out)
    # Labels file given as predictions: readable error.
    code, out, err = run_cli(["--labels", os.path.join(TOY, "labels_toy.csv"), "--predictions", os.path.join(TOY, "labels_toy.csv"), "--footage-seconds", "10"])
    check_true("wrong file as predictions: exit 2 with JSON error", code == 2 and "invalid JSON" in err and "Traceback" not in err)


def main() -> int:
    toy_case()
    edge_cases()
    input_validation()
    failed = _results.count(False)
    print()
    if failed:
        print("FAIL: %d of %d checks failed" % (failed, len(_results)))
        return 1
    print("PASS: all %d checks passed" % len(_results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
