import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A full-screen, touch-absorbing lock for ride mode that recognises **both** a
/// one-finger and a two-finger press-and-hold (~1 s) as an unlock (owner
/// device-testing feedback: "allow a ONE-finger press-and-hold of ~1 s anywhere
/// to unlock (keep the two-finger long-press too)"). After the rider picks the
/// phone up they no longer need two fingers, but the deliberate two-finger hold
/// still works exactly as before.
///
/// Both gestures are deliberate holds, so a quick, incidental tap (a knee, a
/// jersey brush, a rain drop) does nothing — the touch must last the full
/// `minimumDuration`. The view swallows all touches so nothing underneath reacts
/// while locked. Using one view with two `UILongPressGestureRecognizer`s (one
/// requiring one touch, one requiring two) is the reliable path; SwiftUI's
/// `LongPressGesture` cannot require a touch count and stacking two swallowing
/// layers would starve the lower recognizer.
///
/// Lives under `Support/Representables/` (UIKit wrappers), matching the layering
/// table. It performs no screen or camera work; it only reports the gesture.
struct RideModeUnlockLock: UIViewRepresentable {
    /// Seconds a hold must last before the unlock fires (~1 s).
    var minimumDuration: TimeInterval
    /// Called on the main actor when either hold completes.
    var onUnlock: () -> Void

    #if canImport(UIKit)
    func makeUIView(context: Context) -> UIView {
        let view = TouchSwallowingView()
        for touches in [1, 2] {
            let recognizer = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handle(_:))
            )
            recognizer.numberOfTouchesRequired = touches
            recognizer.minimumPressDuration = minimumDuration
            // Generous slop: a rider holding a just-picked-up phone wobbles.
            recognizer.allowableMovement = 40
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onUnlock = onUnlock
        uiView.gestureRecognizers?
            .compactMap { $0 as? UILongPressGestureRecognizer }
            .forEach { $0.minimumPressDuration = minimumDuration }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUnlock: onUnlock)
    }

    /// Routes a recognizer's `.began` phase (a hold completed) to the SwiftUI
    /// closure, once per press.
    final class Coordinator: NSObject {
        var onUnlock: () -> Void

        init(onUnlock: @escaping () -> Void) {
            self.onUnlock = onUnlock
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onUnlock()
        }
    }

    /// A view that is opaque to hit-testing so every touch is absorbed by the
    /// lock (nothing underneath reacts while the screen is locked).
    private final class TouchSwallowingView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    }
    #else
    func makeUIView(context: Context) -> NSObject { NSObject() }
    func updateUIView(_ uiView: NSObject, context: Context) {}
    #endif
}
