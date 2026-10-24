import SwiftUI
import WhooshWire

/// The watch app root (watch-companion design "Watch-side design"). It chooses
/// the page set from the ride phase, pages vertically with the Crown, overlays
/// the crash countdown above everything, and drives the model's ~1 Hz `tick()`
/// (time projection + retry/TTL timers + countdown schedule).
struct WatchRootView: View {
    @State var model: WatchSessionModel

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var showRearFlash = false

    var body: some View {
        ZStack {
            WatchTheme.ink.ignoresSafeArea()
            content
            if showRearFlash && model.countdownPhase == .hidden {
                RearCueFlashView()
                    .transition(.opacity)
            }
            if model.countdownPhase != .hidden {
                CountdownView(model: model)
                    .transition(.opacity)
            }
        }
        .onChange(of: model.rearCuesPlayed) {
            withAnimation { showRearFlash = true }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { showRearFlash = false }
            }
        }
        .onReceive(ticker) { _ in model.tick() }
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.view.phase {
        case .noLink:
            NoLinkView()
        case .idle:
            NavigationStack {
                TabView {
                    IdlePageView(model: model)
                    SettingsPageView(model: model)
                }
                .tabViewStyle(.verticalPage)
            }
        case .activeFresh, .activeStale, .ending:
            NavigationStack {
                TabView {
                    RidePageView(model: model)
                    ControlsPageView(model: model)
                    NoticesPageView(model: model)
                    SettingsPageView(model: model)
                }
                .tabViewStyle(.verticalPage)
            }
        case .summary:
            NavigationStack {
                SummaryPageView(model: model)
            }
        }
    }
}

/// Shown when the phone link is down (honest, calm — never silent).
struct NoLinkView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.slash")
                .font(.title2)
                .foregroundStyle(WatchTheme.amber)
            Text("iPhone not responding")
                .font(.caption)
                .foregroundStyle(WatchTheme.mist)
            Text("Open Whoosh on your iPhone")
                .font(.caption2)
                .foregroundStyle(WatchTheme.mistDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(WatchTheme.ink)
    }
}

#Preview("Root — riding") {
    WatchRootView(model: WatchDemo.makeModel(scenario: .riding))
}

#Preview("Root — ready") {
    WatchRootView(model: WatchDemo.makeModel(scenario: .idleReady))
}

#Preview("Root — crash drill") {
    WatchRootView(model: WatchDemo.makeModel(scenario: .crashDrill))
}

/// A brief full-screen "Car behind" flash shown with the rear-vehicle buzz, so
/// the cue is visible as well as felt. Experimental cue.
private struct RearCueFlashView: View {
    var body: some View {
        ZStack {
            WatchTheme.amber.ignoresSafeArea()
            VStack(spacing: 6) {
                Image(systemName: "car.rear.fill")
                    .font(.system(size: 40, weight: .bold))
                Text("Car behind")
                    .font(.headline)
            }
            .foregroundStyle(WatchTheme.ink)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Car behind")
    }
}
