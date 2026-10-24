"""Run YOLO + approach logic on recorded footage and print when the app would alert.

Examples:
  .venv/bin/python tune_approach.py clips/*.mp4 --fps 12
  .venv/bin/python tune_approach.py clip.mp4 --fps 12 --set growth_threshold_per_s=0.4 --save out/
  .venv/bin/python tune_approach.py clip.mp4 --model models/yolo26n_w8a32.tflite --trace

Use --fps with the FPS measured on the phone: smoothing and "N consecutive frames" depend on it.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import cv2
from ultralytics import YOLO

from approach import ApproachConfig, ApproachDetector, Box

HERE = Path(__file__).parent


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("videos", nargs="+", type=Path)
    p.add_argument("--model", default=str(HERE / "models" / "yolo26n.pt"), help=".pt (fast) or the exported .tflite")
    p.add_argument("--imgsz", type=int, default=320)
    p.add_argument("--fps", type=float, help="process at this rate (phone FPS); default: every frame")
    p.add_argument("--config", type=Path, default=HERE / "approach_config.json")
    p.add_argument("--set", action="append", default=[], metavar="KEY=VALUE", help="override a config value")
    p.add_argument("--save", type=Path, metavar="DIR", help="write annotated videos here")
    p.add_argument("--trace", action="store_true", help="print every track on every processed frame")
    p.add_argument("--crash-at", type=float, action="append", default=[], metavar="SECONDS",
                   help="simulate a crash report at this video time (tests the 'hit' outcome)")
    return p.parse_args()


def detect(model: YOLO, frame, cfg: ApproachConfig, imgsz: int) -> list[Box]:
    r = model.predict(frame, imgsz=imgsz, conf=min(0.25, cfg.min_confidence), classes=list(cfg.vehicle_classes),
                      verbose=False)[0]
    return [Box(int(c), float(s), *map(float, xyxy))
            for xyxy, c, s in zip(r.boxes.xyxyn.tolist(), r.boxes.cls.tolist(), r.boxes.conf.tolist())]


def draw(frame, detector: ApproachDetector, alert_until: float, t: float):
    h, w = frame.shape[:2]
    for tr in detector.tracks.values():
        if tr.last_seen != t:
            continue
        b = tr.box
        p1, p2 = (int(b.x1 * w), int(b.y1 * h)), (int(b.x2 * w), int(b.y2 * h))
        color = (0, 0, 255) if tr.streak else (0, 255, 0)
        cv2.rectangle(frame, p1, p2, color, 2)
        label = f"#{tr.id} {detector.config.vehicle_classes[tr.class_id]} h={tr.smoothed_height:.2f} g={tr.growth_rate:+.2f}"
        cv2.putText(frame, label, (p1[0], max(p1[1] - 6, 14)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
    if t < alert_until:
        cv2.rectangle(frame, (0, 0), (w - 1, h - 1), (0, 0, 255), 12)
        cv2.putText(frame, "POTENTIAL HIT", (20, 60), cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 0, 255), 4)
    cv2.putText(frame, f"t={t:.2f}s", (w - 140, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)


def run_video(path: Path, model: YOLO, cfg: ApproachConfig, args: argparse.Namespace) -> int:
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        print(f"{path}: cannot open")
        return 0
    video_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    out_fps = args.fps or video_fps
    detector = ApproachDetector(cfg)
    writer = None
    next_t, frame_idx, processed, infer_s, n_alerts, alert_until = 0.0, -1, 0, 0.0, 0, -1.0

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_idx += 1
        t = frame_idx / video_fps
        if args.fps:
            # Same tolerance in both checks, or a frame a hair before next_t is processed without advancing it.
            if t + 1e-9 < next_t:
                continue
            while next_t <= t + 1e-9:
                next_t += 1 / args.fps

        start = time.perf_counter()
        boxes = detect(model, frame, cfg, args.imgsz)
        infer_s += time.perf_counter() - start
        processed += 1

        for crash_t in args.crash_at:
            if t - 1 / out_fps < crash_t <= t:
                detector.report_crash(crash_t)
                print(f"{path.name} t={t:7.2f}s (simulated crash reported)")
        for a in detector.update(boxes, t):
            if a.kind == "potential_hit":
                n_alerts += 1
                alert_until = t + 0.5
            tr = detector.tracks.get(a.track_id)
            h = f"h={tr.smoothed_height:.2f}" if tr else "(vehicle gone)"
            print(f"{path.name} t={t:7.2f}s {a.kind.upper():13s} {a.reason:6s} {a.vehicle_class:10s} "
                  f"track={a.track_id:<3d} conf={a.confidence:.2f} growth={a.growth_rate:+.2f}/s {h}")
        if args.trace:
            for tr in detector.tracks.values():
                if tr.last_seen == t:
                    print(f"  t={t:7.2f}s #{tr.id:<3d} {cfg.vehicle_classes[tr.class_id]:10s} "
                          f"h={tr.smoothed_height:.3f} g={tr.growth_rate:+.2f}/s streak={tr.streak}")

        if args.save:
            if writer is None:
                args.save.mkdir(parents=True, exist_ok=True)
                fh, fw = frame.shape[:2]
                writer = cv2.VideoWriter(str(args.save / f"{path.stem}_annotated.mp4"),
                                         cv2.VideoWriter_fourcc(*"mp4v"), out_fps, (fw, fh))
            draw(frame, detector, alert_until, t)
            writer.write(frame)

    cap.release()
    if writer:
        writer.release()
    ms = 1000 * infer_s / max(processed, 1)
    print(f"{path.name}: {processed} frames processed ({frame_idx + 1} in video @ {video_fps:.1f} fps), "
          f"{n_alerts} potential hits, {ms:.1f} ms/frame inference on this machine")
    return n_alerts


def main() -> None:
    args = parse_args()
    cfg = ApproachConfig.load(args.config).with_overrides(dict(kv.split("=", 1) for kv in args.set))
    print(f"config: {cfg}")
    model = YOLO(args.model, task="detect")
    total = sum(run_video(v, model, cfg, args) for v in args.videos)
    print(f"total potential hits: {total}")


if __name__ == "__main__":
    main()
