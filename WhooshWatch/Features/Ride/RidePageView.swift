import SwiftUI
import WhooshWire

/// The primary Ride page (watch-companion design "Pages → Ride"): large tabular
/// elapsed time, distance (mi) and speed (mph) in a row, and icon+text chips for
/// ride state, camera state, and the link when stale. At most three numbers
/// (product principle). A crash takeover (`CountdownView`) is layered above the
/// whole app in `WatchRootView`.
struct RidePageView: View {
    let model: WatchSessionModel
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var vm: WatchRideReducer.ViewModel { model.view }

    var body: some View {
        VStack(spacing: 4) {
            Text(WatchFormat.elapsed(vm.elapsedMs))
                .font(.watchMetricLarge)
                .foregroundStyle(WatchTheme.mist)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .accessibilityLabel("Elapsed \(WatchFormat.elapsed(vm.elapsedMs))")

            if !luminanceReduced {
                HStack(spacing: 14) {
                    metric(value: WatchFormat.miles(vm.distance10m), unit: "mi")
                    metric(value: WatchFormat.mph(vm.speedDms), unit: "mph")
                }
                .padding(.top, 2)

                chips
                    .padding(.top, 2)
            } else {
                // Reduced luminance: elapsed + one state glyph only.
                WatchChip(systemImage: WatchText.rideGlyph(vm.rideState),
                          text: WatchText.rideState(vm.rideState))
                    .padding(.top, 4)
            }

            if vm.banner == .signalLost {
                WatchChip(systemImage: "location.slash", text: "Signal lost — ride continues",
                          tint: WatchTheme.amber)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .background(WatchTheme.ink)
    }

    private func metric(value: String, unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.watchMetric)
                .foregroundStyle(WatchTheme.mist)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(WatchTheme.mistDim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(unit)")
    }

    private var chips: some View {
        VStack(spacing: 3) {
            WatchChip(systemImage: WatchText.rideGlyph(vm.rideState),
                      text: WatchText.rideState(vm.rideState))
            cameraChip
            if vm.showStaleChip {
                WatchChip(systemImage: "wifi.exclamationmark",
                          text: "Reconnecting…", tint: WatchTheme.amber)
            }
        }
    }

    private var cameraChip: some View {
        WatchChip(systemImage: WatchText.cameraGlyph(vm.cameraState),
                  text: WatchText.cameraState(vm.cameraState),
                  tint: WatchText.cameraTint(vm.cameraState))
    }
}

#Preview("Riding") {
    RidePageView(model: WatchDemo.makeModel(scenario: .riding))
}

#Preview("Camera trouble") {
    RidePageView(model: WatchDemo.makeModel(scenario: .ridingCameraTrouble))
}

#Preview("Signal lost") {
    RidePageView(model: WatchDemo.makeModel(scenario: .signalLost))
}
