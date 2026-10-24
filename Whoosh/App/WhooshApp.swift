import SwiftUI

/// The app entry point and navigation host (task 23).
///
/// Builds the live composition root (`AppEnvironment.live()`), owns a
/// `NavigationStack` rooted at `HomeView`, pushes History and Settings (with a
/// "Home" back label), pushes `RideSummaryView` for a tapped recent/history
/// ride, and presents the active ride as a **non-dismissible full-screen
/// cover** while a session is in progress. When the ride finishes the cover
/// switches to the finished-ride summary; "Done" resets the session and returns
/// to Home. All service wiring lives here; views stay framework-service-free.
///
/// Lifecycle: `persistSnapshot()` runs when the scene goes background/inactive
/// (task 21 safeguard), and on launch an unfinished ride triggers a "Finish your
/// interrupted ride?" alert (Save finalizes it; Discard deletes that record).
@main
struct WhooshApp: App {
    @State private var environment = AppEnvironment.live()
    @State private var path: [Route] = []

    /// The in-progress ride session, or `nil` when idle. Created on Start Ride.
    @State private var rideSession: RideSessionViewModel?
    /// An unfinished ride found on launch, pending the recovery decision.
    @State private var interruptedRide: Ride?

    @Environment(\.scenePhase) private var scenePhase

    /// Routes pushed on the Home-rooted stack.
    private enum Route: Hashable {
        case history
        case settings
        case summary(Ride)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(
                    viewModel: environment.homeViewModel,
                    onStartRide: startRide,
                    onOpenHistory: { path.append(.history) },
                    onOpenSettings: { path.append(.settings) },
                    onSelectRide: { path.append(.summary($0)) }
                )
                .navigationDestination(for: Route.self, destination: destination)
            }
            .fullScreenCover(isPresented: coverBinding) {
                coverContent
            }
            .alert(
                "Finish your interrupted ride?",
                isPresented: interruptedAlertBinding,
                presenting: interruptedRide
            ) { ride in
                Button("Save") { saveInterrupted(ride) }
                Button("Discard", role: .destructive) { discardInterrupted(ride) }
            } message: { _ in
                Text("Whoosh found a ride that didn't finish. Save it to your history or discard it.")
            }
            .onAppear(perform: checkForInterruptedRide)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { rideSession?.persistSnapshot() }
            }
        }
    }

    // MARK: - Navigation destinations

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .history:
            HistoryView(
                viewModel: environment.makeHistoryViewModel(),
                onSelectRide: { path.append(.summary($0)) }
            )
        case .settings:
            SettingsView(viewModel: environment.settingsViewModel)
        case .summary(let ride):
            RideSummaryView(ride: ride, presentation: .historyDetail)
        }
    }

    // MARK: - Ride cover

    /// Present the cover whenever a session is active or finished (showing the
    /// summary). Non-dismissible: the setter ignores programmatic dismissal so a
    /// swipe/tap can't abandon a ride (Requirement 1.5).
    private var coverBinding: Binding<Bool> {
        Binding(
            get: {
                guard let session = rideSession else { return false }
                return RideFlowCoordinator.isCoverPresented(
                    for: session.rideState,
                    finishedRide: session.finishedRide
                )
            },
            set: { _ in }
        )
    }

    @ViewBuilder
    private var coverContent: some View {
        if let session = rideSession {
            switch RideFlowCoordinator.coverContent(
                for: session.rideState,
                finishedRide: session.finishedRide
            ) {
            case .activeRide:
                ActiveRideView(viewModel: session)
                    .interactiveDismissDisabled()
            case .summary(let ride):
                NavigationStack {
                    RideSummaryView(
                        ride: ride,
                        presentation: .justFinished,
                        onDone: finishRide
                    )
                }
                .interactiveDismissDisabled()
            case .none:
                // Nothing to show; dismiss by clearing the session next runloop.
                Color.clear.onAppear { rideSession = nil }
            }
        }
    }

    // MARK: - Ride lifecycle

    private func startRide() {
        let session = environment.makeRideSession()
        rideSession = session
        session.start()
    }

    /// "Done" on the finished-ride summary: clear the session (dismisses the
    /// cover) and refresh Home so the new ride appears in stats/recent.
    private func finishRide() {
        rideSession = nil
        environment.homeViewModel.load()
    }

    // MARK: - Interrupted-ride recovery (task 21 / 3.6)

    private func checkForInterruptedRide() {
        // Use a throwaway session purely to query the repository for an
        // unfinished ride; it owns no live tracking until `start()`.
        let probe = environment.makeRideSession()
        interruptedRide = probe.recoverInterruptedRide()
    }

    private func saveInterrupted(_ ride: Ride) {
        let session = environment.makeRideSession()
        session.finalizeRecoveredRide(ride)
        interruptedRide = nil
        environment.homeViewModel.load()
    }

    private func discardInterrupted(_ ride: Ride) {
        try? environment.repository.delete(id: ride.id)
        interruptedRide = nil
        environment.homeViewModel.load()
    }

    // MARK: - Alert binding

    private var interruptedAlertBinding: Binding<Bool> {
        Binding(
            get: { interruptedRide != nil },
            set: { if !$0 { interruptedRide = nil } }
        )
    }
}
