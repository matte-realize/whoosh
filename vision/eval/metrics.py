"""Evaluation metrics for Whoosh vision (task V2). Standard library only.

Everything here is a pure function over plain values. Nothing reads files, prints, or
flips coordinates. File parsing and printing live in ``report.py``.

Conventions
-----------
* Times are seconds from the start of the clip file.
* Boxes are normalized ``(x, y, w, h)`` with ``(x, y)`` the top-left corner and the
  origin at the top-left of the image (LABELING.md section 3.4).
* "Undefined" is ``None``. A rate whose denominator is zero is never reported as 0 and
  never as NaN.
* ``side`` / ``position_hint`` are in the RIDER's frame (LABELING.md section 3.2). See
  ``side_confusion``.
"""

from __future__ import annotations

import math
import statistics
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

Box = Tuple[float, float, float, float]

# Slack for comparing floating point times at the tolerance boundary
# (for example 12.4 - 1.0 versus a prediction at 11.4).
_EPS = 1e-9

#: Labeled sides, rows of the side-confusion table.
SIDE_VALUES = ("left", "center", "right", "unknown")
#: Predicted hints plus the two bookkeeping columns, in display order.
HINT_COLUMNS = ("left", "center", "right", "none", "missed")


@dataclass(frozen=True)
class LabeledEvent:
    """One ground-truth event (a row of events.csv)."""

    clip_id: str
    t_start_s: float
    t_end_s: float
    side: str = "unknown"  # rider's frame: left | center | right | unknown


@dataclass(frozen=True)
class PredictedEvent:
    """One detector output: a single timestamp, not a window."""

    clip_id: str
    t_s: float
    confidence: float = 1.0
    position_hint: Optional[str] = None  # rider's frame: left | center | right | None


@dataclass(frozen=True)
class Match:
    """A predicted event paired with a labeled event.

    ``label_index`` and ``prediction_index`` are positions in the sequences that were
    passed to ``match_events``.
    """

    label_index: int
    prediction_index: int
    labeled: LabeledEvent
    predicted: PredictedEvent


@dataclass(frozen=True)
class MatchResult:
    """Output of ``match_events``.

    ``matches`` are in processing order (clip_id, then prediction time). The two
    unmatched lists hold input indices in ascending order.
    """

    matches: List[Match]
    unmatched_labels: List[int]  # false negatives
    unmatched_predictions: List[int]  # false positives


@dataclass(frozen=True)
class EventScores:
    """Counts plus precision / recall / F1. A rate is ``None`` when it is undefined."""

    true_positives: int
    false_negatives: int
    false_positives: int
    precision: Optional[float]
    recall: Optional[float]
    f1: Optional[float]


# --------------------------------------------------------------------------- boxes


def box_iou(a: Box, b: Box) -> float:
    """Intersection over union of two normalized ``(x, y, w, h)`` boxes.

    ``(x, y)`` is the top-left corner, ``w`` and ``h`` the size, all in the same units
    (normally 0..1). Returns a float in ``[0.0, 1.0]``.

    Returns ``0.0`` (no exception) when either box has zero or negative width or height,
    or when the union is zero, or when any value is not finite.
    """
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    if not all(math.isfinite(v) for v in (ax, ay, aw, ah, bx, by, bw, bh)):
        return 0.0
    if aw <= 0.0 or ah <= 0.0 or bw <= 0.0 or bh <= 0.0:
        return 0.0
    inter_w = min(ax + aw, bx + bw) - max(ax, bx)
    inter_h = min(ay + ah, by + bh) - max(ay, by)
    if inter_w <= 0.0 or inter_h <= 0.0:
        return 0.0
    inter = inter_w * inter_h
    union = aw * ah + bw * bh - inter
    if union <= 0.0:
        return 0.0
    return inter / union


# ------------------------------------------------------------------------ matching


def _window_gap(label: LabeledEvent, t_s: float) -> float:
    """Distance in seconds from ``t_s`` to the label window (0.0 if inside it)."""
    if t_s < label.t_start_s:
        return label.t_start_s - t_s
    if t_s > label.t_end_s:
        return t_s - label.t_end_s
    return 0.0


def _is_match(label: LabeledEvent, pred: PredictedEvent, tolerance_s: float) -> bool:
    inside = label.t_start_s - _EPS <= pred.t_s <= label.t_end_s + _EPS
    near = (
        label.t_start_s - tolerance_s - _EPS
        <= pred.t_s
        <= label.t_end_s + tolerance_s + _EPS
    )
    return inside or near


