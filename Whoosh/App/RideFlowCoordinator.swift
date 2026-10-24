import Foundation

/// Pure presentation logic for the ride full-screen cover (Requirement 1.5 /
/// task 23), kept framework-free so the decision of *what the cover shows* is
/// unit-testable without SwiftUI.
///
/// `WhooshApp` presents a single non-dismissible `fullScreenCover` while a ride
/// is in progress; when the ride finishes the cover content switches to the
/// summary, and "Done" (which resets the session back to `idle`) dismisses it.
/// This type maps a `RideState` (plus the session's finished ride) to that
/// decision so the view layer only renders it.
enum RideFlowCoordinator {
    /// What the cover should present for a given session state.
    enum CoverContent: Equatable {
        /// No cover — Home is fully visible (ride is `idle`).
        case none
        /// The active-ride screen (recording / paused / signalLost).
        case activeRide
        /// The just-finished ride summary, dismissed with "Done".
        case summary(Ride)
    }

    /// Decide the cover content from the current ride state and the session's
    /// finished ride (set once `stop` finalizes).
    ///
    /// - `idle` → `.none` (cover dismissed / never shown).
    /// - `recording` / `paused` / `signalLost` → `.activeRide`.
    /// - `finished` → `.summary(ride)` if a finished ride exists, else `.none`
    ///   (defensive: a finished state with no ride has nothing to show).
    static func coverContent(
        for state: RideState,
        finishedRide: Ride?
    ) -> CoverContent {
        switch state {
        case .idle:
            return .none
        case .recording, .paused, .signalLost:
            return .activeRide
        case .finished:
            if let finishedRide {
                return .summary(finishedRide)
            }
            return .none
        }
    }

    /// Whether the cover should be presented at all (anything other than
    /// `.none`). Drives the `isPresented` binding of the `fullScreenCover`.
    static func isCoverPresented(
        for state: RideState,
        finishedRide: Ride?
    ) -> Bool {
        coverContent(for: state, finishedRide: finishedRide) != .none
    }
}
