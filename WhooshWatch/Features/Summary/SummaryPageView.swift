import SwiftUI
import WhooshWire

/// The Summary page (watch-companion design "Pages → Summary"): totals and
/// counts only (no route, location, or contacts — privacy), with Save to Health
/// / Discard. The default choice is applied by the workout controller after
/// 60 s; these buttons let the rider choose sooner.
struct SummaryPageView: View {
    let model: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Ride complete")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.mist)

                if let s = model.summary {
                    totals(s)
                } else {
                    totalsFromView
                }

                VStack(spacing: 6) {
                    Button {
                        model.saveWorkout()
                    } label: {
                        Label("Save to Health", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity, minHeight: WatchTheme.minTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.lime)

                    Button(role: .destructive) {
                        model.discardWorkout()
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: WatchTheme.minTarget)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .background(WatchTheme.ink)
    }

    private func totals(_ s: WireSummary) -> some View {
        VStack(spacing: 2) {
            row("Time", WatchFormat.elapsed(s.durationMs))
            row("Distance", "\(WatchFormat.miles(s.distance10m)) mi")
            row("Avg speed", "\(WatchFormat.mph(s.avgSpeedDms)) mph")
            row("Cues", "\(s.cueCount)")
        }
    }

    private var totalsFromView: some View {
        VStack(spacing: 2) {
            row("Time", WatchFormat.elapsed(model.view.elapsedMs))
            row("Distance", "\(WatchFormat.miles(model.view.distance10m)) mi")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(WatchTheme.mistDim)
            Spacer()
            Text(value).font(.caption).foregroundStyle(WatchTheme.mist)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

#Preview("Summary") {
    SummaryPageView(model: WatchDemo.makeModel(scenario: .summary))
}
