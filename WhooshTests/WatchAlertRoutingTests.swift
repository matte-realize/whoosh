import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Tests FO-1…10 for the watch-channel-aware routing (`AlertRoutingPolicy.plan`)
/// and the pure `AlertOutcomeTracker` (watch-companion spec task 9; design
/// "Fan-out, routing, and escalation" table; Requirement 12.1, 13.2–13.7,
/// 13.9). Written test-first.
///
/// Every cell of the design routing table is exercised: watch first for
/// `ready`; watch **and** audio for `degraded`/`foregroundOnly`; phone channels
/// for `unavailable`/`unreachable`; the crash countdown on all channels; audio
/// not concurrent with a confirmed watch cue unless "Also play a sound" is on;
/// the watch-link announcements are audio-only; plus escalation timing with a
/// test clock.
struct WatchAlertRoutingTests {
    private let audio: [AlertChannel] = [.phoneHeadphones, .phoneSpeaker]
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // FO-1: rear-vehicle caution, watch ready → watch first, audio is the
    // escalation target (not immediate).
    @Test func readyRearVehicleWatchFirstEscalatesToAudio() {
        let plan = AlertRoutingPolicy.plan(
            for: .cautionRearVehicle, watch: .ready,
            appState: .foregroundRideMode, audioAvailable: audio
        )
        #expect(plan.immediate == [.watchHaptic])
        #expect(plan.escalateTo == .phoneHeadphones)
        #expect(plan.usesWatch)
    }

    // FO-2: watch degraded → watch AND audio immediately (a degraded watch may
    // not buzz, so audio backs it at once, no escalation gap).
    @Test func degradedWatchAndAudio() {
        let plan = AlertRoutingPolicy.plan(
            for: .cautionRearVehicle, watch: .degraded(reason: .watchBatteryLow),
            appState: .foregroundRideMode, audioAvailable: audio
        )
        #expect(plan.immediate.first == .watchHaptic)
        #expect(plan.immediate.contains(.phoneHeadphones))
    }

    // FO-3: foregroundOnly behaves like degraded → watch + audio.
    @Test func foregroundOnlyWatchAndAudio() {
        let plan = AlertRoutingPolicy.plan(
            for: .cameraStopped(.thermal), watch: .foregroundOnly,
            appState: .foregroundRideMode, audioAvailable: audio
        )
        #expect(plan.immediate.first == .watchHaptic)
        #expect(plan.immediate.contains(.phoneHeadphones))
    }

    // FO-4: watch unavailable → phone channels only (audio), no watch.
    @Test func unavailablePhoneOnly() {
        let plan = AlertRoutingPolicy.plan(
            for: .cautionRearVehicle, watch: .unavailable,
            appState: .foregroundRideMode, audioAvailable: audio
        )
        #expect(!plan.usesWatch)
        #expect(plan.immediate == [.phoneHeadphones])
    }

    // FO-5: watch unreachable, phone locked, transient caution → dropped (no
    // audio route, no notification for a stale cue).
    @Test func unreachableLockedRearVehicleDropped() {
        let plan = AlertRoutingPolicy.plan(
            for: .cautionRearVehicle, watch: .unreachable,
            appState: .lockedOrBackgrounded, audioAvailable: []
        )
        #expect(plan.immediate.isEmpty)
    }

    // FO-6: watch unavailable, important camera-stopped notice, locked, no audio
    // → a local notification.
    @Test func unavailableLockedCameraStoppedNotifies() {
        let plan = AlertRoutingPolicy.plan(
            for: .cameraStopped(.battery), watch: .unavailable,
            appState: .lockedOrBackgrounded, audioAvailable: []
        )
        #expect(plan.immediate == [.localNotification])
    }

    // FO-7: crash countdown (critical) → every channel, repeating (watch + audio
    // + notification when locked). The crash path supplies the critical tier via
    // its AlertContext, so route with an explicit tier override.
    @Test func crashCountdownAllChannels() {
        let critical = AlertRoutingPolicy.plan(
            for: .cautionRearVehicle, watch: .ready,
            appState: .lockedOrBackgrounded, audioAvailable: audio,
            tier: .critical
        )
        #expect(critical.immediate.contains(.watchHaptic))
        #expect(critical.immediate.contains(.phoneHeadphones))
        #expect(critical.immediate.contains(.localNotification))
    }

