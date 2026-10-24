import CoreGraphics
import Foundation
import ImageIO

public enum WhooshVisionModel {
    /// The bundled YOLO26n Core ML package (320 px, COCO, NMS embedded).
    /// SwiftPM copies the `.mlpackage` as is; an Xcode app build compiles it to `.mlmodelc`.
    public static var url: URL? {
        Bundle.module.url(forResource: "yolo26n", withExtension: "mlpackage")
            ?? Bundle.module.url(forResource: "yolo26n", withExtension: "mlmodelc")
    }
}

/// One detected vehicle in one frame.
public struct VehicleBox: Sendable, Equatable {
    /// COCO label from the model: "bicycle", "car", "motorcycle", "bus" or "truck".
    public let label: String
    public let confidence: Float
    /// Normalized 0...1, origin top-left, in the upright (horizon-level) frame.
    public let rect: CGRect

    public init(label: String, confidence: Float, rect: CGRect) {
        self.label = label
        self.confidence = confidence
        self.rect = rect
    }
}

/// Everything the detector produced for one processed camera frame.
public struct DetectionFrame: Sendable {
    public let boxes: [VehicleBox]
    /// Camera presentation time in seconds (monotonic; use differences, not absolute values).
    public let timestamp: Double
    /// Upright frame size in pixels; width > height when the phone is in landscape.
    public let imageSize: CGSize
    public let inferenceMs: Double
    /// Processed frames per second, smoothed.
    public let fps: Double
}

public enum FrameGeometry {
    /// COCO classes we care about (bicycle 1, car 2, motorcycle 3, bus 5, truck 7). Keep in sync with
    /// `vehicle_classes` in cv/approach_config.json. Bicycle stands in for e-scooters/e-bikes: COCO has
    /// no scooter class, and only something faster than the rider can "approach" from behind.
    public static let vehicleLabels: Set<String> = ["bicycle", "car", "motorcycle", "bus", "truck"]

    /// Vision boxes are normalized with the origin at the bottom-left; flip to top-left.
    public static func topLeftRect(fromVision r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// Orientation to hand Vision so a buffer from the back camera is read upright, given the
    /// rotation angle AVCaptureDevice.RotationCoordinator reports for horizon-level capture.
    public static func imageOrientation(forRotationAngle degrees: CGFloat) -> CGImagePropertyOrientation {
        switch (Int(degrees.rounded()) % 360 + 360) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    /// Pixel size of the upright frame for a buffer of the given size and orientation.
    public static func uprightSize(bufferWidth: Int, bufferHeight: Int, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: bufferHeight, height: bufferWidth)
        default:
            return CGSize(width: bufferWidth, height: bufferHeight)
        }
    }
}
