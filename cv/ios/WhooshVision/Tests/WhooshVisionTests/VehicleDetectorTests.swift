import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WhooshVision

/// Runs the real model on Ultralytics' sample bus photo (runs on a Mac with `swift test`).
@Test func detectsTheBusInTheSamplePhoto() async throws {
    let url = try #require(Bundle.module.url(forResource: "bus", withExtension: "jpg"))
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

    let detector = try await VehicleDetector.load()
    let frame = try detector.detect(in: image, timestamp: 0)

    let bus = try #require(frame.boxes.first { $0.label == "bus" })
    #expect(bus.confidence > 0.5)
    // Python/Ultralytics puts it at x 0.03-0.99, y 0.21-0.70 (top-left origin). A centre near 0.46
    // (not 0.54) also proves the Vision bottom-left -> top-left flip is right.
    #expect(bus.rect.width > 0.85)
    #expect(abs(bus.rect.midY - 0.46) < 0.04)
    // People are in the photo but aren't vehicles.
    #expect(frame.boxes.allSatisfy { FrameGeometry.vehicleLabels.contains($0.label) })
    #expect(frame.imageSize == CGSize(width: image.width, height: image.height))
}

@Test func fpsIsMeasuredFromTimestamps() async throws {
    let url = try #require(Bundle.module.url(forResource: "bus", withExtension: "jpg"))
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

    let detector = try await VehicleDetector.load()
    _ = try detector.detect(in: image, timestamp: 0)
    let frame = try detector.detect(in: image, timestamp: 0.1)
    #expect(abs(frame.fps - 10) < 0.01)
}
