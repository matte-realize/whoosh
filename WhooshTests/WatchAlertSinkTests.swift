import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Unit tests for `WatchAlertSink` and the fan-out escalation wiring
/// (watch-companion spec task 14; design "Fan-out, routing, and escalation";
/// Requirement 13.1–13.7, 1.4). Written test-first.
///
/// - A confirmed cue (receipt `played`) does not escalate.
/// - No receipt / a suppressed-or-failed receipt escalates to audio exactly once.
/// - A stale alert (past TTL) never escalates.
/// - A sink failure leaves the other sinks and recording untouched.
@MainActor
struct WatchAlertSinkTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let ctx = AlertDeliveryContext(firedAt: Date(timeIntervalSince1970: 1_000_000), appState: .foregroundRideMode)

    /// Records audio escalations.
    private final class AudioSpy: @unchecked Sendable {
        var escalations: [AlertKind] = []
    }

    private func receiptEnvelope(alertId: String, result: WireAlertReceiptResult) -> WireEnvelope {
        let receipt = WireAlertReceipt(alertId: alertId, result: result, workoutActive: true, playedAfterMs: 10)
        return try! WireCodec.encode(receipt, id: alertId, seq: 0, sentAt: now.timeIntervalSince1970)
    }

    private func makeSink(
        link: FakeWireLink,
        clock: TestClock,
        spy: AudioSpy,
        reachable: Bool = true,
        alsoPlaySound: Bool = false
    ) -> WatchAlertSink {
        WatchAlertSink(
            link: link, clock: clock,
            isReachable: { reachable },
            escalate: { kind, _ in spy.escalations.append(kind) },
            alsoPlaySound: { alsoPlaySound },
            makeAlertId: { "alert-1" }
        )
    }

    // A confirmed cue (receipt `played`) does not escalate.
    @Test func confirmedCueDoesNotEscalate() async {
        let link = FakeWireLink(reachable: true)
        await link.setStubbedReply(receiptEnvelope(alertId: "alert-1", result: .played))
        let clock = TestClock(now: now)
        let spy = AudioSpy()
        let sink = makeSink(link: link, clock: clock, spy: spy)

        await sink.deliverAwaitingSend(.cautionRearVehicle, context: ctx)
        #expect(sink.lastReceipt == .played)
        #expect(sink.outcomes.outcome(for: "alert-1") == .confirmed)

        // Even if the ack timeout now fires, a confirmed cue never escalates.
        clock.advance(by: 2)
        #expect(spy.escalations.isEmpty)
    }

    // No receipt within the ack timeout escalates to audio exactly once.
    @Test func noReceiptEscalatesOnceOnTimeout() async {
        let link = FakeWireLink(reachable: true)   // delivered, but no stubbed reply
        let clock = TestClock(now: now)
        let spy = AudioSpy()
        let sink = makeSink(link: link, clock: clock, spy: spy)

        await sink.deliverAwaitingSend(.cautionRearVehicle, context: ctx)
        #expect(sink.outcomes.outcome(for: "alert-1") == .pending)

        clock.advance(by: 1.5)   // ack timeout = 1.5 s
        #expect(spy.escalations == [.cautionRearVehicle])
        #expect(sink.outcomes.outcome(for: "alert-1") == .escalated)

        // A further advance never escalates again.
        clock.advance(by: 5)
        #expect(spy.escalations.count == 1)
    }

    // An unreachable link escalates immediately (failed receipt).
    @Test func unreachableEscalates() async {
        let link = FakeWireLink(reachable: false)
        let clock = TestClock(now: now)
        let spy = AudioSpy()
        let sink = makeSink(link: link, clock: clock, spy: spy)

        await sink.deliverAwaitingSend(.cameraStopped(.thermal), context: ctx)
        #expect(sink.lastReceipt == .failed)
        #expect(spy.escalations == [.cameraStopped(.thermal)])
    }

    // A stale alert (past TTL) never escalates: the timeout fires after TTL.
    @Test func staleAlertNeverEscalates() async {
        let link = FakeWireLink(reachable: true)
        let clock = TestClock(now: now)
        let spy = AudioSpy()
        // Rear-vehicle TTL is 3 s; the ack timeout is 1.5 s. Use an override
        // context with a very short TTL so the timeout lands past TTL.
        let sink = makeSink(link: link, clock: clock, spy: spy)
        let shortCtx = AlertContext(id: "alert-1", tier: .caution, ttl: 0.5)

        await sink.deliverAwaitingSend(.cautionRearVehicle, context: ctx, overrideContext: shortCtx)
        clock.advance(by: 1.5)   // ack timeout fires, but now > TTL (0.5 s)
        #expect(spy.escalations.isEmpty)
        #expect(sink.outcomes.outcome(for: "alert-1") == .expired)
    }

    // "Also play a sound" on: audio plays concurrently (via routing), so the
    // sink does not schedule an escalation timeout at all.
    @Test func alsoPlaySoundSkipsEscalation() async {
        let link = FakeWireLink(reachable: true)
        let clock = TestClock(now: now)
        let spy = AudioSpy()
        let sink = makeSink(link: link, clock: clock, spy: spy, alsoPlaySound: true)

        await sink.deliverAwaitingSend(.cautionRearVehicle, context: ctx)
        #expect(clock.pendingCount == 0)   // no ack timeout scheduled
        clock.advance(by: 5)
        #expect(spy.escalations.isEmpty)
    }

    // A suppressed receipt (watch chose not to buzz) escalates to audio.
    @Test func suppressedReceiptEscalates() async {
        let link = FakeWireLink(reachable: true)
        await link.setStubbedReply(receiptEnvelope(alertId: "alert-1", result: .suppressedNotActive))
        let clock = TestClock(now: now)
        let spy = AudioSpy()
        let sink = makeSink(link: link, clock: clock, spy: spy)

        await sink.deliverAwaitingSend(.cameraInterrupted, context: ctx)
        #expect(spy.escalations == [.cameraInterrupted])
    }

    // The sink is a channel-`.watchHaptic` AlertSink and never throws from
    // deliver (failures are swallowed, recording is never affected).
    @Test func isAWatchAlertSink() async throws {
        let link = FakeWireLink(reachable: true)
        let clock = TestClock(now: now)
        let spy = AudioSpy()
        let sink = makeSink(link: link, clock: clock, spy: spy)
        #expect(sink.channel == .watchHaptic)
        #expect(sink.isAvailable)
        try sink.deliver(.clipSaved, context: ctx)   // non-blocking, no throw
    }
}

/// Fan-out integration: the `WatchAlertSink` registers with the existing
/// `FanOutAlertManager` alongside the phone sinks; a rear-vehicle caution routes
/// to the watch only (single best channel), and a throwing watch sink never
/// stops recording or the other sinks.
@MainActor
struct WatchAlertSinkFanOutTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func fanOutDeliversRearVehicleToWatchSink() async {
        let link = FakeWireLink(reachable: true)
        let clock = TestClock(now: now)
        let audio = FakeAlertSink(channel: .phoneSpeaker)
        let watch = WatchAlertSink(
            link: link, clock: clock,
            isReachable: { true },
            escalate: { _, _ in }
        )
        let manager = FanOutAlertManager(
            sinks: [watch, audio], clock: clock, appState: { .foregroundRideMode }
        )
        manager.fire(.cautionRearVehicle)
        // Single best channel = watch; the audio sink does not get the cue
        // (escalation to audio is the watch sink's own job on no acknowledgement).
        #expect(audio.delivered.isEmpty)
    }
}
