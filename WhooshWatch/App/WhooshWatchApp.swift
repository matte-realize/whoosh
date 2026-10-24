import SwiftUI
import WhooshWire

/// Entry point of the Whoosh watchOS companion app (watch-companion
/// Requirement 2.1). The app is deliberately **thin and phone-authoritative**:
/// it displays what the phone publishes, sends typed commands, and plays
/// haptics. It records no ride and holds no ride data.
///
/// Wiring (tasks 15, 19, 20): the real `WKHapticPlayer` plays wrist haptics; the
/// `WireLink` and `WorkoutSessionController` are the fakes until the real
/// WatchConnectivity adapter (tasks 16–17) and the HealthKit keep-alive
/// (task 18) land in parallel. The model never imports those frameworks — it
/// only depends on the seams — so swapping in the real services is a one-line
/// change here.
@main
struct WhooshWatchApp: App {
    @State private var model: WatchSessionModel = WhooshWatchApp.makeModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
    }

    @MainActor
    private static func makeModel() -> WatchSessionModel {
        // Real haptic actuator (the only watch-haptic caller, confined to
        // Services/Haptics/).
        let haptics = WKHapticPlayer()
        // Placeholder link + workout until tasks 16–18 provide the real adapters.
        // Using the fakes keeps the app runnable and previewable now; the demo
        // scenarios in `WatchDemo` exercise every page with scripted data.
        let link = FakeWireLink(reachable: false)
        let workout = FakeWorkoutSessionController()
        return WatchSessionModel(link: link, haptics: haptics, workout: workout)
    }
}
