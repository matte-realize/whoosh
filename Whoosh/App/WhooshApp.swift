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
    /// Set once if local storage degraded to a non-persistent store; shown as a
    /// calm, dismissible notice (Requirement 11.4).
    @State private var storageNoticePresented = false
    /// Presents the crash-alert status screen after a backup-notification tap
    /// (crash-response task 26, Requirement 13.3). Prompt-only; nothing automatic.
    @State private var crashStatusPresented = false
    /// Routes crash backup-notification taps to the status screen.
    @State private var notificationRouter = CrashNotificationRouter()

    @Environment(\.scenePhase) private var scenePhase

    /// Routes pushed on the Home-rooted stack.
    private enum Route: Hashable {
        case history
        case settings
        case summary(Ride)
        case crashAlerts
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(
                    viewModel: environment.homeViewModel,
                    onStartRide: startRide,
                    onOpenHistory: { path.append(.history) },
                    onOpenSettings: { path.append(.settings) },
                    onSelectRide: { path.append(.summary($0)) },
                    crashAlertsOn: environment.crash.isFeatureOn
                )
                .navigationDestination(for: Route.self, destination: destination)
            }
            .overlay(alignment: .top) {
                // DEMO MODE badge over the app chrome (Home + pushed screens),
                // below the ride cover and any crash takeover. Tapping it opens
                // the demo tools in Settings (O-DM5).
                if environment.demo.badgeVisible {
                    DemoBadge(scheme: .light) {
                        if path.last != .settings { path.append(.settings) }
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
            }
            .fullScreenCover(isPresented: coverBinding) {
                coverContent
            }
            // The crash-countdown takeover is mounted as a root-level overlay
            // ABOVE the NavigationStack AND the active-ride full-screen cover
            // (design D25): it must appear from Home (drills) and from the ride
            // screen, and cannot be swiped away.
            .crashCountdownHost(coordinator: environment.crash.coordinator)
            .sheet(isPresented: $crashStatusPresented) {
                NavigationStack {
                    CrashAlertStatusView(coordinator: environment.crash.coordinator)
                }
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
            .alert(
                "Ride saving unavailable",
                isPresented: $storageNoticePresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(environment.storageNotice ?? "")
            }
            .onAppear(perform: onLaunch)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
            .onChange(of: notificationRouter.shouldOpenStatus) { _, shouldOpen in
                if shouldOpen {
                    crashStatusPresented = true
                    notificationRouter.shouldOpenStatus = false
                }
            }
        }
    }

    // MARK: - Navigation destinations

    /// Builds the History view model and wires its local delete to request a
    /// remote deletion too (no-op while sync is off).
    private func makeHistoryViewModel() -> HistoryViewModel {
        let viewModel = environment.makeHistoryViewModel()
        viewModel.onDidDelete = { ride in
            Task { await environment.rideWasDeleted(ride) }
        }
        return viewModel
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .history:
            HistoryView(
                viewModel: makeHistoryViewModel(),
                onSelectRide: { path.append(.summary($0)) }
            )
        case .settings:
            SettingsView(
                viewModel: environment.settingsViewModel,
                rearCamera: environment.rearCameraSettingsViewModel,
                demo: environment.demo,
                onOpenCrashAlerts: { path.append(.crashAlerts) }
            )
        case .summary(let ride):
            RideSummaryView(ride: ride, presentation: .historyDetail)
        case .crashAlerts:
            EmergencySetupHostView(
                contactStore: environment.crash.contactStore,
                consentStore: environment.crash.consentStore,
                settingsStore: environment.crash.settingsStore,
                notifier: environment.crash.noopNotifier,
                connectivity: environment.crash.connectivity,
                scheduler: environment.crash.scheduler,
                repository: environment.crash.repository,
                clock: environment.clock,
                isMessagingConnected: environment.crash.isMessagingConnected,
                onConsentRevoked: {
                    // Revoking disarms immediately and cancels any queued unsent
                    // alert (Requirement 3.7).
                    environment.crash.coordinator.consentRevoked()
                    environment.crash.reevaluateArming()
                }
            )
            .onDisappear {
                // Contacts / consent / toggle may have changed in setup; re-arm.
                environment.crash.reevaluateArming()
            }
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
                ActiveRideView(viewModel: session, crashAlertsOn: environment.crash.isFeatureOn)
                    .interactiveDismissDisabled()
                    .overlay(alignment: .top) {
                        if environment.demo.badgeVisible {
                            // Positioned at the top so it never obscures the
                            // three metrics or the hold-to-stop control.
                            DemoBadge(scheme: .dark)
                                .padding(.top, Theme.Spacing.sm)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if environment.demo.badgeVisible {
                            RideScreenDemoMenu(controller: environment.demo)
                                .padding(Theme.Spacing.lg)
                        }
                    }
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
                Color.clear.onAppear { clearRideSession() }
            }
        }
    }

    // MARK: - Ride lifecycle

    private func startRide() {
        let session = environment.makeRideSession()
        rideSession = session
        session.start()
    }

    /// "Done" on the finished-ride summary: upload it (no-op while sync is off),
    /// clear the session (dismisses the cover) and refresh Home so the new ride
    /// appears in stats/recent.
    private func finishRide() {
        let finished = rideSession?.finishedRide
        clearRideSession()
        environment.homeViewModel.load()
        if let finished {
            Task { await environment.rideDidFinish(finished) }
        }
    }

    /// Clear the ride session and detach the crash bridge (disarms detection).
    private func clearRideSession() {
        environment.clearRideSession()
        rideSession = nil
    }

    // MARK: - Launch

    private func onLaunch() {
        notificationRouter.install()
        // Reconcile any persisted active crash event (task 14): resume a live
        // countdown, prompt for recovery past a deadline, or mark stale — never
        // auto-send on relaunch (Requirement 13.5).
        environment.crash.reconcileOnLaunch()
        checkForInterruptedRide()
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            environment.crash.coordinator.enterForeground()
            // Retry pending uploads/deletes (no-op while sync is off).
            Task { await environment.retryPendingSync() }
        } else {
            rideSession?.persistSnapshot()
            environment.crash.coordinator.enterBackground()
        }
    }

    // MARK: - Interrupted-ride recovery (task 21 / 3.6)

    private func checkForInterruptedRide() {
        // Use a throwaway session purely to query the repository for an
        // unfinished ride; it owns no live tracking until `start()`. Detach the
        // crash bridge the probe attached, since we are not starting a ride.
        let probe = environment.makeRideSession()
        interruptedRide = probe.recoverInterruptedRide()
        environment.clearRideSession()
        // Surface the non-fatal storage notice once, if storage degraded.
        if environment.storageNotice != nil { storageNoticePresented = true }
    }

    private func saveInterrupted(_ ride: Ride) {
        let session = environment.makeRideSession()
        session.finalizeRecoveredRide(ride)
        environment.clearRideSession()
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