def match_events(
    labeled: Sequence[LabeledEvent],
    predicted: Sequence[PredictedEvent],
    tolerance_s: float,
) -> MatchResult:
    """Greedy one-to-one matching of predicted events to labeled events.

    Matching rule (exact):

    1. A prediction ``p`` can match a label ``l`` only if ``p.clip_id == l.clip_id``.
    2. Within a clip, ``p`` matches ``l`` if the time windows overlap, OR if the
       prediction time ``p.t_s`` lies in the closed interval
       ``[l.t_start_s - tolerance_s, l.t_end_s + tolerance_s]``.
       A prediction is a single timestamp, so its "window" is the point ``[t_s, t_s]``
       and the overlap clause means ``l.t_start_s <= t_s <= l.t_end_s``. That case is
       already inside the tolerance interval; it is spelled out so that the rule still
       reads correctly when ``tolerance_s`` is 0. Boundaries are inclusive (with a
       1e-9 s slack for floating point).
    3. Predictions are processed in ascending order of ``(clip_id, t_s, input index)``.
       For each prediction, among the labels in its clip that have NOT been used yet
       and that it matches, it takes the one with the smallest distance from ``t_s`` to
       the label window (0 when inside), breaking ties by earlier ``t_start_s``, then
       earlier ``t_end_s``, then lower input index.
    4. Each label and each prediction is used at most once. A prediction that finds no
       free matching label is a false positive (this includes a second prediction near a
       label that an earlier prediction already took). A label never taken is a false
       negative.

    Greedy means an earlier prediction can take a label that a later prediction would
    have matched more closely. The result is deterministic, not optimal.

    Confidence is not used. Apply any confidence filter before calling.

    Raises ``ValueError`` if ``tolerance_s`` is negative or not finite.
    """
    if not math.isfinite(tolerance_s) or tolerance_s < 0:
        raise ValueError("tolerance_s must be a finite number >= 0")

    labels_by_clip: Dict[str, List[int]] = {}
    for i, lab in enumerate(labeled):
        labels_by_clip.setdefault(lab.clip_id, []).append(i)

    order = sorted(
        range(len(predicted)), key=lambda i: (predicted[i].clip_id, predicted[i].t_s, i)
    )

    used_labels = set()  # type: set
    matched_preds = set()  # type: set
    matches = []  # type: List[Match]

    for pi in order:
        pred = predicted[pi]
        best = None  # type: Optional[Tuple[float, float, float, int]]
        for li in labels_by_clip.get(pred.clip_id, []):
            if li in used_labels:
                continue
            lab = labeled[li]
            if not _is_match(lab, pred, tolerance_s):
                continue
            key = (_window_gap(lab, pred.t_s), lab.t_start_s, lab.t_end_s, li)
            if best is None or key < best:
                best = key
        if best is None:
            continue
        li = best[3]
        used_labels.add(li)
        matched_preds.add(pi)
        matches.append(Match(li, pi, labeled[li], pred))

    return MatchResult(
        matches=matches,
        unmatched_labels=[i for i in range(len(labeled)) if i not in used_labels],
        unmatched_predictions=[
            i for i in range(len(predicted)) if i not in matched_preds
        ],
    )


# ------------------------------------------------------------------------- scores


def _ratio(numerator: float, denominator: float) -> Optional[float]:
    if denominator <= 0:
        return None
    return numerator / denominator


def scores_from_counts(
    true_positives: int, false_negatives: int, false_positives: int
) -> EventScores:
    """Build ``EventScores`` from raw counts.

    * precision = TP / (TP + FP), ``None`` when there are no predictions.
    * recall    = TP / (TP + FN), ``None`` when there are no labeled events.
    * f1        = 2PR / (P + R) (equivalently 2TP / (2TP + FP + FN)), ``None`` when
      precision or recall is ``None``. It is 0.0 only when both are defined and TP is 0.

    Never divides by zero, never returns NaN, never reports 0 for "undefined".
    """
    tp, fn, fp = true_positives, false_negatives, false_positives
    if tp < 0 or fn < 0 or fp < 0:
        raise ValueError("counts must be >= 0")
    precision = _ratio(tp, tp + fp)
    recall = _ratio(tp, tp + fn)
    f1 = None  # type: Optional[float]
    if precision is not None and recall is not None:
        f1 = _ratio(2 * tp, 2 * tp + fp + fn)
    return EventScores(tp, fn, fp, precision, recall, f1)


