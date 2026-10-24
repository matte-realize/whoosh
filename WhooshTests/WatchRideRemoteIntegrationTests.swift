import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Integration tests INT-1…6 for `WatchRideRemote` over the `LoopbackWireLinkPair`
/// with the real `RideSessionViewModel` + `RideRemoteBridge` (watch-companion
/// spec task 13; Requirement 7.1, 7.3–7.9, 6.1–6.6, 20.8). Written test-first.
///
/// The watch side encodes a `WireCommand`, sends it live over the loopback, and
/// the phone's `WatchRideRemote` decodes → dedupe → `RemoteCommandReducer` →
/// `RideRemoteBridge` effect → reply with a fresh status. The ride engine is the
/// real one (unchanged), so a remote failure can never corrupt ride state or GPS.
///
/// The `WireLink` delivers live messages off the main actor, so the snapshot
/// provider reads a lock-protected mirror of the ride state that the harness
/// refreshes on the main actor before each command (mirroring how the real
/// composition root keeps a `Sendable` snapshot in sync).
@MainActor
struct WatchRideRemoteIntegrationTests {
    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    /// A lock-protected snapshot the provider reads from any thread.
    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: WatchRideRemote.Snapshot
        init(_ value: WatchRideRemote.Snapshot) { self.value = value }
        func read() -> WatchRideRemote.Snapshot { lock.withLock { value } }
        func set(_ v: WatchRideRemote.Snapshot) { lock.withLock { value = v } }
    }

    private final class Spy: @unchecked Sendable {
        var saveClipCount = 0
        var cancelCount = 0
    }

    /// The assembled system under test.
    @MainActor
    private final class System {
        let pair: LoopbackWireLinkPair
        let remote: WatchRideRemote
        let vm: RideSessionViewModel
        let tracker: FakeLocationTracker
        let spy: Spy
        let box: SnapshotBox
        var camera: RemoteCommandReducer.CameraSnapshot
        var crash: RemoteCommandReducer.CrashSnapshot

        init(
            pair: LoopbackWireLinkPair, remote: WatchRideRemote,
            vm: RideSessionViewModel, tracker: FakeLocationTracker, spy: Spy,
            box: SnapshotBox, camera: RemoteCommandReducer.CameraSnapshot,
            crash: RemoteCommandReducer.CrashSnapshot
        ) {
            self.pair = pair; self.remote = remote; self.vm = vm
            self.tracker = tracker; self.spy = spy; self.box = box
            self.camera = camera; self.crash = crash
        }

        /// Refresh the lock-protected snapshot from the live ride state.
        func refresh() {
            box.set(WatchRideRemote.Snapshot(
                status: System.status(vm, at: epoch),
                rideId: vm.rideState.isActive ? "ride-1" : "",
                epoch: 1, camera: camera, crash: crash
            ))
        }

        /// Encode a command, refresh the snapshot, process it through the phone
        /// remote's real pipeline (dedupe → reducer → bridge → reply), and decode
        /// the reply. The command envelope travels the loopback encode path; the
        /// real WatchConnectivity adapter (task 16) does the delegate-queue →
        /// main-actor hop that is stubbed here by a direct main-actor call.
        func send(_ command: WireCommand, replyLost: Bool = false) -> WireCommandReply? {
            refresh()
            guard let envelope = try? WireCodec.encode(
                command, id: command.commandId, seq: 0, sentAt: epoch.timeIntervalSince1970
            ) else { return nil }
            let reply = remote.handleCommand(envelope)
            if replyLost { return nil }   // the command applied, the reply was dropped
            guard let reply else { return nil }
            return try? WireCodec.decodePayload(WireCommandReply.self, from: reply)
        }

        static func status(_ vm: RideSessionViewModel, at epoch: Date) -> RideStatus {
            RideStatus(
                rideState: vm.rideState,
                activeDurationAnchor: 0, anchorDate: epoch,
                distanceMeters: 0, speedMetersPerSecond: nil,
                cameraState: .off, cameraStopReason: nil,
                storageStatus: .ok, thermalLevel: .nominal,
                phoneBatteryPercent: 0.9, isCharging: false,
                banner: nil, crashCountdownDeadline: nil,
                lastClipSavedAt: nil, lastDegradationNote: nil
            )
        }
    }

    private static func makeSystem(
        camera: RemoteCommandReducer.CameraSnapshot = .off,
        crash: RemoteCommandReducer.CrashSnapshot = .none,
        saveOutcome: ClipSaveOutcome = .saved
    ) async -> System {
        let tracker = FakeLocationTracker(authorizationStatus: .authorizedWhenInUse)
        let clock = TestClock(now: epoch)
        let repo = InMemoryRideRepository()
        var counter = 0
        let vm = RideSessionViewModel(
            tracker: tracker, clock: clock, repository: repo,
            makeID: {
                counter += 1
                return UUID(uuidString: "00000000-0000-0000-0000-00000000000\(counter)")!
            }
        )
        let spy = Spy()
        let pair = LoopbackWireLinkPair()
        let box = SnapshotBox(WatchRideRemote.Snapshot(status: System.status(vm, at: epoch)))
        let remote = WatchRideRemote(link: pair.phone, clock: clock) { box.read() }
        let bridge = RideRemoteBridge(
            rideViewModel: vm,
            saveClip: { spy.saveClipCount += 1; return saveOutcome },
            cancelCrashCountdown: { spy.cancelCount += 1 }
        )
        remote.onCommand = { command, reply in reply(bridge.handle(command)) }
        await remote.activate()
        return System(
            pair: pair, remote: remote, vm: vm, tracker: tracker, spy: spy,
            box: box, camera: camera, crash: crash
        )
    }

    // INT-1: pause / resume end to end change the real ride state; reply accepted.
    @Test func pauseResumeEndToEnd() async {
        let sys = await Self.makeSystem()
        sys.vm.start()
        #expect(sys.vm.rideState == .recording)

        let pauseReply = sys.send(WireCommand(commandId: "c1", kind: .pause, rideId: "ride-1"))
        #expect(pauseReply?.outcome == .accepted)
        #expect(sys.vm.rideState == .paused)

        let resumeReply = sys.send(WireCommand(commandId: "c2", kind: .resume, rideId: "ride-1"))
        #expect(resumeReply?.outcome == .accepted)
        #expect(sys.vm.rideState == .recording)
    }

    // INT-2: stop with a confirmed hold ends the ride; without it is rejected.
    @Test func stopEndToEnd() async {
        let sys = await Self.makeSystem()
        sys.vm.start()
        sys.tracker.emit(RoutePoint(latitude: 42, longitude: -71, timestamp: Self.epoch.addingTimeInterval(1), speedMetersPerSecond: 5, horizontalAccuracyMeters: 5))

        let noHold = sys.send(WireCommand(commandId: "s1", kind: .stop, rideId: "ride-1", holdConfirmed: false))
        #expect(noHold?.outcome == .rejected)
        #expect(sys.vm.rideState == .recording)

        let held = sys.send(WireCommand(commandId: "s2", kind: .stop, rideId: "ride-1", holdConfirmed: true))
        #expect(held?.outcome == .accepted)
        #expect(sys.vm.rideState == .finished)
    }

    // INT-3: saveClip routes to the pinner and the reply carries the detail.
    @Test func saveClipEndToEnd() async {
        let sys = await Self.makeSystem(camera: RemoteCommandReducer.CameraSnapshot(isRecording: true))
        sys.vm.start()
        let reply = sys.send(WireCommand(commandId: "k1", kind: .saveClip, rideId: "ride-1"))
        #expect(reply?.outcome == .accepted)
        #expect(reply?.detail == .saved)
        #expect(sys.spy.saveClipCount == 1)
    }

    // INT-4: a stale ride id can never act on a new ride (ignored, state unchanged).
    @Test func staleRideIdIgnored() async {
        let sys = await Self.makeSystem()
        sys.vm.start()   // active ride is "ride-1"
        let reply = sys.send(WireCommand(commandId: "p9", kind: .pause, rideId: "OLD-RIDE"))
        #expect(reply?.outcome == .ignored)
        #expect(reply?.reason == .staleRide)
        #expect(sys.vm.rideState == .recording)
    }

    // INT-5: a duplicate commandId returns the cached reply and applies once.
    @Test func duplicateCommandAppliesOnce() async {
        let sys = await Self.makeSystem()
        sys.vm.start()
        let first = sys.send(WireCommand(commandId: "dup", kind: .pause, rideId: "ride-1"))
        #expect(first?.outcome == .accepted)
        #expect(sys.vm.rideState == .paused)

        // Resume manually, then replay the SAME paused command id: it must not
        // re-pause (effect applied once; cached reply replayed).
        sys.vm.resume()
        #expect(sys.vm.rideState == .recording)
        let dup = sys.send(WireCommand(commandId: "dup", kind: .pause, rideId: "ride-1"))
        #expect(dup?.outcome == .accepted)   // cached reply
        #expect(sys.vm.rideState == .recording)  // NOT re-paused
    }

    // INT-6: a dropped reply then a same-id retry still resolves; remote failure
    // never changes ride state.
    @Test func replyLostThenRetry() async {
        let sys = await Self.makeSystem()
        sys.vm.start()

        // Drop the reply on the first attempt (the command still applies).
        let lost = sys.send(WireCommand(commandId: "r1", kind: .pause, rideId: "ride-1", attempt: 1), replyLost: true)
        #expect(lost == nil)                     // reply swallowed
        #expect(sys.vm.rideState == .paused)     // but the command applied

        // Retry the SAME id with the reply flowing; the cached reply comes back
        // and the ride is not double-applied.
        let retry = sys.send(WireCommand(commandId: "r1", kind: .pause, rideId: "ride-1", attempt: 2))
        #expect(retry?.outcome == .accepted)
        #expect(sys.vm.rideState == .paused)
    }
}
