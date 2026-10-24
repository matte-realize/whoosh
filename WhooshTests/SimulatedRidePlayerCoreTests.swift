import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure scripted-route model and the player-core timing/scaling
/// math (demo-mode task 1, Requirements 5.2/5.3/5.8). Pure and Foundation-only:
/// no `Clock`, no device.
struct SimulatedRidePlayerCoreTests {
    // MARK: Script shape (Req 5.2)

    @Test func bundledLoopHasMonotonicOffsets() {
        #expect(DemoRideScript.charlesRiverLoop.hasMonotonicOffsets)
    }

    @Test func bundledLoopDeclaresPauseAndSignalLossSegments() {
        let script = DemoRideScript.charlesRiverLoop
        #expect(script.pauseWindow != nil)
        #expect(script.signalLossWindow != nil)
    }

    @Test func signalLossGapIsLongerThanDefaultLossTimeout() {
        // The gap must exceed the MVP's 8 s loss timeout so the amber banner
        // actually appears during a simulated ride.
        let window = DemoRideScript.charlesRiverLoop.signalLossWindow
        #expect(window != nil)
        if let window {
            #expect(window.upperBound - window.lowerBound > RideTuning().signalLossTimeout)
        }
    }

    @Test func totalDurationIsLastOffset() {
        let script = DemoRideScript.charlesRiverLoop
        #expect(script.totalDuration == script.points.last?.offsetSeconds)
    }

    @Test func emptyScriptIsMonotonicWithZeroDuration() {
        let empty = DemoRideScript(name: "Empty", points: [])
        #expect(empty.hasMonotonicOffsets)
        #expect(empty.totalDuration == 0)
        #expect(empty.signalLossWindow == nil)
        #expect(empty.pauseWindow == nil)
    }

    // MARK: Due-point selection at 1× (Req 5.3/5.8)

    @Test func duePointsAtOneXReturnsPointsUpToElapsed() {
        let script = DemoRideScript.charlesRiverLoop
        // At 25 s elapsed (1×), points at offsets 0,10,20 are due (30 is not).
        let due = SimulatedRidePlayerCore.duePoints(
            in: script, speedFactor: 1, elapsedPlayback: 25
        )
        #expect(due.map(\.offsetSeconds) == [0, 10, 20])
    }

    @Test func duePointsExcludesWithheldSignalLossPoints() {
        // Build a tiny script with an explicit withheld point inside the gap.
        let script = DemoRideScript(name: "Gap", points: [
            ScriptedRoutePoint(latitude: 0, longitude: 0, offsetSeconds: 0, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5),
            ScriptedRoutePoint(latitude: 0, longitude: 0, offsetSeconds: 10, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5, marker: .signalLossStart),
            ScriptedRoutePoint(latitude: 0, longitude: 0, offsetSeconds: 15, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5),
            ScriptedRoutePoint(latitude: 0, longitude: 0, offsetSeconds: 25, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5, marker: .signalLossEnd),
        ])
        // The start-of-gap (10) and the interior point (15) are withheld; only
        // 0 and the end point (25) are ever delivered.
        let due = SimulatedRidePlayerCore.duePoints(
            in: script, speedFactor: 1, elapsedPlayback: 100
        )
        #expect(due.map(\.offsetSeconds) == [0, 25])
        #expect(SimulatedRidePlayerCore.isWithheld(script.points[1], in: script))
        #expect(SimulatedRidePlayerCore.isWithheld(script.points[2], in: script))
        #expect(!SimulatedRidePlayerCore.isWithheld(script.points[3], in: script))
    }

    // MARK: Accelerated playback (Req 5.3)

    @Test func acceleratedPlaybackScalesDeliverySchedule() {
        let script = DemoRideScript.charlesRiverLoop
        // At 10× a point at offset 120 is delivered at playback time 12 s.
        let p120 = script.points.first { $0.offsetSeconds == 120 }!
        #expect(SimulatedRidePlayerCore.deliveryTime(for: p120, speedFactor: 10) == 12)
        #expect(SimulatedRidePlayerCore.deliveryTime(for: p120, speedFactor: 1) == 120)
    }

    @Test func acceleratedDuePointsMatchScaledElapsed() {
        let script = DemoRideScript.charlesRiverLoop
        // 3 s of playback at 10× == 30 s scripted: offsets 0,10,20,30 due.
        let due = SimulatedRidePlayerCore.duePoints(
            in: script, speedFactor: 10, elapsedPlayback: 3
        )
        #expect(due.map(\.offsetSeconds) == [0, 10, 20, 30])
    }

    @Test func playbackDurationScalesWithSpeedFactor() {
        let script = DemoRideScript.charlesRiverLoop
        let total = script.totalDuration
        #expect(SimulatedRidePlayerCore.playbackDuration(of: script, speedFactor: 1) == total)
        #expect(SimulatedRidePlayerCore.playbackDuration(of: script, speedFactor: 10) == total / 10)
    }

    @Test func speedScalingPreservesScriptedOffsets() {
        // The scripted offsets themselves never change with speed — only the
        // delivery schedule scales (so summary math stays identical).
        let script = DemoRideScript.charlesRiverLoop
        let offsets1x = SimulatedRidePlayerCore.duePoints(in: script, speedFactor: 1, elapsedPlayback: script.totalDuration).map(\.offsetSeconds)
        let offsets10x = SimulatedRidePlayerCore.duePoints(in: script, speedFactor: 10, elapsedPlayback: script.totalDuration / 10).map(\.offsetSeconds)
        #expect(offsets1x == offsets10x)
    }

    @Test func pendingPointsAreThoseNotYetDue() {
        let script = DemoRideScript.charlesRiverLoop
        let pending = SimulatedRidePlayerCore.pendingPoints(
            in: script, speedFactor: 1, elapsedPlayback: 25
        )
        // First pending non-withheld point is offset 30.
        #expect(pending.first?.offsetSeconds == 30)
    }

    // MARK: Pause segment emits nothing in its interior (Req 5.2)

    @Test func pauseSegmentInteriorIsWithheld() {
        let script = DemoRideScript.charlesRiverLoop
        guard let window = script.pauseWindow else {
            Issue.record("expected a pause window")
            return
        }
        // The `.pauseStart` boundary point is delivered (last fix before pause).
        let pauseStart = script.points.first { $0.marker == .pauseStart }!
        #expect(!SimulatedRidePlayerCore.isWithheld(pauseStart, in: script))
        // A mid-pause point (offset strictly inside the window) is withheld.
        let midPause = script.points.first {
            $0.offsetSeconds > window.lowerBound && $0.offsetSeconds < window.upperBound
        }
        #expect(midPause != nil)
        if let midPause {
            #expect(SimulatedRidePlayerCore.isWithheld(midPause, in: script))
        }
        // The `.pauseEnd` point (resume) is delivered.
        let pauseEnd = script.points.first { $0.marker == .pauseEnd }!
        #expect(!SimulatedRidePlayerCore.isWithheld(pauseEnd, in: script))
    }
}
