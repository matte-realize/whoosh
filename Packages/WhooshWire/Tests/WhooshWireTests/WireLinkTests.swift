import Testing
import Foundation
@testable import WhooshWire

/// Task 12 — the `WireLinkStateMachine` 17-row table (LS-1…17) and the
/// `LoopbackWireLinkPair` fault behaviour (LB-1…8).
@Suite("WireLink state machine and loopback pair")
struct WireLinkTests {

    private static func hello(_ nonce: String = "peer", min: Int = 1, max: Int = 1) -> WireHello {
        WireHello(minVersion: min, maxVersion: max, appBuild: "1", sessionNonce: nonce)
    }

    private func phoneMachine(state: WireLinkState = .activating) -> WireLinkStateMachine {
        WireLinkStateMachine(side: .phone, localHello: Self.hello("local"), state: state)
    }
    private func watchMachine(state: WireLinkState = .activating) -> WireLinkStateMachine {
        WireLinkStateMachine(side: .watch, localHello: Self.hello("local"), state: state)
    }

    // MARK: - LS state machine

    @Test("LS-1: unsupported at start reports and no-ops sends")
    func ls1() {
        var m = WireLinkStateMachine(side: .phone, localHello: Self.hello(), state: .unsupported)
        #expect(m.apply(.reachability(true)).isEmpty)      // row 17: no-op
        #expect(m.state == .unsupported)
    }

    @Test("LS-2: activating is the initial state (session activates)")
    func ls2() {
        let m = phoneMachine()
        #expect(m.state == .activating)
    }

    @Test("LS-3: phone activated not paired → notPaired")
    func ls3() {
        var m = phoneMachine()
        let fx = m.apply(.activated(paired: false, installed: false))
        #expect(m.state == .notPaired)
        #expect(fx == [.report])
    }

    @Test("LS-4: paired not installed (phone) / companion missing (watch) → notInstalled")
    func ls4() {
        var p = phoneMachine()
        #expect(p.apply(.activated(paired: true, installed: false)) == [.report])
        #expect(p.state == .notInstalled)

        var w = watchMachine()
        #expect(w.apply(.activated(paired: false, installed: false)) == [.report])
        #expect(w.state == .notInstalled)
    }

    @Test("LS-5: phone deactivated → inactive, re-activate")
    func ls5() {
        var m = phoneMachine(state: .ready(peer: Self.hello()))
        #expect(m.apply(.deactivated) == [.reactivate])
        #expect(m.state == .inactive)
    }

    @Test("LS-6: activated installed but not reachable → installedUnreachable")
    func ls6() {
        var m = phoneMachine()
        #expect(m.apply(.activated(paired: true, installed: true)) == [.startStalenessTimers])
        #expect(m.state == .installedUnreachable)
    }

    @Test("LS-7: reachability true → send hello, pending")
    func ls7() {
        var m = phoneMachine(state: .installedUnreachable)
        #expect(m.apply(.reachability(true)) == [.sendHello])
        #expect(m.state == .reachableHelloPending)
    }

    @Test("LS-8: hello received with overlapping versions → ready + status")
    func ls8() {
        var m = phoneMachine(state: .reachableHelloPending)
        let fx = m.apply(.helloReceived(Self.hello("peerA")))
        #expect(m.isReady)
        #expect(fx == [.negotiate, .sendFullStatus, .resendCrashCountdown])
        // Watch side sends watchState instead.
        var w = watchMachine(state: .reachableHelloPending)
        #expect(w.apply(.helloReceived(Self.hello("peerB"))).contains(.sendWatchState))
    }

    @Test("LS-9: hello received with no version overlap → incompatible")
    func ls9() {
        var m = phoneMachine(state: .reachableHelloPending)
        let fx = m.apply(.helloReceived(Self.hello("peer", min: 5, max: 6)))
        #expect(m.state == .incompatible)
        #expect(fx == [.reportIncompatible])
    }

    @Test("LS-10: hello timeout with tries left → resend hello, stay pending")
    func ls10() {
        var m = phoneMachine(state: .installedUnreachable)
        m.apply(.reachability(true))              // tries = 1
        #expect(m.apply(.helloTimeout) == [.sendHello])
        #expect(m.state == .reachableHelloPending)
    }

    @Test("LS-11: hello timeout with tries exhausted → installedUnreachable, not responding")
    func ls11() {
        var m = phoneMachine(state: .installedUnreachable)
        m.apply(.reachability(true))              // tries = 1
        m.apply(.helloTimeout)                    // tries = 2
        m.apply(.helloTimeout)                    // tries = 3
        let fx = m.apply(.helloTimeout)           // exhausted
        #expect(m.state == .installedUnreachable)
        #expect(fx == [.markNotResponding, .startStalenessTimers])
    }

    @Test("LS-12: ready → reachability false → installedUnreachable, announce")
    func ls12() {
        var m = phoneMachine(state: .ready(peer: Self.hello()))
        let fx = m.apply(.reachability(false))
        #expect(m.state == .installedUnreachable)
        #expect(fx == [.startStalenessTimers, .announceAfterDelay])
    }

    @Test("LS-13: ready + peer relaunched (new nonce) → reset, resend")
    func ls13() {
        var m = phoneMachine(state: .reachableHelloPending)
        m.apply(.helloReceived(Self.hello("nonceA")))   // peerNonce = nonceA
        let fx = m.apply(.peerRelaunched(nonce: "nonceB"))
        #expect(fx == [.resetDedupe, .resendStatus, .resendCrashCountdown])
        #expect(m.isReady)
        // Same nonce is a no-op.
        #expect(m.apply(.peerRelaunched(nonce: "nonceB")).isEmpty)
    }

