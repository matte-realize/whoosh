"""Approach detection: turns per-frame vehicle boxes into near-miss events.

Each dangerous vehicle produces a "potential_hit" event (alert the rider now), later resolved to
"hit" if a crash is reported (report_crash, e.g. from the phone's accelerometer) or "near_miss"
once the vehicle leaves or outcome_window_s passes.

Pure Python with no ML imports, so it's easy to unit test and to port line-by-line to
Dart/Swift. All boxes are normalized to 0..1 (x right, y down) and all times are seconds.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, fields
from pathlib import Path


@dataclass(frozen=True)
class ApproachConfig:
    vehicle_classes: dict[int, str]
    min_confidence: float  # drop detections below this
    iou_match: float  # min IoU to continue a track
    track_max_age_s: float  # drop a track not seen for this long
    ema_alpha: float  # weight of the newest box height in the smoothed height
    min_height_frac: float  # smoothed height / frame height needed for a growth alert
    growth_window_s: float  # growth is measured over this span, not frame-to-frame (noise at high FPS)
    growth_threshold_per_s: float  # relative growth per second (~ 1 / time-to-contact)
    consecutive_frames: int  # frames in a row above the growth threshold
    edge_margin: float  # a box within this distance of a frame edge "touches" it
    edge_height_frac: float  # a box touching an edge and taller than this is "close" (clipped, too near to grow)
    close_dwell_s: float  # "close" this long without a break -> potential hit (a clean overtake clears sooner)
    outcome_window_s: float  # a potential hit with no crash by then (or once the vehicle leaves) is a near miss
    cooldown_s: float  # per-track quiet time after an outcome before the next potential hit

    @classmethod
    def load(cls, path: str | Path = Path(__file__).with_name("approach_config.json")) -> ApproachConfig:
        raw = json.loads(Path(path).read_text())
        raw["vehicle_classes"] = {int(k): v for k, v in raw["vehicle_classes"].items()}
        return cls(**raw)

    def with_overrides(self, overrides: dict[str, str]) -> ApproachConfig:
        """Return a copy with string overrides applied, e.g. {"cooldown_s": "3"}."""
        types = {f.name: f.type for f in fields(self)}
        values = {}
        for key, value in overrides.items():
            if key not in types or key == "vehicle_classes":
                raise KeyError(f"unknown or non-overridable config key: {key}")
            values[key] = int(value) if types[key] == "int" else float(value)
        return ApproachConfig(**{**self.__dict__, **values})


@dataclass(frozen=True)
class Box:
    class_id: int
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float

    @property
    def height(self) -> float:
        return self.y2 - self.y1


@dataclass(frozen=True)
class ApproachAlert:
    kind: str  # "potential_hit" (alert now), then "near_miss" or "hit" for the same track
    track_id: int
    vehicle_class: str
    confidence: float
    timestamp: float
    growth_rate: float  # smoothed relative growth per second
    reason: str  # what triggered the potential hit: "growth" (approaching fast) or "close" (stayed too close)


@dataclass
class Track:
    id: int
    box: Box
    smoothed_height: float
    last_seen: float
    growth_rate: float = 0.0
    streak: int = 0  # consecutive frames with growth above threshold
    last_alert: float | None = None  # time of the last outcome (cooldown starts there)
    close_since: float | None = None  # start of the current unbroken "close" stretch
    class_scores: dict[int, float] = field(default_factory=dict)  # summed confidence per class
    history: list[tuple[float, float]] = field(default_factory=list)  # (t, smoothed_height) within the window

    @property
    def class_id(self) -> int:
        # Car/truck labels flicker frame to frame; report the best-supported class.
        return max(self.class_scores, key=self.class_scores.__getitem__)


def iou(a: Box, b: Box) -> float:
    ix = max(0.0, min(a.x2, b.x2) - max(a.x1, b.x1))
    iy = max(0.0, min(a.y2, b.y2) - max(a.y1, b.y1))
    inter = ix * iy
    union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter
    return inter / union if union > 0 else 0.0


class ApproachDetector:
    def __init__(self, config: ApproachConfig):
        self.config = config
        self.tracks: dict[int, Track] = {}
        self.pending: dict[int, ApproachAlert] = {}  # potential hits awaiting an outcome, by track id
        self._crash_times: list[float] = []
        self._next_id = 1

    def report_crash(self, t: float) -> None:
        """Tell the detector a crash happened at time t; pending potential hits resolve to "hit"."""
        self._crash_times.append(t)

    def update(self, boxes: list[Box], t: float) -> list[ApproachAlert]:
        """Feed one frame's detections at time t (seconds); returns events produced this frame."""
        cfg = self.config
        boxes = [b for b in boxes if b.class_id in cfg.vehicle_classes and b.confidence >= cfg.min_confidence]

        # Greedy IoU matching, best pairs first. Class is ignored on purpose (label flicker).
        pairs = sorted(
            ((iou(tr.box, b), tid, bi) for tid, tr in self.tracks.items() for bi, b in enumerate(boxes)),
            reverse=True,
        )
        matched_tracks: set[int] = set()
        matched_boxes: set[int] = set()
        for score, tid, bi in pairs:
            if score < cfg.iou_match:
                break
            if tid in matched_tracks or bi in matched_boxes:
                continue
            matched_tracks.add(tid)
            matched_boxes.add(bi)
            self._continue_track(self.tracks[tid], boxes[bi], t)

        for bi, b in enumerate(boxes):
            if bi not in matched_boxes:
                track = Track(id=self._next_id, box=b, smoothed_height=b.height, last_seen=t,
                              class_scores={b.class_id: b.confidence}, history=[(t, b.height)])
                self.tracks[track.id] = track
                matched_tracks.add(track.id)
                self._next_id += 1

        for tid in matched_tracks:
            self._update_close(self.tracks[tid], t)
        self.tracks = {tid: tr for tid, tr in self.tracks.items() if t - tr.last_seen <= cfg.track_max_age_s}

        events = self._resolve_outcomes(t)
        for tid in sorted(matched_tracks):
            alert = self._check_alert(self.tracks[tid], t)
            if alert:
                self.pending[tid] = alert
                events.append(alert)
        return events

    def _touches_edge(self, b: Box) -> bool:
        m = self.config.edge_margin
        return b.x1 <= m or b.y1 <= m or b.x2 >= 1 - m or b.y2 >= 1 - m

    def _update_close(self, track: Track, t: float) -> None:
        if self._touches_edge(track.box) and track.box.height > self.config.edge_height_frac:
            if track.close_since is None:
                track.close_since = t
        else:
            track.close_since = None

    def _resolve_outcomes(self, t: float) -> list[ApproachAlert]:
        events = []
        for tid, alert in list(self.pending.items()):
            if any(alert.timestamp <= c <= t for c in self._crash_times):
                kind = "hit"
            elif tid not in self.tracks or t - alert.timestamp >= self.config.outcome_window_s:
                kind = "near_miss"
            else:
                continue
            del self.pending[tid]
            if tid in self.tracks:
                self.tracks[tid].last_alert = t
            events.append(ApproachAlert(kind, alert.track_id, alert.vehicle_class, alert.confidence, t,
                                        alert.growth_rate, alert.reason))
        return events

    def _continue_track(self, track: Track, box: Box, t: float) -> None:
        cfg = self.config
        track.smoothed_height = cfg.ema_alpha * box.height + (1 - cfg.ema_alpha) * track.smoothed_height
        # Keep only the newest sample at or beyond the window edge, so the oldest entry is ~window ago.
        track.history.append((t, track.smoothed_height))
        while len(track.history) > 2 and t - track.history[1][0] >= cfg.growth_window_s:
            track.history.pop(0)
        t0, h0 = track.history[0]
        if t > t0 and h0 > 0:
            track.growth_rate = (track.smoothed_height - h0) / h0 / (t - t0)
        track.streak = track.streak + 1 if track.growth_rate > cfg.growth_threshold_per_s else 0
        track.box = box
        track.last_seen = t
        track.class_scores[box.class_id] = track.class_scores.get(box.class_id, 0.0) + box.confidence

    def _check_alert(self, track: Track, t: float) -> ApproachAlert | None:
        cfg = self.config
        if track.id in self.pending or (track.last_alert is not None and t - track.last_alert < cfg.cooldown_s):
            return None
        if track.close_since is not None and t - track.close_since >= cfg.close_dwell_s:
            reason = "close"
        elif (track.streak >= cfg.consecutive_frames and track.smoothed_height >= cfg.min_height_frac
              and not self._touches_edge(track.box)):
            # A clipped box "grows" just by sliding into view (overtaking, entering from the side).
            reason = "growth"
        else:
            return None
        return ApproachAlert(
            kind="potential_hit",
            track_id=track.id,
            vehicle_class=cfg.vehicle_classes[track.class_id],
            confidence=track.box.confidence,
            timestamp=t,
            growth_rate=track.growth_rate,
            reason=reason,
        )
