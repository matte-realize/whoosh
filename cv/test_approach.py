"""Synthetic-sequence tests for approach.py. Run: .venv/bin/python -m unittest -v test_approach"""

import random
import unittest

from approach import ApproachConfig, ApproachDetector, Box

FPS = 15
PERSON, BICYCLE, CAR, BUS, TRUCK = 0, 1, 2, 5, 7


def centered(height: float, class_id: int = CAR, conf: float = 0.8, cx: float = 0.5, aspect: float = 1.2) -> Box:
    """A box of the given normalized height, centered on (cx, 0.55)."""
    w = min(height * aspect, 0.9)
    return Box(class_id, conf, cx - w / 2, 0.55 - height / 2, cx + w / 2, 0.55 + height / 2)


def run(detector: ApproachDetector, frames: list[list[Box]], fps: float = FPS):
    alerts = []
    for i, boxes in enumerate(frames):
        alerts += detector.update(boxes, i / fps)
    return alerts


class ApproachTests(unittest.TestCase):
    def setUp(self):
        self.cfg = ApproachConfig.load()
        self.det = ApproachDetector(self.cfg)

    def test_approaching_car_alerts_once(self):
        # Height doubles every second (~1.4 s time-to-contact): 0.10 -> 0.40 over 2 s.
        frames = [[centered(0.10 * 2 ** (i / FPS))] for i in range(2 * FPS)]
        alerts = run(self.det, frames)
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0].reason, "growth")
        self.assertEqual(alerts[0].vehicle_class, "car")
        self.assertLess(alerts[0].timestamp, 0.5)

    def test_static_car_with_vibration_jitter_never_alerts(self):
        rng = random.Random(0)
        frames = []
        for _ in range(30 * FPS):
            h = 0.25 * (1 + rng.uniform(-0.05, 0.05))  # +-5% height noise
            frames.append([centered(h, cx=0.5 + rng.uniform(-0.02, 0.02))])
        self.assertEqual(run(self.det, frames), [])

    def test_distant_growing_car_below_min_size_ignored(self):
        frames = [[centered(0.02 * 2 ** (i / FPS))] for i in range(int(1.5 * FPS))]  # ends ~0.057
        self.assertEqual(run(self.det, frames), [])

    def test_receding_car_never_alerts(self):
        frames = [[centered(0.4 * 0.5 ** (i / FPS))] for i in range(2 * FPS)]
        self.assertEqual(run(self.det, frames), [])

    def test_bus_staying_alongside_is_a_potential_hit_after_dwell(self):
        clipped = Box(BUS, 0.7, 0.0, 0.0, 0.5, 0.97)  # bus alongside: clipped left/top, 97% tall
        frames = [[clipped] for _ in range(3 * FPS)]
        alerts = run(self.det, frames)
        self.assertEqual([(a.kind, a.reason, a.vehicle_class) for a in alerts], [("potential_hit", "close", "bus")])
        self.assertAlmostEqual(alerts[0].timestamp, self.cfg.close_dwell_s, delta=1.5 / FPS)

    def test_quick_overtake_is_not_an_alert(self):
        # Clipped and huge, but gone before close_dwell_s: a clean pass.
        clipped = Box(BUS, 0.7, 0.0, 0.0, 0.5, 0.97)
        frames = [[clipped] for _ in range(int(0.8 * self.cfg.close_dwell_s * FPS))] + [[] for _ in range(FPS)]
        self.assertEqual(run(self.det, frames), [])

    def test_box_growing_while_sliding_in_from_edge_is_not_growth(self):
        # Car entering from the left: box widens and grows only because more of it becomes visible.
        frames = [[Box(CAR, 0.8, 0.0, 0.4, 0.1 + 0.02 * i, 0.5 + 0.01 * i)] for i in range(FPS)]
        self.assertEqual(run(self.det, frames), [])

    def test_tall_box_not_touching_edge_is_not_close(self):
        frames = [[Box(BUS, 0.7, 0.2, 0.1, 0.8, 0.9)] for _ in range(3 * FPS)]
        self.assertEqual(run(self.det, frames), [])

    def test_near_miss_when_vehicle_leaves_without_crash(self):
        clipped = Box(BUS, 0.7, 0.0, 0.0, 0.5, 0.97)
        frames = [[clipped] for _ in range(2 * FPS)] + [[] for _ in range(FPS)]
        alerts = run(self.det, frames)
        self.assertEqual([a.kind for a in alerts], ["potential_hit", "near_miss"])
        self.assertEqual(alerts[0].track_id, alerts[1].track_id)
        self.assertLess(alerts[1].timestamp, 2 + self.cfg.track_max_age_s + 0.2)

    def test_hit_when_crash_reported(self):
        clipped = Box(BUS, 0.7, 0.0, 0.0, 0.5, 0.97)
        events = []
        for i in range(3 * FPS):
            t = i / FPS
            if i == int(1.8 * FPS):
                self.det.report_crash(t)
            events += self.det.update([clipped], t)
        self.assertEqual([a.kind for a in events], ["potential_hit", "hit"])

    def test_crash_before_potential_hit_does_not_count(self):
        self.det.report_crash(0.0)
        clipped = Box(BUS, 0.7, 0.0, 0.0, 0.5, 0.97)
        frames = [[clipped] for _ in range(2 * FPS)] + [[] for _ in range(FPS)]
        self.assertEqual([a.kind for a in run(self.det, frames)], ["potential_hit", "near_miss"])

    def test_vehicle_alongside_for_long_rearms_only_after_outcome_and_cooldown(self):
        clipped = Box(BUS, 0.7, 0.0, 0.0, 0.5, 0.97)
        frames = [[clipped] for _ in range(16 * FPS)]
        alerts = run(self.det, frames)
        self.assertEqual([a.kind for a in alerts], ["potential_hit", "near_miss", "potential_hit"])
        self.assertAlmostEqual(alerts[1].timestamp - alerts[0].timestamp, self.cfg.outcome_window_s, delta=1.5 / FPS)
        self.assertGreaterEqual(alerts[2].timestamp - alerts[1].timestamp, self.cfg.cooldown_s)

    def test_non_vehicles_and_low_confidence_ignored(self):
        frames = [[centered(0.10 * 2 ** (i / FPS), class_id=PERSON),
                   centered(0.10 * 2 ** (i / FPS), conf=0.2, cx=0.2)] for i in range(2 * FPS)]
        self.assertEqual(run(self.det, frames), [])
        self.assertEqual(self.det.tracks, {})

    def test_approaching_bicycle_alerts(self):
        # Stand-in for e-scooters/e-bikes gaining on the rider.
        frames = [[centered(0.10 * 2 ** (i / FPS), class_id=BICYCLE, aspect=0.6)] for i in range(2 * FPS)]
        alerts = run(self.det, frames)
        self.assertEqual([a.vehicle_class for a in alerts], ["bicycle"])

    def test_class_flicker_keeps_one_track(self):
        frames = [[centered(0.10 * 2 ** (i / FPS), class_id=CAR if i % 3 else TRUCK)] for i in range(2 * FPS)]
        alerts = run(self.det, frames)
        self.assertEqual(len(alerts), 1)
        self.assertEqual(len({a.track_id for a in alerts}), 1)
        self.assertEqual(alerts[0].vehicle_class, "car")

    def test_two_vehicles_tracked_separately(self):
        frames = [[centered(0.10 * 2 ** (i / FPS), cx=0.25, aspect=0.8),
                   centered(0.10 * 2 ** (i / FPS), cx=0.75, aspect=0.8)] for i in range(2 * FPS)]
        alerts = run(self.det, frames)
        self.assertEqual(len({a.track_id for a in alerts}), 2)

    def test_track_dropped_after_max_age(self):
        self.det.update([centered(0.2)], 0.0)
        self.det.update([], self.cfg.track_max_age_s + 0.1)
        self.assertEqual(self.det.tracks, {})

    def test_growth_rate_is_frame_rate_independent(self):
        # Same physical approach at 8 and 30 FPS should both alert.
        for fps in (8, 30):
            det = ApproachDetector(self.cfg)
            frames = [[centered(0.10 * 2 ** (i / fps))] for i in range(2 * fps)]
            self.assertEqual(len(run(det, frames, fps)), 1, f"fps={fps}")

    def test_overrides(self):
        cfg = self.cfg.with_overrides({"consecutive_frames": "5", "cooldown_s": "2.5"})
        self.assertEqual((cfg.consecutive_frames, cfg.cooldown_s), (5, 2.5))
        with self.assertRaises(KeyError):
            self.cfg.with_overrides({"nope": "1"})


if __name__ == "__main__":
    unittest.main()
