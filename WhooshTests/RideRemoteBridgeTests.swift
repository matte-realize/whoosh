import Foundation
import Testing
@testable import Whoosh

/// Tests RC-1…6 for `RideRemoteBridge` (rear-camera task 13, Requirements
/// 13.1–13.3, 13.8; design "Eyes-free surfaces": the bridge maps
/// `RideRemoteCommand`s to the **existing** `RideSessionViewModel` intents,
/// to a save-clip action, and to a cancel-crash-countdown action). Written
/// test-first.
///
/// The ride engine is unchanged: the bridge reuses `start`/`pause`/`resume`/
/// `stop` on the real view model and routes `saveClip`/`cancelCrashCountdown`
/// to injected closures (the pinner and the crash coordinator are wired at the
/// composition root). `stop` is honoured only with `confirmedByHold`.
///
/// Uses the real ride engine with `FakeLocationTracker` + `TestClock` +
/// `InMemoryRideRepository`, so the ride internals stay unchanged.
@MainActor
struct RideRemoteBridgeTests {
    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    private static func makeRide() -> (RideSessionViewModel, FakeLocationTracker, TestClock) {
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
        return (vm, tracker, clock)
    }

    private final class Spy {
        var saveClipCount = 0
        var cancelCount = 0
    }

    private static func makeBridge(_ vm: RideSessionViewModel, spy: Spy)
        -> RideRemoteBridge {
        RideRemoteBridge(
            rideViewModel: vm,
            saveClip: { spy.saveClipCount += 1; return .saved },
            cancelCrashCountdown: { spy.cancelCount += 1 }
        )
    }

    // RC-1: pause/resume map to the engine intents and change ride state.
    @Test func pauseResumeMapToIntents() {
        let (vm, _, _) = Self.makeRide()
        let spy = Spy()
        let bridge = Self.makeBridge(vm, spy: spy)
        vm.start()
        #expect(vm.rideState == .recording)

        _ = bridge.handle(.pause)
        #expect(vm.rideState == .paused)
        _ = bridge.handle(.resume)
        #expect(vm.rideState == .recording)
    }

    // RC-2: pause/resume are idempotent — a redundant command is a no-op reply,
    // never a crash or a bad state.
    @Test func pauseResumeIdempotent() {
        let (vm, _, _) = Self.makeRide()
        let spy = Spy()
        let bridge = Self.makeBridge(vm, spy: spy)
        vm.start()
        _ = bridge.handle(.pause)
        let reply = bridge.handle(.pause)   // already paused
        #expect(vm.rideState == .paused)
        #expect(reply == .ignored(reason: .invalidState))

        _ = bridge.handle(.resume)
        let reply2 = bridge.handle(.resume) // already recording
        #expect(vm.rideState == .recording)
        #expect(reply2 == .ignored(reason: .invalidState))
    }

    // RC-3: stop WITHOUT a confirmed hold is ignored (an accidental wrist tap
    // must never end a ride); the ride stays active.
    @Test func stopWithoutHoldIsIgnored() {
        let (vm, _, _) = Self.makeRide()
        let spy = Spy()
        let bridge = Self.makeBridge(vm, spy: spy)
        vm.start()
        let reply = bridge.handle(.stop(confirmedByHold: false))
        #expect(vm.rideState == .recording)
        #expect(reply == .ignored(reason: .notConfirmed))
    }

    // RC-4: stop WITH a confirmed hold ends the ride.
    @Test func stopWithHoldEndsRide() {
        let (vm, tracker, _) = Self.makeRide()
        let spy = Spy()
        let bridge = Self.makeBridge(vm, spy: spy)
        vm.start()
        tracker.emit(RoutePoint(latitude: 42, longitude: -71, timestamp: Self.epoch.addingTimeInterval(1), speedMetersPerSecond: 5, horizontalAccuracyMeters: 5))
        let reply = bridge.handle(.stop(confirmedByHold: true))
        #expect(vm.rideState == .finished)
        #expect(reply == .accepted)
    }

    // RC-5: saveClip routes to the injected pinner and returns its outcome;
    // nothing-to-save is surfaced as an ignored reply (not an error).
    @Test func saveClipRoutesToPinner() {
        let (vm, _, _) = Self.makeRide()
        let spy = Spy()
        let bridge = Self.makeBridge(vm, spy: spy)
        vm.start()
        let reply = bridge.handle(.saveClip)
        #expect(spy.saveClipCount == 1)
        #expect(reply == .accepted)
    }

    @Test func saveClipNothingToSaveIsIgnored() {
        let (vm, _, _) = Self.makeRide()
        let spy = Spy()
        let bridge = RideRemoteBridge(
            rideViewModel: vm,
            saveClip: { spy.saveClipCount += 1; return .nothingToSave },
            cancelCrashCountdown: { spy.cancelCount += 1 }
        )
        vm.start()
        let reply = bridge.handle(.saveClip)
        #expect(reply == .ignored(reason: .nothingToSave))
    }

    // RC-6: cancelCrashCountdown routes to the injected crash action; an unknown
    // command (modelled by cancel with no active countdown) is handled by the
    // closure. Here the closure always runs, so the reply is accepted.
    @Test func cancelCrashCountdownRoutes() {
        let (vm, _, _) = Self.makeRide()
        let spy = Spy()
        let bridge = Self.makeBridge(vm, spy: spy)
        vm.start()
        let reply = bridge.handle(.cancelCrashCountdown)
        #expect(spy.cancelCount == 1)
        #expect(reply == .accepted)
    }

    // A command that does not apply to the current state (pause when idle) is
    // ignored rather than crashing.
    @Test func commandInInvalidStateIsIgnored() {
        let (vm, _, _) = Self.makeRide()
        let spy = Spy()
        let bridge = Self.makeBridge(vm, spy: spy)
        // not started → idle
        let reply = bridge.handle(.pause)
        #expect(reply == .ignored(reason: .invalidState))
        #expect(vm.rideState == .idle)
    }
}
