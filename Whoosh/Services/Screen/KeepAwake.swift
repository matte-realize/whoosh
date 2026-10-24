import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The one owner of the idle timer. Screens ask to keep the phone awake and
/// release when they go away; the timer stays disabled while any reason is
/// still held, so dismissing an overlay (a cancelled crash countdown) can't let
/// the phone sleep mid-ride. Rear-camera task 21 grows this into the
/// `ScreenController` that also owns ride-mode brightness.
@MainActor
final class KeepAwake {
    enum Reason: Hashable {
        case ride
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
