import SwiftUI

/// The app entry point.
///
/// The full composition root — wiring all concrete services, the
/// `NavigationStack`, the active-ride full-screen cover, and navigation
/// closures — is task 23. This interim wiring constructs a `HomeViewModel` with
/// the real `SystemClock`, an in-memory repository, and the `CoreLocationTracker`
/// so the app launches to a functional Home dashboard; task 23 replaces it with
/// the complete root (SwiftData repository, navigation, and the ride cover).
@main
struct WhooshApp: App {
    @State private var homeViewModel: HomeViewModel

    init() {
        // Interim services; task 23 swaps the repository for SwiftData and adds
        // navigation wiring.
        let repository = InMemoryRideRepository()
        let tracker = CoreLocationTracker()
        _homeViewModel = State(
            initialValue: HomeViewModel(
                repository: repository,
                clock: SystemClock(),
                tracker: tracker
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: homeViewModel)
        }
    }
}