def event_scores(result: MatchResult) -> EventScores:
    """Event-level counts and scores from a ``MatchResult``.

    TP = matched pairs, FN = unmatched labels, FP = unmatched predictions.
    See ``scores_from_counts`` for the rate definitions.
    """
    return scores_from_counts(
        len(result.matches),
        len(result.unmatched_labels),
        len(result.unmatched_predictions),
    )


def false_alarms_per_hour(
    false_positives: int, footage_seconds: float
) -> Optional[float]:
    """False positives per hour of footage.

    ``false_positives / (footage_seconds / 3600)``. Returns ``None`` (undefined) when
    ``footage_seconds`` is zero, negative, or not finite. Footage means all footage
    evaluated, including clips with no labeled events.
    """
    if not math.isfinite(footage_seconds) or footage_seconds <= 0:
        return None
    return false_positives / (footage_seconds / 3600.0)


# --------------------------------------------------------------------- lead times


def lead_times(matches: Sequence[Match]) -> List[float]:
    """Detection lead time in seconds for each match, in the order given.

    ``lead = labeled.t_start_s - predicted.t_s`` with no clamping:
    positive means the vehicle was detected BEFORE the labeled start, negative means
    AFTER it (late), zero means exactly at the start.

    Because matching only accepts predictions inside
    ``[t_start_s - tolerance_s, t_end_s + tolerance_s]``, matched lead times are never
    larger than ``tolerance_s``. Earlier detections are scored as false positives, so
    this statistic understates how early a detector fires.
    """
    return [m.labeled.t_start_s - m.predicted.t_s for m in matches]


def median_lead_time(leads: Sequence[float]) -> Optional[float]:
    """Median of lead times in seconds, or ``None`` for empty input.

    For an even count this is the mean of the two middle values.
    """
    if len(leads) == 0:
        return None
    return float(statistics.median(leads))


# ---------------------------------------------------------------- side confusion


def side_confusion(
    matches: Sequence[Match], labeled: Sequence[LabeledEvent]
) -> Dict[Tuple[str, str], int]:
    """Count (labeled side, predicted position_hint) pairs.

    Frame of reference (LABELING.md section 3.2): ``side`` in the labels is the RIDER's
    left/right, seen facing forward. With a backward-facing camera the rider's left is
    the RIGHT of the video image. A prediction's ``position_hint`` is expected to be in
    the same rider frame; the detector is responsible for flipping image coordinates.
    This function does NOT flip anything. If a detector emits image-frame hints, the
    left/right cells will look swapped here, and that is the signal to fix the detector.

    Keys are ``(labeled_side, column)``:

    * one entry per match: ``column`` is the prediction's ``position_hint``
      (``"left"``, ``"center"``, ``"right"``), or ``"none"`` when it is ``None``;
    * one entry per labeled event that has no match, with ``column`` = ``"missed"``.

    ``labeled`` must be the same sequence that was given to ``match_events`` (indices in
    ``Match.label_index`` refer to it). False-positive predictions have no labeled side
    and are not counted here. Only non-zero cells are present.
    """
    counts = {}  # type: Dict[Tuple[str, str], int]
    matched_labels = set()
    for m in matches:
        matched_labels.add(m.label_index)
        hint = m.predicted.position_hint
        key = (m.labeled.side, hint if hint is not None else "none")
        counts[key] = counts.get(key, 0) + 1
    for i, lab in enumerate(labeled):
        if i not in matched_labels:
            key = (lab.side, "missed")
            counts[key] = counts.get(key, 0) + 1
    return counts


def side_agreement(confusion: Dict[Tuple[str, str], int]) -> Tuple[int, int]:
    """Return ``(agree, comparable)`` from a ``side_confusion`` table.

    ``comparable`` counts matched events whose labeled side is left/center/right and
    whose prediction carried a hint. ``agree`` counts those where the two are equal.
    """
    comparable = 0
    agree = 0
    for (side, col), n in confusion.items():
        if side in ("left", "center", "right") and col in ("left", "center", "right"):
            comparable += n
            if side == col:
                agree += n
    return agree, comparable
