import Foundation
import Testing
@testable import Whoosh

/// Tests for `CameraPreviewViewModel` — the view-only holder that feeds the
/// active ride screen's live preview + detection overlay (owner device-testing
/// feedback: "the user should be able to see the camera"). It never captures or
/// uploads; it only forwards the latest view-only boxes.
@MainActor
struct CameraPreviewViewModelTests {
    @Test func updateReplacesTheBoxes() {
        let vm = CameraPreviewViewModel(previewHost: nil)
        #expect(vm.boxes.isEmpty)

        let boxes = [
            DetectionOverlayBox(label: "car", confidence: 0.8, x: 0.1, y: 0.1, width: 0.2, height: 0.2, isApproaching: true),
            DetectionOverlayBox(label: "truck", confidence: 0.6, x: 0.5, y: 0.3, width: 0.1, height: 0.1)
        ]
        vm.update(boxes: boxes)
        #expect(vm.boxes.count == 2)
        #expect(vm.boxes.first?.isApproaching == true)

        // A later frame with no detections clears them.
        vm.update(boxes: [])
        #expect(vm.boxes.isEmpty)
    }

    @Test func clearEmptiesTheBoxes() {
        let vm = CameraPreviewViewModel(previewHost: nil)
        vm.update(boxes: [DetectionOverlayBox(label: "car", confidence: 0.9, x: 0, y: 0, width: 0.3, height: 0.3)])
        #expect(!vm.boxes.isEmpty)

        vm.clear()
        #expect(vm.boxes.isEmpty)
    }

    @Test func hasPreviewReflectsTheHost() {
        let noHost = CameraPreviewViewModel(previewHost: nil)
        #expect(noHost.hasPreview == false)

        let withHost = CameraPreviewViewModel(previewHost: NoopCameraPreviewHost())
        #expect(withHost.hasPreview == true)
    }
}
