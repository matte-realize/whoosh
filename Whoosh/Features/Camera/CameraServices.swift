import Foundation
import UIKit

/// The shared rear-camera service stack the composition root builds once and
/// uses to construct a per-ride `CameraRecordingCoordinator` and the Mount &
/// frame screen (rear-camera task 19/22). Bundling these keeps `AppEnvironment`
/// readable and keeps every framework-owning type behind a protocol.
///
/// All members are protocols or small closures so the preview/test stack can be
/// built entirely from fakes (no AVFoundation, Core Motion, or disk). Footage is
/// on-device only; nothing here touches the network.
///
/// `@MainActor` to match the camera seams (capture, store, pinner, sensor).
@MainActor
struct CameraServices {
    /// The capture seam (the only capture-session owner live; a fake in tests).
    let capture: CameraCapturing
    /// The Mount & frame preview host (the capture service live; a no-op in tests).
    let previewHost: CameraPreviewHost
    /// The frame pipeline consumers register with (shared with the detector).
    let pipeline: FramePipeline?
    /// The ring-buffer segment store.
    let segmentStore: SegmentStore
    /// The clip pinner (manual save / finalize / cascade).
    let clipPinner: ClipPinner
    /// The persisted rear-camera settings store (camera, quality, buffer, etc).
    let settingsStore: RearCameraSettingsStore
    /// The tuning constants (one source).
    let tuning: RideCameraTuning
    /// Builds a per-ride segment recorder (the writer is keyed to the ride id).
    let makeRecorder: (UUID) -> SegmentRecording
    /// Builds a Mount & frame level sensor (one per screen presentation).
    let makeLevelSensor: () -> MountLevelSensing

    // MARK: - Live

    /// The real stack: a `FileSegmentStore` + `AssetWriterSegmentRecorder` over
    /// the on-device camera root, a `FramePipeline`, a `ClipPinner` over the
    /// shared clip repository, and a Core Motion `MountLevelSensor`.
    static func live(
        capture: CameraCapturing,
        previewHost: CameraPreviewHost,
        clipRepository: ClipRepository,
        settingsStore: RearCameraSettingsStore,
        clock: Clock,
        tuning: RideCameraTuning = RideCameraTuning()
    ) -> CameraServices {
        let layout = CameraStorageLayout(root: CameraStorageLayout.defaultRoot())
        let segmentStore = FileSegmentStore(layout: layout)
        let clipPinner = ClipPinner(
            segmentStore: segmentStore,
            clipRepository: clipRepository,
            thumbnailer: AssetImageClipThumbnailer(),
            layout: layout,
            tuning: tuning,
            clock: clock
        )
        return CameraServices(
            capture: capture,
            previewHost: previewHost,
            pipeline: FramePipeline(),
            segmentStore: segmentStore,
            clipPinner: clipPinner,
            settingsStore: settingsStore,
            tuning: tuning,
            makeRecorder: { rideId in
                AssetWriterSegmentRecorder(layout: layout, rideId: rideId, tuning: tuning)
            },
            makeLevelSensor: { MountLevelSensor() }
        )
    }

    // MARK: - Fake (previews / tests)

    /// The fake stack: a `FakeCameraCapture`, an in-memory segment store, a
    /// `ClipPinner` over an in-memory repository with a fake thumbnailer, and a
    /// `FakeMountLevelSensor`. Nothing touches a framework or disk.
    static func fake(
        clipRepository: ClipRepository,
        settingsStore: RearCameraSettingsStore,
        clock: Clock,
        tuning: RideCameraTuning = RideCameraTuning()
    ) -> CameraServices {
        let layout = CameraStorageLayout(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("WhooshPreviewCamera", isDirectory: true))
        let segmentStore = InMemorySegmentStore()
        let clipPinner = ClipPinner(
            segmentStore: segmentStore,
            clipRepository: clipRepository,
            thumbnailer: FakeClipThumbnailer(),
            layout: layout,
            tuning: tuning,
            clock: clock
        )
        return CameraServices(
            capture: FakeCameraCapture(),
            previewHost: NoopCameraPreviewHost(),
            pipeline: FramePipeline(),
            segmentStore: segmentStore,
            clipPinner: clipPinner,
            settingsStore: settingsStore,
            tuning: tuning,
            makeRecorder: { _ in FakeSegmentRecorder() },
            makeLevelSensor: { FakeMountLevelSensor() }
        )
    }
}

/// A preview/test `CameraPreviewHost` that returns a plain black view (no
/// capture session), so Mount & frame renders in previews without AVFoundation.
@MainActor
final class NoopCameraPreviewHost: CameraPreviewHost {
    func makePreviewView() -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
}
