import CoreGraphics
import ImageIO
import Testing
@testable import WhooshVision

@Test func visionRectIsFlippedToTopLeft() {
    let r = FrameGeometry.topLeftRect(fromVision: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    #expect(abs(r.minX - 0.1) < 1e-9)
    #expect(abs(r.minY - 0.4) < 1e-9)
    #expect(abs(r.width - 0.3) < 1e-9)
    #expect(abs(r.height - 0.4) < 1e-9)
}

@Test(arguments: [
    (CGFloat(0), CGImagePropertyOrientation.up),
    (90, .right),
    (180, .down),
    (270, .left),
    (-90, .left),
    (360, .up),
])
func rotationAngleMapsToOrientation(angle: CGFloat, expected: CGImagePropertyOrientation) {
    #expect(FrameGeometry.imageOrientation(forRotationAngle: angle) == expected)
}

@Test func portraitOrientationSwapsSize() {
    #expect(FrameGeometry.uprightSize(bufferWidth: 1280, bufferHeight: 720, orientation: .right) == CGSize(width: 720, height: 1280))
    #expect(FrameGeometry.uprightSize(bufferWidth: 1280, bufferHeight: 720, orientation: .up) == CGSize(width: 1280, height: 720))
}

@Test func modelIsBundled() {
    #expect(WhooshVisionModel.url != nil)
}
