import SwiftUI

/// Entry point of the Whoosh watchOS companion app (watch-companion
/// Requirement 2.1). The app is deliberately **thin and phone-authoritative**:
/// it displays what the phone publishes, sends typed commands, and plays
/// haptics. It records no ride and holds no ride data.
///
/// This is the task 3 scaffold: it shows a placeholder screen so the target
/// builds and installs. The real session model, pages, link, workout, and
/// haptic services arrive in watch-companion tasks 15–21 (after the task 1
/// feasibility spike returns a go decision).
@main
struct WhooshWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchPlaceholderView()
        }
    }
}
