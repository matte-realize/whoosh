import SwiftUI

/// The app entry point. The composition root (service wiring, dependency
/// injection, and the `NavigationStack`) is fleshed out in later tasks; for the
/// scaffolding task it simply shows the placeholder Home screen.
@main
struct WhooshApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
