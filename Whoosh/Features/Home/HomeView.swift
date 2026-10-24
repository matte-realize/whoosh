import SwiftUI

/// Placeholder Home screen for the scaffolding task.
///
/// The real Home hub (weekly-stats dashboard, Recent rides, Start Ride, and the
/// location-denied state) is built in later tasks. For now it proves the app
/// builds and launches to a recognizable screen.
struct HomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Whoosh")
                .font(.largeTitle.bold())
            Text("Ready to ride?")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