    @Test("LS-14: notPaired/notInstalled becomes installed → installedUnreachable")
    func ls14() {
        var m = phoneMachine(state: .notInstalled)
        #expect(m.apply(.watchStateChanged(paired: true, installed: true)) == [.startStalenessTimers])
        #expect(m.state == .installedUnreachable)
    }

    @Test("LS-15: any state loses pairing/installation → notPaired/notInstalled, unavailable")
    func ls15() {
        var p = phoneMachine(state: .ready(peer: Self.hello()))
        #expect(p.apply(.watchStateChanged(paired: false, installed: true)) == [.channelUnavailable])
        #expect(p.state == .notPaired)

        var w = watchMachine(state: .ready(peer: Self.hello()))
        #expect(w.apply(.watchStateChanged(paired: true, installed: false)) == [.channelUnavailable])
        #expect(w.state == .notInstalled)
    }

    @Test("LS-16: incompatible then an overlapping hello → ready")
    func ls16() {
        var m = phoneMachine(state: .incompatible)
        let fx = m.apply(.helloReceived(Self.hello("peer", min: 1, max: 1)))
        #expect(m.isReady)
        #expect(fx.contains(.sendFullStatus))
        // A still-incompatible hello stays incompatible (no-op).
        var m2 = phoneMachine(state: .incompatible)
        #expect(m2.apply(.helloReceived(Self.hello("peer", min: 9, max: 9))).isEmpty)
        #expect(m2.state == .incompatible)
    }

    @Test("LS-17: undefined (state, event) pairs are a no-op")
    func ls17() {
        var m = phoneMachine(state: .ready(peer: Self.hello()))
        let before = m.state
        #expect(m.apply(.helloTimeout).isEmpty)   // no hello pending
        #expect(m.state == before)
    }

    // MARK: - LoopbackWireLinkPair (LB-1…8)

    private func envelope(id: String = "m1", seq: Int = 1) throws -> WireEnvelope {
        try WireCodec.encode(WireSamples.hello, id: id, seq: seq, sentAt: 0)
    }

    @Test("LB-1: a live send is delivered to the peer's handler")
    func lb1() async throws {
        let pair = LoopbackWireLinkPair()
        actor Box { var received: [String] = []; func add(_ s: String) { received.append(s) } }
        let box = Box()
        await pair.watch.onLiveMessage { env in Task { await box.add(env.id) }; return nil }
        let result = await pair.phone.send(try envelope(id: "hello-1"))
        #expect(result == .delivered(reply: nil))
        // allow the detached task to run
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await box.received == ["hello-1"])
    }

    @Test("LB-2: the peer's reply comes back on the send")
    func lb2() async throws {
        let pair = LoopbackWireLinkPair()
        let replyEnv = try envelope(id: "reply-1")
        await pair.watch.onLiveMessage { _ in replyEnv }
        let result = await pair.phone.send(try envelope(id: "cmd-1"))
        #expect(result == .delivered(reply: replyEnv))
    }

    @Test("LB-3: unreachable window → send reports unreachable, no delivery")
    func lb3() async throws {
        let pair = LoopbackWireLinkPair()
        actor Counter { var n = 0; func inc() { n += 1 } }
        let c = Counter()
        await pair.watch.onLiveMessage { _ in Task { await c.inc() }; return nil }
        await pair.phone.setFaults(.init(unreachable: true))
        #expect(await pair.phone.send(try envelope()) == .unreachable)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await c.n == 0)
    }

    @Test("LB-4: drop fault → send reports unreachable")
    func lb4() async throws {
        let pair = LoopbackWireLinkPair()
        await pair.watch.onLiveMessage { _ in nil }
        await pair.phone.setFaults(.init(drop: true))
        #expect(await pair.phone.send(try envelope()) == .unreachable)
    }

    @Test("LB-5: duplicate fault → the peer receives the same id twice")
    func lb5() async throws {
        let pair = LoopbackWireLinkPair()
        actor IDs { var all: [String] = []; func add(_ s: String) { all.append(s) } }
        let ids = IDs()
        await pair.watch.onLiveMessage { env in Task { await ids.add(env.id) }; return nil }
        await pair.phone.setFaults(.init(duplicate: true))
        _ = await pair.phone.send(try envelope(id: "dup"))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await ids.all == ["dup", "dup"])
    }

    @Test("LB-6: dropReply fault → delivered but reply is nil")
    func lb6() async throws {
        let pair = LoopbackWireLinkPair()
        await pair.watch.onLiveMessage { _ in try? WireCodec.encode(WireSamples.hello, id: "r", seq: 1, sentAt: 0) }
        await pair.phone.setFaults(.init(dropReply: true))
        #expect(await pair.phone.send(try envelope()) == .delivered(reply: nil))
    }

    @Test("LB-7: context update is delivered to the peer's context handler")
    func lb7() async throws {
        let pair = LoopbackWireLinkPair()
        actor Box { var last: String?; func set(_ s: String) { last = s } }
        let box = Box()
        await pair.watch.onContext { env in Task { await box.set(env.id) } }
        #expect(await pair.phone.updateContext(try envelope(id: "ctx-1")) == .delivered(reply: nil))
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await box.last == "ctx-1")
    }

    @Test("LB-8: queue transfer reaches the peer's queue handler and reports queued")
    func lb8() async throws {
        let pair = LoopbackWireLinkPair()
        actor Box { var last: String?; func set(_ s: String) { last = s } }
        let box = Box()
        await pair.watch.onQueued { env in Task { await box.set(env.id) } }
        #expect(await pair.phone.transfer(try envelope(id: "q-1")) == .queued)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await box.last == "q-1")
    }
}
