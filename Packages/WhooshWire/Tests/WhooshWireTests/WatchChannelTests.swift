import Testing
import Foundation
@testable import WhooshWire

/// Task 10 — channel, readiness, transport, freshness, and the elapsed-time
/// projector (the pure package pieces). Tests WE-1…6, RR-1…8, TP-1…8, SF-1…5,
/// EP-1…6 from the design acceptance criteria.
@Suite("Watch channel, readiness, transport, freshness, projector")
struct WatchChannelTests {

    // MARK: - Helpers

    private static let hello = WireHello(
        minVersion: 1, maxVersion: 1, appBuild: "100", sessionNonce: "n"
    )

    private func readyState() -> WireLinkState { .ready(peer: Self.hello) }

    private func watch(
        session: WireWorkoutSessionPhase = .running,
        healthAuthorized: Bool? = true,
        displayActive: Bool = true,
        batteryPct: Int = 80,
        hapticsArmed: Bool = true,
        anotherWorkout: Bool = false
    ) -> WireWatchState {
        WireWatchState(
            session: session,
            healthAuthorized: healthAuthorized,
            appActive: true,
            displayActive: displayActive,
            batteryPct: batteryPct,
            hapticsArmed: hapticsArmed,
            anotherWorkout: anotherWorkout
        )
    }

    // MARK: - WatchChannelEvaluator (WE-1…6)

    @Test("WE-1: setting off → unavailable regardless of the link")
    func we1() {
        let e = WatchChannelEvaluator()
        #expect(e.evaluate(linkState: readyState(), watch: watch(), settingEnabled: false) == .unavailable)
    }

    @Test("WE-2: not paired/installed/incompatible → unavailable")
    func we2() {
        let e = WatchChannelEvaluator()
        #expect(e.evaluate(linkState: .notPaired, watch: nil, settingEnabled: true) == .unavailable)
        #expect(e.evaluate(linkState: .notInstalled, watch: nil, settingEnabled: true) == .unavailable)
        #expect(e.evaluate(linkState: .incompatible, watch: nil, settingEnabled: true) == .unavailable)
    }

    @Test("WE-3: installed but not reachable → unreachable")
    func we3() {
        let e = WatchChannelEvaluator()
        #expect(e.evaluate(linkState: .installedUnreachable, watch: nil, settingEnabled: true) == .unreachable)
        #expect(e.evaluate(linkState: .reachableHelloPending, watch: nil, settingEnabled: true) == .unreachable)
    }

    @Test("WE-4: ready with no running session → foregroundOnly")
    func we4() {
        let e = WatchChannelEvaluator()
        // No watch report yet.
        #expect(e.evaluate(linkState: readyState(), watch: nil, settingEnabled: true) == .foregroundOnly)
        // Watch reporting session off.
        #expect(e.evaluate(linkState: readyState(), watch: watch(session: .none), settingEnabled: true) == .foregroundOnly)
    }

    @Test("WE-5: ready + running session + all green → ready")
    func we5() {
        let e = WatchChannelEvaluator()
        #expect(e.evaluate(linkState: readyState(), watch: watch(), settingEnabled: true) == .ready)
        // Paused session still counts as running for routing.
        #expect(e.evaluate(linkState: readyState(), watch: watch(session: .paused), settingEnabled: true) == .ready)
    }

