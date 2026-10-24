import SwiftUI
import WhooshWire

/// Entry point of the Whoosh watchOS companion app (watch-companion
/// Requirement 2.1). The app is deliberately **thin and phone-authoritative**:
/// it displays what the phone publishes, sends typed commands, and plays
/// haptics. It records no ride and holds no ride data.
///
/// Wiring (tasks 15–20, "make the watch live"): the `WatchAppDelegate` owns and
/// activates the single **real** WatchConnectivity link (task 17) and builds the
/// one `WatchSessionModel` over it, so the watch shows **live phone data**. When
/// the phone is unreachable the model shows the honest "iPhone not responding"
/// screen (it never fabricates ride data). The scripted fake-data demo
/// (`WatchDemo`) is used only in SwiftUI previews.
@main
struct WhooshWatchApp: App {
    /// The app delegate owns and activates the single watch connectivity link,
    /// builds the one session model over it, and completes every
    /// WatchConnectivity background task (task 17).
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            // The model built over the real link in the delegate → live data.
            WatchRootView(model: delegate.model)
        }
    }
}
