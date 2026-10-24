import Foundation
import Observation

/// View model for the Settings screen (Requirements 14.2, 14.4).
///
/// Owns the functional GPS-accuracy choice (Balanced / High), persisted in
/// `UserDefaults` so it survives relaunch, and maps it to `RideTuning.accuracy`
/// for the next ride. Also exposes the "Delete all rides" intent, which calls
/// `RideRepository.deleteAll()` and reports any failure as a user-facing,
/// non-raw message (Requirement 11.4) rather than surfacing framework error
/// text.
///
/// UI-framework-free (no SwiftUI import), per the layering table; the
/// `UserDefaults` suite is injectable so tests can use an isolated store.
@Observable
final class SettingsViewModel {
    /// Stable `UserDefaults` key for the persisted accuracy choice.
    static let accuracyDefaultsKey = "whoosh.settings.gpsAccuracy"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let repository: RideRepository

    /// The selected GPS accuracy. Persists to `UserDefaults` on every change so
    /// the composition root can read it back into `RideTuning` for the next ride.
    var accuracy: TrackingAccuracy {
        didSet { persistAccuracy() }
    }

    /// A user-facing message set when "Delete all rides" fails; `nil` when there
    /// is nothing to show. Never contains raw framework error text.
    var deleteErrorMessage: String?

    init(repository: RideRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        // Load the persisted choice; fall back to the RideTuning default when
        // absent or unrecognized.
        if let raw = defaults.string(forKey: Self.accuracyDefaultsKey),
           let stored = TrackingAccuracy(rawValue: raw) {
            self.accuracy = stored
        } else {
            self.accuracy = RideTuning().accuracy
        }
    }

    /// The `TrackingAccuracy` to feed into `RideTuning.accuracy` for the next
    /// ride. Mirrors `accuracy`; exposed as an explicit mapping point so the
    /// composition root does not reach into the persistence detail.
    var trackingAccuracy: TrackingAccuracy { accuracy }

    /// Permanently delete every stored ride (Requirement 14.4 / 7.8). On failure
    /// sets `deleteErrorMessage` to a plain, actionable message instead of
    /// throwing raw error text to the UI.
    func deleteAllRides() {
        deleteErrorMessage = nil
        do {
            try repository.deleteAll()
        } catch {
            deleteErrorMessage = "Couldn't delete your rides. Please try again."
        }
    }

    // MARK: Persistence

    private func persistAccuracy() {
        defaults.set(accuracy.rawValue, forKey: Self.accuracyDefaultsKey)
    }
}
