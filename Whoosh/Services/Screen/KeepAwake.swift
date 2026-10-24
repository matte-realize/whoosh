import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The one owner of the idle timer. Screens ask to keep the phone awake and
/// release when they go away; the timer stays disabled while any reason is
/// still held, so dismissing an overlay (a cancelled crash countdown) can't let
/// the phone sleep mid-ride.
///
/// Rear-camera task 21: `UIKitScreenController` (the `ScreenController` that also
/// owns ride-mode brightness) drives this via the `.rideMode` reason, so every
/// `isIdleTimerDisabled` write still funnels through this single reason-counting
/// owner. `ActiveRideView` is migrated to call the controller's
/// `setIdleTimerDisabled(_:)` instead of touching `KeepAwake` directly; the
/// crash countdown keeps acquiring `.crashCountdown` here, so a ride that
/// out-lives a cancelled countdown is never allowed to sleep.
@MainActor
final class KeepAwake {
    enum Reason: Hashable {
        /// The active-ride screen wants the phone awake (the ride mode screen
        /// controller holds this while the idle timer is disabled).
        case ride
        /// The crash countdown takeover wants the phone awake.
        case crashCountdown
    }

    static let shared = KeepAwake(apply: { disabled in
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    })

    private var held: Set<Reason> = []
    private let apply: (Bool) -> Void

    init(apply: @escaping (Bool) -> Void) {
        self.apply = apply
    }

    func acquire(_ reason: Reason) {
        held.insert(reason)
        apply(true)
    }

    func release(_ reason: Reason) {
        held.remove(reason)
        apply(!held.isEmpty)
    }
}
