import Foundation
import Testing
@testable import Whoosh

/// One screen going away must not let the phone sleep while another screen
/// (e.g. the ride under a cancelled crash countdown) still needs it awake.
@MainActor
struct KeepAwakeTests {
    private final class IdleTimerSpy {
        var disabled = false
    }

    private func make() -> (KeepAwake, IdleTimerSpy) {
        let spy = IdleTimerSpy()
        return (KeepAwake(apply: { spy.disabled = $0 }), spy)
    }

    @Test func acquiringKeepsThePhoneAwake() {
        let (keepAwake, spy) = make()
        keepAwake.acquire(.ride)
        #expect(spy.disabled)
    }

    @Test func releasingTheLastHolderLetsThePhoneSleep() {
        let (keepAwake, spy) = make()
        keepAwake.acquire(.ride)
        keepAwake.release(.ride)
        #expect(!spy.disabled)
    }

    @Test func cancelledCountdownOverARideKeepsTheRideAwake() {
        let (keepAwake, spy) = make()
        keepAwake.acquire(.ride)
        keepAwake.acquire(.crashCountdown)
        keepAwake.release(.crashCountdown)
        #expect(spy.disabled)
        keepAwake.release(.ride)
        #expect(!spy.disabled)
    }

    @Test func releasingAnUnheldReasonChangesNothing() {
        let (keepAwake, spy) = make()
        keepAwake.acquire(.ride)
        keepAwake.release(.crashCountdown)
        #expect(spy.disabled)
    }
}
