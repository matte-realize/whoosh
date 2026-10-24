import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ImageIO
import QuartzCore
import Vision

public enum DetectorError: Error {
    case modelMissing
}

/// Runs YOLO26n (Core ML via Vision) on frames the app's camera code hands in and returns the
/// vehicle boxes. Camera capture and preview live in the app, not here.
///
/// `detect` is synchronous and not reentrant: call it from one serial background queue (e.g. the
/// camera's sample-buffer queue), never the main thread. ~10-40 ms per frame on a recent iPhone.
public final class VehicleDetector: @unchecked Sendable {
    public let minimumConfidence: Float
    private let request: VNCoreMLRequest
    private var lastTimestamp: Double?
    private var fps: Double = 0

    private init(request: VNCoreMLRequest, minimumConfidence: Float) {
        self.request = request
        self.minimumConfidence = minimumConfidence
    }

    /// Compiles and loads the bundled model (~1 s). Do this once, before the camera starts.
    /// - Parameters:
    ///   - minimumConfidence: detections below this are dropped. The near-miss logic applies its own, higher bar.
    ///   - iouThreshold: overlap at which the model's NMS merges duplicate boxes.
    public static func load(minimumConfidence: Float = 0.25, iouThreshold: Double = 0.7) async throws -> VehicleDetector {
        guard let url = WhooshVisionModel.url else { throw DetectorError.modelMissing }
        let compiled = url.pathExtension == "mlmodelc" ? url : try await MLModel.compileModel(at: url)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try VNCoreMLModel(for: MLModel(contentsOf: compiled, configuration: configuration))
        // The exported pipeline's NMS stage takes these as (required) inputs.
        model.featureProvider = ThresholdProvider(iouThreshold: iouThreshold, confidenceThreshold: Double(minimumConfidence))
        let request = VNCoreMLRequest(model: model)
        // Letterbox like Ultralytics does in Python. Stretching 16:9 to the square input
        // (.scaleFill) lost every detection on our near-miss test footage.
        request.imageCropAndScaleOption = .scaleFit
        return VehicleDetector(request: request, minimumConfidence: minimumConfidence)
    }

    /// Detects vehicles in one camera frame.
    /// - Parameters:
    ///   - orientation: how to read the buffer upright. From a camera rotation angle, use
    ///     `FrameGeometry.imageOrientation(forRotationAngle:)`.
    ///   - timestamp: frame time in seconds, monotonic (e.g. the sample buffer's presentation time).
    public func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up,
                       timestamp: Double) throws -> DetectionFrame {
        let size = FrameGeometry.uprightSize(bufferWidth: CVPixelBufferGetWidth(pixelBuffer),
                                             bufferHeight: CVPixelBufferGetHeight(pixelBuffer),
                                             orientation: orientation)
        return try run(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation),
                       imageSize: size, timestamp: timestamp)
    }

    /// Detects vehicles in a still image (tests, or frames from a video file).
    public func detect(in image: CGImage, orientation: CGImagePropertyOrientation = .up,
                       timestamp: Double) throws -> DetectionFrame {
        let size = FrameGeometry.uprightSize(bufferWidth: image.width, bufferHeight: image.height, orientation: orientation)
        return try run(VNImageRequestHandler(cgImage: image, orientation: orientation),
                       imageSize: size, timestamp: timestamp)
    }

    private func run(_ handler: VNImageRequestHandler, imageSize: CGSize, timestamp: Double) throws -> DetectionFrame {
        let start = CACurrentMediaTime()
        try handler.perform([request])
        let inferenceMs = (CACurrentMediaTime() - start) * 1000

        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        let boxes = observations.compactMap { observation -> VehicleBox? in
            guard let top = observation.labels.first,
                  FrameGeometry.vehicleLabels.contains(top.identifier),
                  top.confidence >= minimumConfidence else { return nil }
            return VehicleBox(label: top.identifier, confidence: top.confidence,
                              rect: FrameGeometry.topLeftRect(fromVision: observation.boundingBox))
        }

        if let lastTimestamp, timestamp > lastTimestamp {
            let instant = 1 / (timestamp - lastTimestamp)
            fps = fps == 0 ? instant : 0.9 * fps + 0.1 * instant
        }
        lastTimestamp = timestamp

        return DetectionFrame(boxes: boxes, timestamp: timestamp, imageSize: imageSize,
                              inferenceMs: inferenceMs, fps: fps)
    }
}

/// Supplies the NMS thresholds the exported Core ML pipeline expects as inputs.
private final class ThresholdProvider: NSObject, MLFeatureProvider {
    private let values: [String: MLFeatureValue]

    init(iouThreshold: Double, confidenceThreshold: Double) {
        values = [
            "iouThreshold": MLFeatureValue(double: iouThreshold),
            "confidenceThreshold": MLFeatureValue(double: confidenceThreshold),
        ]
        super.init()
    }

    var featureNames: Set<String> { Set(values.keys) }

    func featureValue(for featureName: String) -> MLFeatureValue? { values[featureName] }
}
