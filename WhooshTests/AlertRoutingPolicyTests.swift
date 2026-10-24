import Foundation
import Testing
@testable import Whoosh

/// Tests AR-1…8 for the pure `AlertRoutingPolicy` (rear-camera task 10,
/// Requirements 13.3, 13.4, design "Eyes-free surfaces: Routing table").
/// Written test-first.
///
/// The policy maps (alert kind × available channels × app context) to an
/// **ordered** list of `AlertChannel`s, applying per-kind cooldowns. The order
/// mirrors the design routing table: watch haptic first, then phone audio, then
/// phone haptic, with local notification used when the phone is locked /
/// backgrounded. A stale rear-vehicle caution is dropped when locked.
struct AlertRoutingPolicyTests {
    private let tuning = RideCameraTuning()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func context(
        available: Set<AlertChannel>,
        appState: AppAlertState = .foregroundRideMode,
        lastDeliveredByKind: [String: Date] = [:]
    ) -> AlertRoutingPolicy.Context {
        AlertRoutingPolicy.Context(
            now: now,
            availableChannels: available,
            appState: appState,
            lastDeliveredByKind: lastDeliveredByKind
        )
    }

    // AR-1: rear-vehicle caution with the watch reachable ⇒ watch haptic first.
    @Test func rearVehicleWatchFirst() {
        let sinks = AlertRoutingPolicy.route(
            .cautionRearVehicle,
            context: context(available: [.watchHaptic, .phoneSpeaker]),
            tuning: tuning
        )
        #expect(sinks.first == .watchHaptic)
    }

    // AR-2: rear-vehicle caution, no watch but headphones ⇒ audio blip on headphones.
    @Test func rearVehicleHeadphonesWhenNoWatch() {
        let sinks = AlertRoutingPolicy.route(
            .cautionRearVehicle,
            context: context(available: [.phoneHeadphones, .phoneSpeaker]),
            tuning: tuning
        )
        #expect(sinks == [.phoneHeadphones])
    }

    // AR-3: rear-vehicle caution, speaker only ⇒ speaker blip (wind-limited).
    @Test func rearVehicleSpeakerOnly() {
        let sinks = AlertRoutingPolicy.route(
            .cautionRearVehicle,
            context: context(available: [.phoneSpeaker]),
            tuning: tuning
        )
        #expect(sinks == [.phoneSpeaker])
    }

    // AR-4: rear-vehicle caution is DROPPED (stale) when the phone is locked /
    // backgrounded and no watch is reachable.
    @Test func rearVehicleDroppedWhenLocked() {
        let sinks = AlertRoutingPolicy.route(
            .cautionRearVehicle,
            context: context(available: [.localNotification], appState: .lockedOrBackgrounded),
            tuning: tuning
        )
        #expect(sinks.isEmpty)
    }

    // AR-5: camera interrupted routes to watch (double haptic + text) first and
    // uses the local notification when locked (mirrors to the watch).
    @Test func cameraInterruptedRouting() {
        let watch = AlertRoutingPolicy.route(
            .cameraInterrupted,
            context: context(available: [.watchHaptic, .phoneSpeaker]),
            tuning: tuning
        )
        #expect(watch.first == .watchHaptic)

        let locked = AlertRoutingPolicy.route(
            .cameraInterrupted,
            context: context(available: [.localNotification], appState: .lockedOrBackgrounded),
            tuning: tuning
        )
        #expect(locked == [.localNotification])
    }

    // AR-6: camera-stopped is a high-priority notice: every available in-ride
    // channel (watch + audio) is used, ordered watch-first.
    @Test func cameraStoppedUsesAllChannels() {
        let sinks = AlertRoutingPolicy.route(
            .cameraStopped(.thermal),
            context: context(available: [.watchHaptic, .phoneHeadphones]),
            tuning: tuning
        )
        #expect(sinks.first == .watchHaptic)
        #expect(sinks.contains(.phoneHeadphones))
    }

    // AR-7: clipSaved is a light confirmation — a single best channel (watch,
    // else audio), never the local notification.
    @Test func clipSavedLightConfirmation() {
        let withWatch = AlertRoutingPolicy.route(
            .clipSaved,
            context: context(available: [.watchHaptic, .phoneSpeaker]),
            tuning: tuning
        )
        #expect(withWatch == [.watchHaptic])

        let noWatch = AlertRoutingPolicy.route(
            .clipSaved,
            context: context(available: [.phoneSpeaker, .localNotification]),
            tuning: tuning
        )
        #expect(noWatch == [.phoneSpeaker])
    }

    // AR-8: per-kind cooldown. A rear-vehicle caution within the cooldown since
    // the last one is dropped; at/after the cooldown it routes again. Camera
    // notices use a longer (per-minute) cooldown.
    @Test func rearVehicleCooldown() {
        let recent = now.addingTimeInterval(-(tuning.rearVehicleAlertCooldown - 0.5))
        let dropped = AlertRoutingPolicy.route(
            .cautionRearVehicle,
            context: context(
                available: [.watchHaptic],
                lastDeliveredByKind: [AlertRoutingPolicy.cooldownKey(.cautionRearVehicle): recent]
            ),
            tuning: tuning
        )
        #expect(dropped.isEmpty)

        let elapsed = now.addingTimeInterval(-tuning.rearVehicleAlertCooldown)
        let allowed = AlertRoutingPolicy.route(
            .cautionRearVehicle,
            context: context(
                available: [.watchHaptic],
                lastDeliveredByKind: [AlertRoutingPolicy.cooldownKey(.cautionRearVehicle): elapsed]
            ),
            tuning: tuning
        )
        #expect(allowed == [.watchHaptic])
    }

    @Test func cameraNoticeCooldownPerReason() {
        let recent = now.addingTimeInterval(-(tuning.cameraNoticeCooldown - 1))
        let dropped = AlertRoutingPolicy.route(
            .cameraStopped(.thermal),
            context: context(
                available: [.watchHaptic],
                lastDeliveredByKind: [AlertRoutingPolicy.cooldownKey(.cameraStopped(.thermal)): recent]
            ),
            tuning: tuning
        )
        #expect(dropped.isEmpty)
    }

    // No available channel ⇒ nothing routed, regardless of kind.
    @Test func noAvailableChannelRoutesNothing() {
        let sinks = AlertRoutingPolicy.route(
            .cameraStopped(.battery),
            context: context(available: []),
            tuning: tuning
        )
        #expect(sinks.isEmpty)
    }
}
