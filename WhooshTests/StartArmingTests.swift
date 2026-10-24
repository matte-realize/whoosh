import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Tests for the pure `StartArming` state machine (watch-companion task 7,
/// design "`StartArming`"; Requirement 9.1–9.3). One `@Test` per table row
/// (SA-1 … SA-12), with a controllable `now`.
struct StartArmingTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // SA-1: Ready tapped with all preconditions passing arms until now + 5 min.
    @Test func sa1_readyArms() {
        let m = StartArming()
        let (next, effect) = m.apply(.readyTapped(.allPass), at: t0)
        let expected = t0.addingTimeInterval(300)
        #expect(next.state == .armed(deadline: expected))
        #expect(next.isArmed)
        #expect(effect == .didArm(deadline: expected))
    }

    // SA-2: Ready tapped with a failing precondition stays disarmed and reports
    // the sorted failing rows.
    @Test func sa2_readyFailsPreconditions() {
        let pre = StartArming.Preconditions(locationAuthorized: false, cameraReady: false)
        let m = StartArming()
        let (next, effect) = m.apply(.readyTapped(pre), at: t0)
        #expect(next.state == .disarmed)
        #expect(effect == .showFailingRows([.camera, .location]))
    }

    // SA-3: Cancel while armed disarms and publishes ready.
    @Test func sa3_cancelDisarms() {
        let armed = StartArming(state: .armed(deadline: t0.addingTimeInterval(300)))
        let (next, effect) = armed.apply(.cancelTapped, at: t0)
        #expect(next.state == .disarmed)
        #expect(effect == .didDisarmReady)
    }

    // SA-4: expiry while armed disarms with a notice; before the deadline it is
    // a no-op.
    @Test func sa4_expiry() {
        let deadline = t0.addingTimeInterval(300)
        let armed = StartArming(state: .armed(deadline: deadline))

        let (stillArmed, noEffect) = armed.apply(.expiryCheck, at: t0.addingTimeInterval(299))
        #expect(stillArmed.state == .armed(deadline: deadline))
        #expect(noEffect == .none)

        let (disarmed, effect) = armed.apply(.expiryCheck, at: deadline)
        #expect(disarmed.state == .disarmed)
        #expect(effect == .didDisarmWithNotice(reason: nil))
    }

    // SA-5: app resigning active while armed disarms with a notice.
    @Test func sa5_resignActive() {
        let armed = StartArming(state: .armed(deadline: t0.addingTimeInterval(300)))
        let (next, effect) = armed.apply(.resignedActive, at: t0)
        #expect(next.state == .disarmed)
        #expect(effect == .didDisarmWithNotice(reason: .appNotActive))
    }

    // SA-6: a crash event or location-authorization loss while armed disarms.
    @Test func sa6_crashAndAuthLossDisarm() {
        let armed = StartArming(state: .armed(deadline: t0.addingTimeInterval(300)))

        let (afterCrash, crashEffect) = armed.apply(.crashBecameActive, at: t0)
        #expect(afterCrash.state == .disarmed)
        #expect(crashEffect == .didDisarmWithNotice(reason: .crashActive))

        let (afterAuth, authEffect) = armed.apply(.locationAuthorizationLost, at: t0)
        #expect(afterAuth.state == .disarmed)
        #expect(authEffect == .didDisarmWithNotice(reason: .location))
    }

    // SA-7: requestStart accepted while armed → starting, runs the start path.
    @Test func sa7_requestStartRuns() {
        let armed = StartArming(state: .armed(deadline: t0.addingTimeInterval(300)))
        let (next, effect) = armed.apply(.requestStartAccepted(commandId: "s1"), at: t0)
        #expect(next.state == .starting(commandId: "s1"))
        #expect(effect == .runStartPath(commandId: "s1"))
    }

    // SA-8: ride becomes active while starting → consumed, publishes status.
    @Test func sa8_startingToConsumed() {
        let starting = StartArming(state: .starting(commandId: "s1"))
        let (next, effect) = starting.apply(.rideBecameActive, at: t0)
        #expect(next.state == .consumed)
        #expect(effect == .publishRideActive)
    }

    // SA-9: start fails while starting → disarmed, reports the typed reason.
    @Test func sa9_startFails() {
        let starting = StartArming(state: .starting(commandId: "s1"))
        let (next, effect) = starting.apply(.startFailed(reason: .camera), at: t0)
        #expect(next.state == .disarmed)
        #expect(effect == .reportStartFailure(.camera))
    }

    // SA-10: phone Start tapped while armed consumes the armed window.
    @Test func sa10_phoneStartConsumes() {
        let armed = StartArming(state: .armed(deadline: t0.addingTimeInterval(300)))
        let (next, effect) = armed.apply(.phoneStartTapped, at: t0)
        #expect(next.state == .consumed)
        #expect(effect == .normalStart)
    }

    // SA-11: ride ended / reset from consumed returns to disarmed.
    @Test func sa11_resetDisarms() {
        let consumed = StartArming(state: .consumed)
        let (next, effect) = consumed.apply(.rideEndedOrReset, at: t0)
        #expect(next.state == .disarmed)
        #expect(effect == .none)
    }

    // SA-12: an undefined (state, event) pair is a no-op (e.g. requestStart
    // while disarmed, or Cancel while starting).
    @Test func sa12_undefinedIsNoop() {
        let disarmed = StartArming()
        let (same1, e1) = disarmed.apply(.requestStartAccepted(commandId: "s1"), at: t0)
        #expect(same1.state == .disarmed)
        #expect(e1 == .none)

        let starting = StartArming(state: .starting(commandId: "s1"))
        let (same2, e2) = starting.apply(.cancelTapped, at: t0)
        #expect(same2.state == .starting(commandId: "s1"))
        #expect(e2 == .none)
    }

    // A watch can never arm: only the phone's readyTapped produces .armed.
    // (Requirement 9.2 — covered structurally: the only arming event is
    // readyTapped, which the phone issues.)
    @Test func onlyReadyTappedArms() {
        let m = StartArming()
        // None of the non-ready events from disarmed produce an armed state.
        let events: [StartArming.Event] = [
            .cancelTapped, .expiryCheck, .resignedActive, .crashBecameActive,
            .locationAuthorizationLost, .requestStartAccepted(commandId: "s1"),
            .rideBecameActive, .startFailed(reason: .camera), .phoneStartTapped,
            .rideEndedOrReset
        ]
        for event in events {
            let (next, _) = m.apply(event, at: t0)
            #expect(!next.isArmed)
        }
    }
}
