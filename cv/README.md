# Whoosh CV: vehicle approach detection

Pretrained YOLO26n (COCO) finds cars, motorcycles, buses, trucks and bicycles (our stand-in for e-scooters) in the rear camera. A small
tracker then decides when one is approaching. This folder holds the parts that are the same on
Android and iOS: the model export, the approach logic, its config, and an offline tuning tool.

| File | What it is |
|---|---|
| `approach_config.json` | **Every threshold, in one place.** The app should load this same file. |
| `approach.py` | Tracker + approach logic. Pure Python and no ML imports, so port it line by line to Dart or Swift. |
| `test_approach.py` | Tests on synthetic box sequences (approach, jitter, edge, cooldown, class flicker). |
| `tune_approach.py` | Runs YOLO + the logic on recorded video and prints when the app would alert. |
| `export_model.py` | Exports the phone model to `models/`. |
| `models/yolo26n_w8a32.tflite` | Android model: LiteRT, 320 px, INT8 weights, NMS done by the plugin. |
| `ios/WhooshVision/` | iOS Swift package: camera frames in → Core ML → vehicle boxes out (no camera code). See [ios/README.md](ios/README.md). |

## Setup (WSL/Linux)

```bash
cd cv
python3 -m venv .venv
.venv/bin/pip install torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cpu
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m unittest -v test_approach
```

## Tuning on footage

```bash
.venv/bin/python tune_approach.py clips/*.mp4 --fps 12                 # print alerts
.venv/bin/python tune_approach.py clip.mp4 --fps 12 --save out/        # + annotated video
.venv/bin/python tune_approach.py clip.mp4 --fps 12 --trace            # + every track, every frame
.venv/bin/python tune_approach.py clip.mp4 --set growth_threshold_per_s=0.4 --set consecutive_frames=4
```

- **Always pass `--fps` with the FPS measured on the phone.** Smoothing and "N consecutive frames"
  depend on frame rate, so tuning at the video's 30 fps gives constants that won't carry over.
- Each alert line shows `reason` (`growth` or `edge`), the growth rate `g`, and the smoothed height `h`.
  In `--save` videos, green boxes are tracks and red boxes are currently growing.
- `--model models/yolo26n_w8a32.tflite` runs the exact phone model (a bit slower on a laptop).
- Use footage shot with the **same lens and mount** as the demo phone. A wider lens makes vehicles
  look smaller, which shifts `min_height_frac` and `edge_height_frac`.

## How the logic works

Each frame: keep vehicle classes with `conf >= min_confidence`. Match boxes to tracks by IoU, best
pairs first. Matching ignores the class, because car and truck labels flicker. Then for each track:

1. `h` = box height / frame height, smoothed with an EMA (`ema_alpha`).
2. Growth `g` = relative change of the smoothed `h` per second, measured over `growth_window_s`.
   `1/g` is roughly time-to-contact, so `g = 0.3` means about 3 s away.
3. **Potential hit, growth:** `g > growth_threshold_per_s` for `consecutive_frames` frames in a row,
   with `h >= min_height_frac`, and the box fully inside the frame. A box clipped by the edge "grows"
   just by sliding into view, for example during an overtake or when a car enters from the side.
4. **Potential hit, close:** the box touches a frame edge (`edge_margin`) with `h > edge_height_frac`,
   without a break, for `close_dwell_s`. Being clipped alone isn't dangerous, because a clean overtake
   clears in about a second. A vehicle that *stays* that close is.
5. **Outcome:** each potential hit resolves once. It becomes `hit` if `report_crash(t)` is called after
   it (the app will get this from the phone's accelerometer). Otherwise it becomes `near_miss` when the
   vehicle leaves or `outcome_window_s` passes.
6. After the outcome, that track stays quiet for `cooldown_s`. Tracks unseen for `track_max_age_s` are dropped.

Test the hit path offline with `--crash-at SECONDS`.

Reference clip `../Near_Miss.mp4` (`--fps 12`): a bus stays alongside the rider and then drops back.
Later it overtakes close. Both count as potential hits, and nothing else should fire:

| Potential hit | Outcome | What happens |
|---|---|---|
| ~23.0 s | near miss ~26.9 s | Bus alongside for ~4.6 s, then drops back |
| ~41.4 s | near miss ~42.7 s | Bus overtakes, staying close for ~1.9 s |

If you raise `close_dwell_s` above ~1.9 s, the second one stops firing.

## Exporting

```bash
.venv/bin/python export_model.py                 # Android .tflite
.venv-coreml/bin/python export_model.py --ios    # iOS .mlpackage, copied into the Swift package
```

Core ML export needs `numpy<=2.3.5`, because numpy 2.4+ breaks coremltools. The LiteRT tools pull in
a newer numpy, so Core ML gets its own venv:

```bash
python3 -m venv .venv-coreml
.venv-coreml/bin/pip install torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cpu
.venv-coreml/bin/pip install "ultralytics[export-coreml]==8.4.187" "numpy<=2.3.5"
```

The settings match the `ultralytics_yolo` Flutter plugin's official Android assets. The `tflite`
format name is deprecated in ultralytics >= 8.4.83; it's `litert` now.
