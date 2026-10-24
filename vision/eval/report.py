#!/usr/bin/env python3
"""Print a Markdown evaluation report for Whoosh vision (task V2). Standard library only.

Usage::

    python3 report.py --labels LABELS.csv --predictions PREDICTIONS.json \\
        --footage-seconds N [--tolerance-s 1.0] [--min-confidence C] [--clips CLIPS.csv]

Inputs
------
``--labels``: ``events.csv`` exactly as in vision/LABELING.md section 3.1. Header row
required, with columns ``clip_id,t_start_s,t_end_s,label,side,vehicle_class,close_pass,notes``
(any order, all eight present). Row checks: ``t_end_s > t_start_s >= 0``, ``label`` is
``approach``, ``side`` is left/center/right/unknown (rider's frame), ``vehicle_class`` is
car/truck/bus/motorcycle/other, ``close_pass`` is yes/no/empty.

``--predictions``: a JSON list of objects::

    { "clip_id": str, "t_s": float, "kind": "vehicle",
      "confidence": float (0..1),
      "position_hint": "left" | "center" | "right" | null }

``t_s`` is seconds from clip start. ``position_hint`` may be omitted (treated as null) and
is expected in the RIDER's frame (the detector flips image coordinates; this tool does not).

Footage: give exactly one of ``--footage-seconds N`` (total seconds of footage evaluated,
including clips with no events) or ``--clips CLIPS.csv`` (columns ``clip_id,duration_s``;
footage is the sum, and every clip_id in labels and predictions must be listed).

Output is numbers and counts only. Sample size comes first. Exit status: 0 on success,
2 on bad input or bad arguments.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import metrics
from metrics import (
    EventScores,
    LabeledEvent,
    MatchResult,
    PredictedEvent,
)

LABEL_COLUMNS = (
    "clip_id",
    "t_start_s",
    "t_end_s",
    "label",
    "side",
    "vehicle_class",
    "close_pass",
    "notes",
)
SIDES = ("left", "center", "right", "unknown")
VEHICLE_CLASSES = ("car", "truck", "bus", "motorcycle", "other")
CLOSE_PASS_VALUES = ("yes", "no", "")
HINTS = ("left", "center", "right")

# Sample-size tiers from LABELING.md section 4.
TIER_NO_RATES_BELOW = 20  # fewer than about 20 events: no rates, no percentages
TIER_LIMITED_FROM = 50  # 50 or more: still a small one-bike, one-phone sample

MAX_ERRORS_SHOWN = 20


class InputError(Exception):
    """User-facing input problem. ``messages`` are printed one per line."""

    def __init__(self, messages: Sequence[str]) -> None:
        super().__init__("; ".join(messages))
        self.messages = list(messages)


# ------------------------------------------------------------------------ parsing


def _parse_float(text: str) -> float:
    value = float(text.strip())  # ValueError for non-numbers
    if not math.isfinite(value):
        raise ValueError("not finite")
    return value


def parse_labels(lines: Iterable[str], source: str = "labels") -> List[LabeledEvent]:
    """Parse and validate events.csv text. Raises ``InputError`` naming line numbers."""
    reader = csv.DictReader(lines)
    if reader.fieldnames is None:
        raise InputError(["%s: file is empty (a header row is required)" % source])
    names = [(n or "").strip() for n in reader.fieldnames]
    reader.fieldnames = names
    missing = [c for c in LABEL_COLUMNS if c not in names]
    if missing:
        raise InputError(
            [
                "%s line 1: header is missing column(s): %s. Expected: %s"
                % (source, ", ".join(missing), ",".join(LABEL_COLUMNS))
            ]
        )

    events = []  # type: List[LabeledEvent]
    errors = []  # type: List[str]
    try:
        for row in reader:
            line = reader.line_num
            if not any((v or "").strip() for v in row.values() if isinstance(v, str)):
                continue  # blank line
            problems = []  # type: List[str]
            if None in row or any(v is None for v in row.values()):
                problems.append(
                    "wrong number of fields (expected %d); quote notes that contain commas"
                    % len(names)
                )
                errors.extend("%s line %d: %s" % (source, line, p) for p in problems)
                continue
            clip_id = row["clip_id"].strip()
            if not clip_id:
                problems.append("clip_id is empty")
            start = end = None  # type: Optional[float]
            try:
                start = _parse_float(row["t_start_s"])
            except ValueError:
                problems.append("t_start_s %r is not a number" % row["t_start_s"])
            try:
                end = _parse_float(row["t_end_s"])
            except ValueError:
                problems.append("t_end_s %r is not a number" % row["t_end_s"])
            if start is not None and start < 0:
                problems.append("t_start_s %s is negative" % row["t_start_s"].strip())
            if start is not None and end is not None and end <= start:
                problems.append(
                    "t_end_s (%s) must be greater than t_start_s (%s)"
                    % (row["t_end_s"].strip(), row["t_start_s"].strip())
                )
            if row["label"].strip() != "approach":
                problems.append(
                    "label %r is not allowed (only 'approach')" % row["label"].strip()
                )
            side = row["side"].strip()
            if side not in SIDES:
                problems.append("side %r must be one of %s" % (side, "/".join(SIDES)))
            vclass = row["vehicle_class"].strip()
            if vclass not in VEHICLE_CLASSES:
                problems.append(
                    "vehicle_class %r must be one of %s"
                    % (vclass, "/".join(VEHICLE_CLASSES))
                )
            close_pass = row["close_pass"].strip()
            if close_pass not in CLOSE_PASS_VALUES:
                problems.append("close_pass %r must be yes, no, or empty" % close_pass)
            if problems:
                errors.extend("%s line %d: %s" % (source, line, p) for p in problems)
            elif start is not None and end is not None:
                events.append(LabeledEvent(clip_id, start, end, side))
    except csv.Error as exc:
        errors.append("%s line %d: CSV syntax error: %s" % (source, reader.line_num, exc))
    if errors:
        raise InputError(errors)
    return events


def parse_predictions(text: str, source: str = "predictions") -> List[PredictedEvent]:
    """Parse and validate predictions JSON text. Raises ``InputError``."""
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InputError(
            ["%s line %d column %d: invalid JSON: %s" % (source, exc.lineno, exc.colno, exc.msg)]
        )
    if not isinstance(data, list):
        raise InputError(["%s: top level must be a JSON list of objects" % source])

    events = []  # type: List[PredictedEvent]
    errors = []  # type: List[str]
    for i, item in enumerate(data):
        where = "%s item %d (0-based)" % (source, i)
        if not isinstance(item, dict):
            errors.append("%s: must be an object" % where)
            continue
        problems = []  # type: List[str]
        clip_id = item.get("clip_id")
        if not isinstance(clip_id, str) or not clip_id.strip():
            problems.append("clip_id must be a non-empty string")
        t_s = item.get("t_s")
        if isinstance(t_s, bool) or not isinstance(t_s, (int, float)) or not math.isfinite(t_s) or t_s < 0:
            problems.append("t_s must be a finite number >= 0")
        kind = item.get("kind")
        if kind != "vehicle":
            problems.append("kind must be \"vehicle\" (got %r)" % (kind,))
        conf = item.get("confidence")
        if isinstance(conf, bool) or not isinstance(conf, (int, float)) or not (0.0 <= conf <= 1.0):
            problems.append("confidence must be a number from 0 to 1")
        hint = item.get("position_hint")
        if hint is not None and hint not in HINTS:
            problems.append("position_hint must be left, center, right, or null (got %r)" % (hint,))
        if problems:
            errors.extend("%s: %s" % (where, p) for p in problems)
        else:
            events.append(PredictedEvent(clip_id.strip(), float(t_s), float(conf), hint))
    if errors:
        raise InputError(errors)
    return events


def parse_clips(lines: Iterable[str], source: str = "clips") -> Dict[str, float]:
    """Parse a ``clip_id,duration_s`` CSV into ``{clip_id: seconds}``."""
    reader = csv.DictReader(lines)
    if reader.fieldnames is None:
        raise InputError(["%s: file is empty (a header row is required)" % source])
    reader.fieldnames = [(n or "").strip() for n in reader.fieldnames]
    for col in ("clip_id", "duration_s"):
        if col not in reader.fieldnames:
            raise InputError(["%s line 1: header is missing column %s" % (source, col)])
    durations = {}  # type: Dict[str, float]
    errors = []  # type: List[str]
    try:
        for row in reader:
            line = reader.line_num
            if not any((v or "").strip() for v in row.values() if isinstance(v, str)):
                continue
            clip_id = (row.get("clip_id") or "").strip()
            if not clip_id:
                errors.append("%s line %d: clip_id is empty" % (source, line))
                continue
            try:
                dur = _parse_float(row.get("duration_s") or "")
            except ValueError:
                errors.append(
                    "%s line %d: duration_s %r is not a number" % (source, line, row.get("duration_s"))
                )
                continue
            if dur < 0:
                errors.append("%s line %d: duration_s is negative" % (source, line))
                continue
            if clip_id in durations:
                errors.append("%s line %d: duplicate clip_id %r" % (source, line, clip_id))
                continue
            durations[clip_id] = dur
    except csv.Error as exc:
        errors.append("%s line %d: CSV syntax error: %s" % (source, reader.line_num, exc))
    if errors:
        raise InputError(errors)
    return durations


def _read_text_lines(path: str) -> List[str]:
    try:
        with open(path, "r", encoding="utf-8-sig", newline="") as fh:
            return fh.read().splitlines(True)
    except OSError as exc:
        raise InputError(["cannot read %s: %s" % (path, exc.strerror or exc)])
    except UnicodeDecodeError:
        raise InputError(["cannot read %s: not valid UTF-8 text" % path])


def load_labels(path: str) -> List[LabeledEvent]:
    """Read and validate an events.csv file."""
    return parse_labels(_read_text_lines(path), source=path)


def load_predictions(path: str) -> List[PredictedEvent]:
    """Read and validate a predictions JSON file."""
    return parse_predictions("".join(_read_text_lines(path)), source=path)


def load_clips(path: str) -> Dict[str, float]:
    """Read and validate a clips CSV file."""
    return parse_clips(_read_text_lines(path), source=path)


# -------------------------------------------------------------------- evaluation


@dataclass(frozen=True)
class Evaluation:
    """Everything the report prints. Built by ``evaluate``."""

    n_clips: int
    clips_from_file: bool
    n_labeled: int
    n_predicted: int  # after the confidence filter
    n_dropped_by_confidence: int
    min_confidence: Optional[float]
    footage_seconds: float
    tolerance_s: float
    result: MatchResult
    scores: EventScores
    fa_per_hour: Optional[float]
    leads: List[float]
    median_lead: Optional[float]
    confusion: Dict[Tuple[str, str], int]


def evaluate(
    labeled: Sequence[LabeledEvent],
    predicted: Sequence[PredictedEvent],
    footage_seconds: float,
    tolerance_s: float = 1.0,
    min_confidence: Optional[float] = None,
    clip_ids: Optional[Iterable[str]] = None,
) -> Evaluation:
    """Run matching and all metrics. This is the one entry point the toy script also uses.

    ``clip_ids`` is the full clip list when known (from ``--clips``). Otherwise the clip
    count is the number of distinct clip_ids that appear in labels or predictions, which
    undercounts event-free clips.
    """
    kept = list(predicted)
    if min_confidence is not None:
        kept = [p for p in kept if p.confidence >= min_confidence]
    result = metrics.match_events(labeled, kept, tolerance_s)
    scores = metrics.event_scores(result)
    leads = metrics.lead_times(result.matches)
    if clip_ids is not None:
        n_clips = len(set(clip_ids))
        from_file = True
    else:
        n_clips = len({e.clip_id for e in labeled} | {p.clip_id for p in kept})
        from_file = False
    return Evaluation(
        n_clips=n_clips,
        clips_from_file=from_file,
        n_labeled=len(labeled),
        n_predicted=len(kept),
        n_dropped_by_confidence=len(predicted) - len(kept),
        min_confidence=min_confidence,
        footage_seconds=footage_seconds,
        tolerance_s=tolerance_s,
        result=result,
        scores=scores,
        fa_per_hour=metrics.false_alarms_per_hour(scores.false_positives, footage_seconds),
        leads=leads,
        median_lead=metrics.median_lead_time(leads),
        confusion=metrics.side_confusion(result.matches, labeled),
    )


# --------------------------------------------------------------------- rendering


def sample_warning(n_labeled: int) -> str:
    """Tier line from LABELING.md section 4, chosen by labeled-event count."""
    if n_labeled < TIER_NO_RATES_BELOW:
        return (
            "> **WARNING: only %d labeled events (fewer than %d). Results are anecdotal. "
            "No rates should be quoted; rates are withheld below.**"
            % (n_labeled, TIER_NO_RATES_BELOW)
        )
    if n_labeled < TIER_LIMITED_FROM:
        return (
            "> **NOTE: %d labeled events (%d to %d). Anecdotal. Quote counts and the sample, "
            "not a single percentage; the uncertainty around any rate is wide.**"
            % (n_labeled, TIER_NO_RATES_BELOW, TIER_LIMITED_FROM - 1)
        )
    return (
        "> **NOTE: %d labeled events. Still a small sample from one bike, one phone, and "
        "the roads and conditions in the manifest. Quote counts with the sample "
        "description.**" % n_labeled
    )


def _rate_cell(value: Optional[float], withheld: bool, fmt: str = "%.3f") -> str:
    if withheld:
        return "withheld (fewer than %d labeled events)" % TIER_NO_RATES_BELOW
    if value is None:
        return "undefined"
    return fmt % value


def _num(x: float) -> str:
    return "%+.2f" % x


def render_markdown(ev: Evaluation, show_rates_anyway: bool = False) -> str:
    """Render the report: sample size, metrics, lead time, side confusion."""
    withheld = ev.n_labeled < TIER_NO_RATES_BELOW and not show_rates_anyway
    s = ev.scores
    out = []  # type: List[str]
    out.append("# Whoosh vision evaluation (experimental)")
    out.append("")
    out.append("## Sample size")
    out.append("")
    out.append("| Item | Value |")
    out.append("| ---- | ----- |")
    clip_note = "" if ev.clips_from_file else " (clips with a label or prediction only)"
    out.append("| Clips | %d%s |" % (ev.n_clips, clip_note))
    out.append("| Labeled events | %d |" % ev.n_labeled)
    pred_note = ""
    if ev.min_confidence is not None:
        pred_note = " (confidence >= %g; %d dropped by the filter)" % (
            ev.min_confidence,
            ev.n_dropped_by_confidence,
        )
    out.append("| Predicted events | %d%s |" % (ev.n_predicted, pred_note))
    out.append(
        "| Footage | %.4f hours (%g s) |" % (ev.footage_seconds / 3600.0, ev.footage_seconds)
    )
    out.append("| Match tolerance | %g s |" % ev.tolerance_s)
    out.append("")
    out.append(sample_warning(ev.n_labeled))
    if show_rates_anyway and ev.n_labeled < TIER_NO_RATES_BELOW:
        out.append("")
        out.append("(Rates are shown only because --show-rates-anyway was given.)")
    out.append("")

    out.append("## Event metrics")
    out.append("")
    out.append("| Metric | Value | Counts |")
    out.append("| ------ | ----- | ------ |")
    out.append(
        "| Precision | %s | %d of %d predictions matched a labeled event |"
        % (_rate_cell(s.precision, withheld), s.true_positives, s.true_positives + s.false_positives)
    )
    out.append(
        "| Recall | %s | %d of %d labeled events matched |"
        % (_rate_cell(s.recall, withheld), s.true_positives, s.true_positives + s.false_negatives)
    )
    out.append(
        "| F1 | %s | TP=%d, FP=%d, FN=%d |"
        % (_rate_cell(s.f1, withheld), s.true_positives, s.false_positives, s.false_negatives)
    )
    out.append(
        "| False alarms per hour | %s | %d false positives in %.4f hours (%g s) of footage |"
        % (
            _rate_cell(ev.fa_per_hour, withheld, "%.2f"),
            s.false_positives,
            ev.footage_seconds / 3600.0,
            ev.footage_seconds,
        )
    )
    out.append("")
    out.append(
        "A prediction is a false positive if no free labeled event matched it, including a "
        "second prediction near an event that an earlier prediction already matched."
    )
    out.append("")

    out.append("## Lead time")
    out.append("")
    n = len(ev.leads)
    if n == 0:
        out.append("No matched events, so lead time is undefined.")
    else:
        early = sum(1 for x in ev.leads if x > 0)
        late = sum(1 for x in ev.leads if x < 0)
        at_start = n - early - late
        assert ev.median_lead is not None
        out.append("| Statistic | Value | Counts |")
        out.append("| --------- | ----- | ------ |")
        out.append("| Median lead (s) | %s | over %d matched events |" % (_num(ev.median_lead), n))
        out.append("| Minimum lead (s) | %s | over %d matched events |" % (_num(min(ev.leads)), n))
        out.append("| Maximum lead (s) | %s | over %d matched events |" % (_num(max(ev.leads)), n))
        out.append("| Before labeled start | | %d of %d matched events |" % (early, n))
        out.append("| At labeled start | | %d of %d matched events |" % (at_start, n))
        out.append("| After labeled start (late) | | %d of %d matched events |" % (late, n))
    out.append("")
    out.append(
        "Lead = labeled t_start_s minus prediction t_s. Positive: before the labeled start. "
        "Negative: late. Matched leads cannot exceed the %g s tolerance, because earlier "
        "predictions count as false positives." % ev.tolerance_s
    )
    out.append("")

    out.append("## Side confusion")
    out.append("")
    out.append(
        "Rows: labeled side. Columns: predicted position_hint. Both are in the rider's frame "
        "(LABELING.md section 3.2). Nothing is flipped here. \"none\" is a match with a null "
        "hint; \"missed\" is a labeled event with no match."
    )
    out.append("")
    cols = list(metrics.HINT_COLUMNS)
    rows = list(metrics.SIDE_VALUES)
    for (side, col) in sorted(ev.confusion):
        if side not in rows:
            rows.append(side)
        if col not in cols:
            cols.insert(len(cols) - 2, col)
    out.append("| Labeled side \\ hint | " + " | ".join(cols) + " | total |")
    out.append("| --- |" + " --- |" * (len(cols) + 1))
    for side in rows:
        cells = [ev.confusion.get((side, c), 0) for c in cols]
        out.append("| %s | %s | %d |" % (side, " | ".join(str(c) for c in cells), sum(cells)))
    out.append("")
    agree, comparable = metrics.side_agreement(ev.confusion)
    out.append(
        "Side agreement: %d of %d matched events with a known labeled side and a hint."
        % (agree, comparable)
    )
    out.append("")
    return "\n".join(out)


# --------------------------------------------------------------------------- CLI


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Print a Markdown evaluation report from labels and predictions.",
        epilog="Formats are documented in the docstring of report.py and in README.md.",
    )
    p.add_argument("--labels", required=True, help="events.csv (LABELING.md section 3.1)")
    p.add_argument("--predictions", required=True, help="predictions JSON list")
    p.add_argument("--footage-seconds", type=float, help="total seconds of footage evaluated")
    p.add_argument("--clips", help="CSV with columns clip_id,duration_s (alternative to --footage-seconds)")
    p.add_argument("--tolerance-s", type=float, default=1.0, help="match tolerance in seconds (default 1.0)")
    p.add_argument("--min-confidence", type=float, help="drop predictions below this confidence")
    p.add_argument(
        "--show-rates-anyway",
        action="store_true",
        help="print rates even with fewer than %d labeled events (warning stays)" % TIER_NO_RATES_BELOW,
    )
    return p


def _run(args: argparse.Namespace) -> str:
    errors = []  # type: List[str]
    if args.footage_seconds is None and not args.clips:
        errors.append("give --footage-seconds N or --clips CLIPS.csv (footage is needed for false alarms per hour)")
    if args.footage_seconds is not None and args.clips:
        errors.append("give either --footage-seconds or --clips, not both")
    if args.footage_seconds is not None and (not math.isfinite(args.footage_seconds) or args.footage_seconds < 0):
        errors.append("--footage-seconds must be a finite number >= 0")
    if not math.isfinite(args.tolerance_s) or args.tolerance_s < 0:
        errors.append("--tolerance-s must be a finite number >= 0")
    if args.min_confidence is not None and not (0.0 <= args.min_confidence <= 1.0):
        errors.append("--min-confidence must be between 0 and 1")
    if errors:
        raise InputError(errors)

    labeled = load_labels(args.labels)
    predicted = load_predictions(args.predictions)

    clip_ids = None  # type: Optional[List[str]]
    footage = args.footage_seconds
    if args.clips:
        durations = load_clips(args.clips)
        unknown = sorted(
            ({e.clip_id for e in labeled} | {p.clip_id for p in predicted}) - set(durations)
        )
        if unknown:
            raise InputError(["clip_id(s) not listed in %s: %s" % (args.clips, ", ".join(unknown))])
        footage = sum(durations.values())
        clip_ids = list(durations)

    ev = evaluate(labeled, predicted, footage, args.tolerance_s, args.min_confidence, clip_ids)
    return render_markdown(ev, args.show_rates_anyway)


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI entry point. Returns the process exit status."""
    args = _build_parser().parse_args(argv)
    try:
        text = _run(args)
    except InputError as exc:
        shown = exc.messages[:MAX_ERRORS_SHOWN]
        for msg in shown:
            print("error: " + msg, file=sys.stderr)
        if len(exc.messages) > len(shown):
            print("error: ... and %d more" % (len(exc.messages) - len(shown)), file=sys.stderr)
        return 2
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