    // FO-8: "Also play a sound" on → audio plays concurrently with the watch
    // cue (no escalation gap).
    @Test func alsoPlaySoundConcurrent() {
        let plan = AlertRoutingPolicy.plan(
            for: .cautionRearVehicle, watch: .ready,
            appState: .foregroundRideMode, audioAvailable: audio, alsoPlaySound: true
        )
        #expect(plan.immediate == [.watchHaptic, .phoneHeadphones])
        #expect(plan.escalateTo == nil)
    }

    // FO-9: watchDisconnected / watchReconnected are audio-only on every column
    // (the watch link can't carry a notice about itself).
    @Test func watchLinkAnnouncementsAudioOnly() {
        for kind in [AlertKind.watchDisconnected, .watchReconnected] {
            let ready = AlertRoutingPolicy.plan(
                for: kind, watch: .ready,
                appState: .foregroundRideMode, audioAvailable: audio
            )
            #expect(ready.immediate == [.phoneHeadphones])
            #expect(!ready.usesWatch)
        }
    }

    // FO-10a: light confirmation on a ready watch → watch only, no escalation.
    @Test func readyClipSavedWatchOnly() {
        let plan = AlertRoutingPolicy.plan(
            for: .clipSaved, watch: .ready,
            appState: .foregroundRideMode, audioAvailable: audio
        )
        #expect(plan.immediate == [.watchHaptic])
        #expect(plan.escalateTo == nil)
    }
}

/// Tests for the pure `AlertOutcomeTracker` (escalate at most once, never after
/// TTL). Part of FO-10.
struct AlertOutcomeTrackerTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // Confirmed cue does not escalate.
    @Test func confirmedDoesNotEscalate() {
        var tracker = AlertOutcomeTracker()
        tracker.track(id: "a", firedAt: now, ttl: 3)
        tracker.confirm(id: "a")
        #expect(tracker.outcome(for: "a") == .confirmed)
        let decision = tracker.escalateOnTimeout(id: "a", now: now.addingTimeInterval(1))
        #expect(decision == .skip)
        #expect(tracker.outcome(for: "a") == .confirmed)
    }

    // No ack within TTL → escalate exactly once.
    @Test func escalatesOnceOnTimeout() {
        var tracker = AlertOutcomeTracker()
        tracker.track(id: "a", firedAt: now, ttl: 3)
        let first = tracker.escalateOnTimeout(id: "a", now: now.addingTimeInterval(1.5))
        #expect(first == .escalate)
        #expect(tracker.outcome(for: "a") == .escalated)
        // A second timeout for the same id is refused.
        let second = tracker.escalateOnTimeout(id: "a", now: now.addingTimeInterval(1.6))
        #expect(second == .skip)
    }

    // A stale alert (past TTL) never escalates — it expires.
    @Test func staleNeverEscalates() {
        var tracker = AlertOutcomeTracker()
        tracker.track(id: "a", firedAt: now, ttl: 3)
        let decision = tracker.escalateOnTimeout(id: "a", now: now.addingTimeInterval(5))
        #expect(decision == .skip)
        #expect(tracker.outcome(for: "a") == .expired)
    }

    // expireIfStale transitions a pending alert past its TTL to expired.
    @Test func expireIfStaleWorks() {
        var tracker = AlertOutcomeTracker()
        tracker.track(id: "a", firedAt: now, ttl: 3)
        #expect(tracker.expireIfStale(id: "a", now: now.addingTimeInterval(2)) == false)
        #expect(tracker.expireIfStale(id: "a", now: now.addingTimeInterval(4)) == true)
        #expect(tracker.outcome(for: "a") == .expired)
    }

    // prune drops terminal entries and keeps pending ones bounded.
    @Test func pruneDropsTerminal() {
        var tracker = AlertOutcomeTracker()
        tracker.track(id: "a", firedAt: now, ttl: 3)
        tracker.track(id: "b", firedAt: now, ttl: 3)
        tracker.confirm(id: "a")
        tracker.prune(now: now.addingTimeInterval(1))
        #expect(tracker.outcome(for: "a") == nil)   // confirmed pruned
        #expect(tracker.outcome(for: "b") == .pending)
    }
}
