# WhooshVision (iOS)

The CV part of Whoosh as a Swift package: **frames in, vehicle boxes out.** It runs YOLO26n
on-device with Core ML and Vision, and needs no network. Camera capture, live preview and the app UI
belong to the app (your teammates), not to this package.

**Status:** detection only. The near-miss logic (potential hit → near miss / hit) is still in
Python (`../approach.py`); porting it to Swift is next. **None of this Swift code has been compiled
yet**, because it was written without Xcode. Expect small fixes on the first build.

| File | What it is |
|---|---|
| `Sources/WhooshVision/VehicleDetector.swift` | Loads the model and runs it on a `CVPixelBuffer` (camera frame) or `CGImage`. Returns a `DetectionFrame`. |
| `Sources/WhooshVision/VehicleBox.swift` | `VehicleBox` and `DetectionFrame` types, plus coordinate and orientation helpers |
| `Sources/WhooshVision/Resources/yolo26n.mlpackage` | YOLO26n, COCO, 320 px, FP16, NMS built in. Re-create it with `../export_model.py --ios`. |
| `Tests/WhooshVisionTests/` | Geometry tests, plus a real-model test on a sample bus photo |

## Using it from the camera code

```swift
import WhooshVision

let detector = try await VehicleDetector.load()       // once, about 1 s

// In AVCaptureVideoDataOutputSampleBufferDelegate, on the camera's serial background queue:
let orientation = FrameGeometry.imageOrientation(forRotationAngle: rotationCoordinator.videoRotationAngleForHorizonLevelCapture)
let frame = try detector.detect(in: CMSampleBufferGetImageBuffer(sampleBuffer)!,
                                orientation: orientation,
                                timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
// frame.boxes: [VehicleBox(label: "bus", confidence: 0.82, rect: normalized, origin top-left)]
// frame.fps, frame.inferenceMs: show these while testing
```

- **Threading:** `detect` is synchronous and takes about 10–40 ms. Call it from one background serial
  queue, never the main thread. Set `alwaysDiscardsLateVideoFrames = true` so frames don't queue up.
- **Orientation:** pass the camera's rotation, or boxes come out rotated. `rect` is relative to the
  upright frame (`frame.imageSize`).
- **Classes:** only `bicycle`, `car`, `motorcycle`, `bus` and `truck` are returned. Bicycle is the stand-in for e-scooters.
- **Frame size:** 720p is plenty, because the model sees 320 px anyway.

## How to test (Mac, no phone needed)

1. **Model sanity (2 min):** double-click `Sources/WhooshVision/Resources/yolo26n.mlpackage`. In
   Xcode, open the **Preview** tab and drag in a street photo. Boxes should appear on the vehicles.
   The model was exported on Linux with a torch version coremltools hasn't tested, so check this first.
2. **Tests:** `cd cv/ios/WhooshVision && swift test`. This runs the real model on the sample bus photo
   and checks the bus is found at the same place Python finds it (x 0.03–0.99, y 0.21–0.70).

If step 1 fails, re-export on the Mac: `pip install "ultralytics[export-coreml]" "numpy<=2.3.5"`,
then run `python export_model.py --ios` from `cv/`.
