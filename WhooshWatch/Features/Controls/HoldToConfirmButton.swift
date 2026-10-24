import SwiftUI

/// A press-and-hold button with a visible progress ring (watch-companion design
/// "Controls → Stop (hold ~1.0 s with a progress ring; release cancels)" and
/// "Idle → Start (hold 0.8 s)"). Releasing before the threshold cancels; holding
/// past it fires `onConfirm` once. A VoiceOver custom action performs the same
/// action without the hold, so the control is accessible (Requirement 18.x).
///
/// The hold is deliberate so a ride is never started or ended by accident.
struct HoldToConfirmButton: View {
    let title: String
    let systemImage: String
    /// Hold duration in seconds (Stop ~1.0 s, Start ~0.8 s).
    let holdSeconds: Double
    let tint: Color
    /// Accessibility action name, e.g. "Stop ride" / "Start ride".
    let actionName: String
    let onConfirm: () -> Void
    var enabled: Bool = true

    @State private var progress: Double = 0
    @State private var holdTask: Task<Void, Never>?
    /// Tick interval for the ring animation.
    private let tick = 0.02

    var body: some View {
        ZStack {
            Circle()
                .stroke(WatchTheme.mistDim.opacity(0.35), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: tick), value: progress)
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(enabled ? tint : WatchTheme.mistDim)
        }
        .frame(width: WatchTheme.cancelTarget, height: WatchTheme.cancelTarget)
        .contentShape(Circle())
        .opacity(enabled ? 1 : 0.5)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if enabled { beginHold() } }
                .onEnded { _ in endHold() }
        )
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Hold to confirm")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(actionName)) {
            if enabled { onConfirm() }
        }
    }

    private func beginHold() {
        guard holdTask == nil else { return }
        progress = 0
        let step = tick / holdSeconds
        holdTask = Task { @MainActor in
            while !Task.isCancelled && progress < 1 {
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                if Task.isCancelled { return }
                progress = min(1, progress + step)
                if progress >= 1 {
                    onConfirm()
                    progress = 0
                    holdTask = nil
                    return
                }
            }
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
        if progress < 1 { progress = 0 }   // released early → cancel
    }
}
