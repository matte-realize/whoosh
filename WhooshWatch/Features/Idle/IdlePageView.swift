import SwiftUI
import WhooshWire

/// The Idle / Ready page (watch-companion design "Pages → Idle / Ready"): a
/// readiness line, a hold-to-start (0.8 s) control enabled only when the phone
/// reports `armed`, and the last ride summary. When not armed it shows the
/// short reason from the phone ("Tap Ready on your iPhone").
struct IdlePageView: View {
    let model: WatchSessionModel

    private var armed: Bool { model.view.controls.startEnabled }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("Whoosh")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.mist)
                Text(armed ? "Ready to ride" : "Waiting for iPhone")
                    .font(.caption2)
                    .foregroundStyle(armed ? WatchTheme.lime : WatchTheme.mistDim)
            }

            if armed {
                VStack(spacing: 4) {
                    Text("Hold to start")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.mistDim)
                    HoldToConfirmButton(
                        title: "Start",
                        systemImage: "play.fill",
                        holdSeconds: 0.8,
                        tint: WatchTheme.lime,
                        actionName: "Start ride",
                        onConfirm: { model.requestStart() }
                    )
                }
            } else {
                WatchChip(systemImage: "iphone", text: WatchText.controlReason(model.view.controls.start),
                          tint: WatchTheme.mistDim)
            }

            if let s = model.summary {
                lastRide(s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .background(WatchTheme.ink)
    }

    private func lastRide(_ s: WireSummary) -> some View {
        VStack(spacing: 1) {
            Text("Last ride")
                .font(.caption2).foregroundStyle(WatchTheme.mistDim)
            Text("\(WatchFormat.miles(s.distance10m)) mi · \(WatchFormat.elapsed(s.durationMs))")
                .font(.caption2).foregroundStyle(WatchTheme.mist)
        }
        .padding(.top, 2)
    }
}

#Preview("Ready (armed)") {
    IdlePageView(model: WatchDemo.makeModel(scenario: .idleReady))
}

#Preview("Not ready") {
    IdlePageView(model: WatchDemo.makeModel(scenario: .idleNotReady))
}
