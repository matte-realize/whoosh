import SwiftUI

/// Mounts the full-screen crash-countdown takeover as a **root-level overlay**
/// above everything else — the `NavigationStack`, Home, and the active-ride
/// full-screen cover (spec design D25, "Presentation", crash-response task 20).
///
/// This is provided as a `ViewModifier` + `View` extension so the composition
/// root (task 26) can attach it once at the app's root:
///
/// ```swift
/// RootView()
///     .crashCountdownHost(coordinator: environment.crashCoordinator)
/// ```
///
/// The overlay is driven solely by the coordinator's read-only
/// `isTakeoverPresented` flag (true only while the event is in `countdown`). It
/// uses a full-screen `overlay` (not a sheet or `fullScreenCover`) so it layers
/// above any presented cover and cannot be dismissed by a swipe or system
/// gesture — the only exits are Cancel, "Send now", or expiry, all handled
/// inside `CrashCountdownView`.
struct CrashCountdownHost: ViewModifier {
    let coordinator: CrashResponseCoordinator

    func body(content: Content) -> some View {
        content.overlay {
            if coordinator.isTakeoverPresented {
                CrashCountdownView(coordinator: coordinator)
                    .transition(.opacity)
                    // Above the ride cover and navigation chrome.
                    .zIndex(.greatestFiniteMagnitude)
            }
        }
    }
}

extension View {
    /// Attach the root-level crash-countdown takeover host. Call once at the
    /// app's root so the countdown can appear over every screen.
    func crashCountdownHost(coordinator: CrashResponseCoordinator) -> some View {
        modifier(CrashCountdownHost(coordinator: coordinator))
    }
}
