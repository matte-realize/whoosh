"""Export the pretrained YOLO26n detector for the phone app.

  .venv/bin/python export_model.py                  # Android: models/yolo26n_w8a32.tflite
  .venv-coreml/bin/python export_model.py --ios     # iOS: models/yolo26n.mlpackage, copied into the Swift package

Android settings match the ultralytics_yolo plugin's official assets: LiteRT, INT8 weights with
FP32 activations (w8a32, no calibration data), NMS done by the plugin (nms left at its default).
Avoid full INT8 activations: the plugin's performance doc reports naive A8W8 gave zero detections.

iOS embeds NMS (nms=True) so Vision returns labeled VNRecognizedObjectObservations directly.
Core ML export needs numpy<=2.3.5 (numpy 2.4+ breaks coremltools), which conflicts with the
LiteRT tooling, hence the separate .venv-coreml (see README).
"""

import argparse
import shutil
from pathlib import Path

from ultralytics import YOLO

MODELS = Path(__file__).parent / "models"
SWIFT_RESOURCES = Path(__file__).parent / "ios" / "WhooshVision" / "Sources" / "WhooshVision" / "Resources"


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--imgsz", type=int, default=320)
    p.add_argument("--ios", action="store_true", help="export Core ML for iOS instead of LiteRT")
    args = p.parse_args()

    MODELS.mkdir(exist_ok=True)
    model = YOLO(MODELS / "yolo26n.pt")  # downloaded on first use
    if not args.ios:
        print(model.export(format="litert", imgsz=args.imgsz, quantize="w8a32"))
        return
    exported = Path(model.export(format="coreml", imgsz=args.imgsz, nms=True))
    target = SWIFT_RESOURCES / exported.name
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(exported, target)
    print(f"copied to {target}")


if __name__ == "__main__":
    main()
