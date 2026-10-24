import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A full-screen, touch-absorbing layer whose **only** recognised gesture is a
/// deliberate **two-finger long press** (rear-camera spec Requirement 10.5,
/// design "Ride mode": the touch lock ignores incidental touches; the unlock is
/// two fingers held for ~1 s). Used by `RideModeView` so a single-finger rain
/// drop, a knee, or a jersey brush cannot unlock the dimmed screen.
///
/// A `UIViewRepresentable` because SwiftUI's `LongPressGesture` cannot require a
/// specific number of touches; a `UILongPressGestureRecognizer` with
/// `numberOfTouchesRequired = 2` is the reliable path. The view swallows all
/// other touches (it is opaque to hit-testing) so nothing underneath reacts
/// while locked.
///
/// Lives under `Support/Representables/` (UIKit wrappers), matching the layering
/// table. It performs no screen or camera work; it only reports the gesture.
struct TwoFingerLongPressLock: UIViewRepresentable {
    /// Seconds the two fingers must be held before the unlock fires.
    var minimumDuration: TimeInterval
    /// Called on the main actor when the two-finger long press completes.
    var onUnlock: () -> Void

    #if canImport(UIKit)
    func makeUIView(context: Context) -> UIView {
        let view = TouchSwallowingView()
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        recognizer.numberOfTouchesRequired = 2
        recognizer.minimumPressDuration = minimumDuration
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onUnlock = onUnlock
        if let recognizer = uiView.gestureRecognizers?
            .compactMap({ $0 as? UILongPressGestureRecognizer }).first {
            recognizer.minimumPressDuration = minimumDuration
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUnlock: onUnlock)
    }

    /// Routes the recognizer's `.began` phase (the hold completed) to the
    /// SwiftUI closure, once per press.
    final class Coordinator: NSObject {
        var onUnlock: () -> Void

        init(onUnlock: @escaping () -> Void) {
            self.onUnlock = onUnlock
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            // `.began` fires exactly once when the minimum duration elapses with
            // the required touches down.
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
