import Foundation
import WhooshWire

/// Preview / demo-mode support for the watch UI (tasks 15, 20). It builds a
/// `WatchSessionModel` wired entirely to fakes and injects scripted wire
/// statuses, so every page can be shown with realistic data **before the phone
/// link is live** — in SwiftUI previews and in an on-device demo mode. Nothing
/// here touches WatchConnectivity, HealthKit, or WatchKit.
///
/// Honest copy only: the rear-vehicle cue is experimental; Whoosh cannot
/// guarantee detection or delivery.
@MainActor
public enum WatchDemo {
    /// A model wired to fakes, with a demo clock, haptic recorder, and workout
    /// stub. Use `WatchDemo.clock` to advance time in a preview.
    public static func makeModel(
        scenario: Scenario = .riding
    ) -> WatchSessionModel {
        let clock = FakeMonotonicClock(startMs: 10_000)
        let link = FakeWireLink(reachable: scenario != .noLink)
        let haptics = FakeHapticPlayer(isActive: true)
        let workout = FakeWorkoutSessionController()
        let model = WatchSessionModel(
            link: link,
            haptics: haptics,
            workout: workout,
            clock: clock
        )
        model.injectForPreview(status: scenario.status, summary: scenario.summary)
        if let crash = scenario.crash { model.injectForPreview(crashOnly: crash) }
        return model
    }

    /// The demo scenarios the previews and demo mode cycle through.
    public enum Scenario: String, CaseIterable, Sendable {
        case idleReady          // armed, ready to start from the wrist
        case idleNotReady       // waiting on the phone
        case riding             // recording, camera on, numbers live
        case ridingCameraTrouble
        case paused
        case signalLost
        case summary
        case crashDrill
        case noLink

        public var title: String {
            switch self {
            case .idleReady: return "Ready"
            case .idleNotReady: return "Not ready"
            case .riding: return "Riding"
            case .ridingCameraTrouble: return "Camera trouble"
            case .paused: return "Paused"
            case .signalLost: return "Signal lost"
            case .summary: return "Summary"
            case .crashDrill: return "Crash drill"
            case .noLink: return "No link"
            }
        }

        var status: WireRideStatus {
            switch self {
            case .idleReady:
                return WatchDemo.status(state: .idle, camera: .off, cameraFeature: .on,
                                        start: .armed(untilMs: 280_000))
            case .idleNotReady:
                return WatchDemo.status(state: .idle, camera: .off, start: .ready)
            case .riding:
                return WatchDemo.status(state: .recording, activeMs: 1_845_000,
                                        distance10m: 1_207, speedDms: 62,
                                        camera: .recording, cameraFeature: .on, clipCount: 2)
            case .ridingCameraTrouble:
                return WatchDemo.status(state: .recording, activeMs: 920_000,
                                        distance10m: 640, speedDms: 48,
                                        camera: .interrupted, cameraFeature: .on,
                                        cameraReason: .interrupted)
            case .paused:
                return WatchDemo.status(state: .paused, activeMs: 1_200_000,
                                        distance10m: 800, speedDms: 0,
                                        camera: .recording, cameraFeature: .on)
            case .signalLost:
                return WatchDemo.status(state: .signalLost, activeMs: 300_000,
                                        distance10m: 210, speedDms: 55,
                                        camera: .recording, cameraFeature: .on,
                                        banner: .signalLost)
            case .summary:
                return WatchDemo.status(state: .finished, activeMs: 2_700_000,
                                        distance10m: 1_900, speedDms: 58, camera: .off)
            case .crashDrill:
                return WatchDemo.status(state: .recording, activeMs: 600_000,
                                        distance10m: 410, speedDms: 50,
                                        camera: .recording, cameraFeature: .on,
                                        crash: WireCrashStatus(eventId: "demo-evt",
                                                               remainingMs: 10_000,
                                                               isDrill: true,
                                                               contactCount: 2,
                                                               phase: .countdown))
            case .noLink:
                return WatchDemo.status(state: .recording, activeMs: 500_000,
                                        distance10m: 300, speedDms: 52,
                                        camera: .recording, cameraFeature: .on)
            }
        }

        var crash: WireCrashStatus? {
            if case .crashDrill = self { return status.crash }
            return nil
        }

        var summary: WireSummary? {
            guard case .summary = self else { return nil }
            return WireSummary(rideId: "demo", durationMs: 2_700_000, distance10m: 1_900,
                               avgSpeedDms: 58, cueCount: 3, noticeCount: 2, cameraGapCount: 1)
        }
    }

    /// Build a `WireRideStatus` for demo data with sensible defaults.
    public static func status(
        rideId: String = "demo-ride",
        epoch: Int = 1,
        seq: Int = 1,
        state: WireRideState,
        activeMs: Int = 0,
        distance10m: Int = 0,
        speedDms: Int? = nil,
        camera: WireCameraState = .off,
        cameraFeature: WireCameraFeature = .off,
        cameraReason: WireCameraReason? = nil,
        banner: WireBanner = .none,
        clipCount: Int = 0,
        start: WireStartState = .ready,
        crash: WireCrashStatus? = nil,
        demo: Bool = true
    ) -> WireRideStatus {
        WireRideStatus(
            rideId: rideId,
            epoch: epoch,
            seq: seq,
            state: state,
            activeMs: activeMs,
            distance10m: distance10m,
            speedDms: speedDms,
            camera: WireCameraStatus(feature: cameraFeature, state: camera, reason: cameraReason),
            phone: WirePhoneState(batteryPct: 74, charging: false),
            banner: banner,
            crash: crash,
            clip: WireClipStatus(count: clipCount),
            start: start,
            demo: demo
        )
    }
}