    @Test("WE-6: ready minus one capability → degraded with the right reason")
    func we6() {
        let e = WatchChannelEvaluator()
        #expect(e.evaluate(linkState: readyState(), watch: watch(healthAuthorized: false), settingEnabled: true)
                == .degraded(reason: .healthDenied))
        #expect(e.evaluate(linkState: readyState(), watch: watch(anotherWorkout: true), settingEnabled: true)
                == .degraded(reason: .anotherWorkout))
        #expect(e.evaluate(linkState: readyState(), watch: watch(session: .failed), settingEnabled: true)
                == .degraded(reason: .sessionFailed))
        #expect(e.evaluate(linkState: readyState(), watch: watch(batteryPct: 10), settingEnabled: true)
                == .degraded(reason: .watchBatteryLow))
    }

    // MARK: - WatchReadinessEvaluator (RR-1…8)

    private func readiness(_ input: WatchReadinessEvaluator.Input) -> [WatchReadinessEvaluator.Row: WatchReadinessEvaluator.Status] {
        var map: [WatchReadinessEvaluator.Row: WatchReadinessEvaluator.Status] = [:]
        for item in WatchReadinessEvaluator().evaluate(input) { map[item.row] = item.status }
        return map
    }

    @Test("RR-1: all-green inputs pass the gating rows")
    func rr1() {
        let r = readiness(.init(linkState: readyState(), watch: watch(), armed: false, lastHapticTestFelt: true))
        #expect(r[.watchPaired] == .pass)
        #expect(r[.appInstalled] == .pass)
        #expect(r[.link] == .pass)
        #expect(r[.healthPermission] == .pass)
        #expect(r[.watchBattery] == .pass)
        #expect(r[.hapticsTest] == .pass)
    }

    @Test("RR-2: not paired / not installed surface instructions as info")
    func rr2() {
        let np = readiness(.init(linkState: .notPaired, watch: nil, armed: false, lastHapticTestFelt: nil))
        #expect(np[.watchPaired] == .info(code: "pairInstructions"))
        let ni = readiness(.init(linkState: .notInstalled, watch: nil, armed: false, lastHapticTestFelt: nil))
        #expect(ni[.appInstalled] == .info(code: "installInstructions"))
    }

    @Test("RR-3: incompatible / unreachable link warn with the right code")
    func rr3() {
        let inc = readiness(.init(linkState: .incompatible, watch: nil, armed: false, lastHapticTestFelt: nil))
        #expect(inc[.link] == .warn(code: "updateWhoosh"))
        let un = readiness(.init(linkState: .installedUnreachable, watch: nil, armed: false, lastHapticTestFelt: nil))
        #expect(un[.link] == .warn(code: "openWhooshOnWatch"))
    }

    @Test("RR-4: Health permission reflects authorized / denied / unknown")
    func rr4() {
        #expect(readiness(.init(linkState: readyState(), watch: watch(healthAuthorized: true), armed: false, lastHapticTestFelt: nil))[.healthPermission] == .pass)
        #expect(readiness(.init(linkState: readyState(), watch: watch(healthAuthorized: false), armed: false, lastHapticTestFelt: nil))[.healthPermission] == .warn(code: "healthDeniedHapticsOnScreen"))
        #expect(readiness(.init(linkState: readyState(), watch: watch(healthAuthorized: nil), armed: false, lastHapticTestFelt: nil))[.healthPermission] == .info(code: "willAskOnWatch"))
    }

    @Test("RR-5: keep-alive warns when another workout is running")
    func rr5() {
        #expect(readiness(.init(linkState: readyState(), watch: watch(anotherWorkout: true), armed: false, lastHapticTestFelt: nil))[.keepAlive] == .warn(code: "otherWorkoutRunning"))
        #expect(readiness(.init(linkState: readyState(), watch: watch(anotherWorkout: false), armed: false, lastHapticTestFelt: nil))[.keepAlive] == .pass)
    }

    @Test("RR-6: watch battery pass ≥ 40, warn 15–40, warn-strong < 15")
    func rr6() {
        #expect(readiness(.init(linkState: readyState(), watch: watch(batteryPct: 80), armed: false, lastHapticTestFelt: nil))[.watchBattery] == .pass)
        #expect(readiness(.init(linkState: readyState(), watch: watch(batteryPct: 30), armed: false, lastHapticTestFelt: nil))[.watchBattery] == .warn(code: "watchBatteryLow"))
        #expect(readiness(.init(linkState: readyState(), watch: watch(batteryPct: 10), armed: false, lastHapticTestFelt: nil))[.watchBattery] == .warn(code: "watchBatteryVeryLow"))
    }

    @Test("RR-7: haptics test reflects felt / not-felt / untested")
    func rr7() {
        #expect(readiness(.init(linkState: readyState(), watch: watch(), armed: false, lastHapticTestFelt: true))[.hapticsTest] == .pass)
        #expect(readiness(.init(linkState: readyState(), watch: watch(), armed: false, lastHapticTestFelt: false))[.hapticsTest] == .info(code: "retryHapticTest"))
        #expect(readiness(.init(linkState: readyState(), watch: watch(), armed: false, lastHapticTestFelt: nil))[.hapticsTest] == .info(code: "noTestYet"))
    }

    @Test("RR-8: audio fallback is always shown and no row blocks a ride")
    func rr8() {
        let items = WatchReadinessEvaluator().evaluate(.init(linkState: .notPaired, watch: nil, armed: false, lastHapticTestFelt: nil))
        #expect(items.contains { $0.row == .audioFallback && $0.status == .info(code: "audioFallbackAlways") })
        // No status is a "block": the enum has only pass/warn/info.
        for item in items {
            switch item.status { case .pass, .warn, .info: break }
        }
        // Start-from-watch is info until armed, pass when armed.
        #expect(readiness(.init(linkState: readyState(), watch: watch(), armed: true, lastHapticTestFelt: true))[.startFromWatch] == .pass)
    }

    // MARK: - StatusTransportPolicy (TP-1…8)

    @Test("TP-1: ready + display active + change → live and context")
    func tp1() {
        let d = StatusTransportPolicy().decide(linkState: readyState(), displayActive: true, trigger: .stateChange, msSinceLastContext: 0)
        #expect(d == .init(live: true, context: true))
    }

    @Test("TP-2: ready + active + 5 s heartbeat → live, context capped at 30 s")
    func tp2() {
        let p = StatusTransportPolicy()
        #expect(p.decide(linkState: readyState(), displayActive: true, trigger: .heartbeat, msSinceLastContext: 5_000)
                == .init(live: true, context: false))   // < 30 s since last context
        #expect(p.decide(linkState: readyState(), displayActive: true, trigger: .heartbeat, msSinceLastContext: 30_000)
                == .init(live: true, context: true))     // ≥ 30 s → refresh context
    }

    @Test("TP-3: ready + display off + change → context only")
    func tp3() {
        let d = StatusTransportPolicy().decide(linkState: readyState(), displayActive: false, trigger: .stateChange, msSinceLastContext: 0)
        #expect(d == .init(live: false, context: true))
    }

    @Test("TP-4: ready + display off + heartbeat → context only")
    func tp4() {
        let d = StatusTransportPolicy().decide(linkState: readyState(), displayActive: false, trigger: .heartbeat, msSinceLastContext: 0)
        #expect(d == .init(live: false, context: true))
    }

    @Test("TP-5: refresh request → live immediately, no context")
    func tp5() {
        let d = StatusTransportPolicy().decide(linkState: readyState(), displayActive: false, trigger: .refreshRequest, msSinceLastContext: 0)
        #expect(d == .init(live: true, context: false))
    }

    @Test("TP-6: crash phase change → live + context, exempt from the cap")
    func tp6() {
        let d = StatusTransportPolicy().decide(linkState: readyState(), displayActive: true, trigger: .crashPhaseChange, msSinceLastContext: 0)
        #expect(d == .init(live: true, context: true))
    }

    @Test("TP-7: not ready → no live send; context only on a change")
    func tp7() {
        let p = StatusTransportPolicy()
        #expect(p.decide(linkState: .installedUnreachable, displayActive: true, trigger: .stateChange, msSinceLastContext: 0)
                == .init(live: false, context: true))
        #expect(p.decide(linkState: .installedUnreachable, displayActive: true, trigger: .heartbeat, msSinceLastContext: 0)
                == .init(live: false, context: false))
    }

    @Test("TP-8: not ready + crash phase change still refreshes context")
    func tp8() {
        let d = StatusTransportPolicy().decide(linkState: .installedUnreachable, displayActive: false, trigger: .crashPhaseChange, msSinceLastContext: 0)
        #expect(d == .init(live: false, context: true))
    }

    // MARK: - StatusFreshness (SF-1…5)

    @Test("SF-1: within the stale window while active → fresh")
    func sf1() {
        #expect(StatusFreshness().level(msSinceLastMessage: 5_000, displayActive: true) == .fresh)
    }

    @Test("SF-2: past the stale window → stale")
    func sf2() {
        #expect(StatusFreshness().level(msSinceLastMessage: 15_000, displayActive: true) == .stale)
    }

    @Test("SF-3: past the silent window → silent")
    func sf3() {
        #expect(StatusFreshness().level(msSinceLastMessage: 60_000, displayActive: true) == .silent)
    }

    @Test("SF-4: display off → always fresh (no flapping wrist-down)")
    func sf4() {
        #expect(StatusFreshness().level(msSinceLastMessage: 120_000, displayActive: false) == .fresh)
    }

    @Test("SF-5: controls disabled once stale, enabled while fresh")
    func sf5() {
        let f = StatusFreshness()
        #expect(f.controlsEnabled(msSinceLastMessage: 5_000, displayActive: true) == true)
        #expect(f.controlsEnabled(msSinceLastMessage: 16_000, displayActive: true) == false)
    }

    // MARK: - ElapsedTimeProjector (EP-1…6)

    @Test("EP-1: recording advances with the monotonic delta")
    func ep1() {
        var p = ElapsedTimeProjector()
        p.apply(activeMs: 10_000, monotonicNowMs: 1_000, state: .recording)
        #expect(p.elapsedMs(monotonicNowMs: 1_000) == 10_000)
        #expect(p.elapsedMs(monotonicNowMs: 4_000) == 13_000)
    }

    @Test("EP-2: paused freezes elapsed at the anchor")
    func ep2() {
        var p = ElapsedTimeProjector()
        p.apply(activeMs: 20_000, monotonicNowMs: 5_000, state: .paused)
        #expect(p.elapsedMs(monotonicNowMs: 9_000) == 20_000)
    }

    @Test("EP-3: signalLost still advances (it is active time)")
    func ep3() {
        var p = ElapsedTimeProjector()
        p.apply(activeMs: 30_000, monotonicNowMs: 2_000, state: .signalLost)
        #expect(p.elapsedMs(monotonicNowMs: 5_000) == 33_000)
    }

    @Test("EP-4: idle / finished freeze at the anchor")
    func ep4() {
        var p = ElapsedTimeProjector()
        p.apply(activeMs: 40_000, monotonicNowMs: 0, state: .finished)
        #expect(p.elapsedMs(monotonicNowMs: 10_000) == 40_000)
    }

    @Test("EP-5: a new anchor re-bases without wall-clock subtraction")
    func ep5() {
        var p = ElapsedTimeProjector()
        p.apply(activeMs: 10_000, monotonicNowMs: 1_000, state: .recording)
        // A later status arrives with a corrected active duration.
        p.apply(activeMs: 25_000, monotonicNowMs: 20_000, state: .recording)
        #expect(p.elapsedMs(monotonicNowMs: 20_000) == 25_000)
        #expect(p.elapsedMs(monotonicNowMs: 22_000) == 27_000)
    }

    @Test("EP-6: a monotonic reading before the anchor never goes negative")
    func ep6() {
        var p = ElapsedTimeProjector()
        p.apply(activeMs: 5_000, monotonicNowMs: 10_000, state: .recording)
        #expect(p.elapsedMs(monotonicNowMs: 9_000) == 5_000)
    }
}
