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
    /// Key for the opt-in cloud-sync toggle (off by default).
    static let syncEnabledDefaultsKey = "whoosh.settings.syncEnabled"
    /// Key for the global public-sharing toggle (off by default).
    static let shareNewRidesDefaultsKey = "whoosh.settings.shareNewRidesPublicly"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let repository: RideRepository

    /// The selected GPS accuracy. Persists to `UserDefaults` on every change so
    /// the composition root can read it back into `RideTuning` for the next ride.
    var accuracy: TrackingAccuracy {
        didSet { persistAccuracy() }
    }

    /// Whether opt-in cloud sync is enabled (Requirement 12.1). OFF by default.
    /// Persisted so it survives relaunch. The composition root observes this to
    /// enable/disable the live `SupabaseRideSyncService`.
    private(set) var syncEnabled: Bool

    /// The global "Share new rides on the Whoosh website" flag (Requirement
    /// 12.11). OFF by default, only meaningful while `syncEnabled` is true, and
    /// never retroactive (stamped per-ride at finalize by the coordinator).
    private(set) var shareNewRidesPublicly: Bool

    /// A user-facing message set when "Delete all rides" fails; `nil` when there
    /// is nothing to show. Never contains raw framework error text.
    var deleteErrorMessage: String?

    /// Called whenever `syncEnabled` changes (composition root reacts: e.g.
    /// retry pending uploads when turned on). Not persisted.
    @ObservationIgnored var onSyncEnabledChange: ((Bool) -> Void)?
    /// Called when the user chooses to unshare already-shared rides (Requirement
    /// 12.14) — the composition root drives `SyncCoordinator.unshareRides`.
    @ObservationIgnored var onUnshareAllSharedRides: (() -> Void)?

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
        self.syncEnabled = defaults.bool(forKey: Self.syncEnabledDefaultsKey)
        self.shareNewRidesPublicly = defaults.bool(forKey: Self.shareNewRidesDefaultsKey)
    }

    /// The `TrackingAccuracy` to feed into `RideTuning.accuracy` for the next
    /// ride. Mirrors `accuracy`; exposed as an explicit mapping point so the
    /// composition root does not reach into the persistence detail.
    var trackingAccuracy: TrackingAccuracy { accuracy }

    /// A prompt the Settings screen must present before a toggle change takes
    /// effect. The view binds its alerts/confirmations to the active prompt.
    enum Prompt: Equatable {
        /// Confirm turning sharing ON: states exactly what becomes public.
        case confirmEnableSharing
        /// Turning sharing OFF while rides are shared: unshare them or keep them.
        case confirmDisableSharing
        /// Turning sync OFF while rides are still shared (Requirement 12.16).
        case confirmDisableSyncWhileShared
    }

    /// The currently active prompt, or `nil`. The view observes this.
    var activePrompt: Prompt?

    // MARK: Sync + sharing intents

    /// User toggled the "Sync rides to Whoosh map" switch. Turning sync OFF
    /// while rides are still shared raises the disable-sync prompt first
    /// (Requirement 12.16); otherwise the change applies immediately.
    func setSyncEnabled(_ enabled: Bool) {
        if !enabled, syncEnabled, hasSharedRides() {
            activePrompt = .confirmDisableSyncWhileShared
            return
        }
        applySyncEnabled(enabled)
    }

    /// User toggled the global sharing switch. Turning it ON raises the
    /// confirmation prompt first (Requirement 12.12); turning it OFF while rides
    /// are shared raises the unshare-or-keep prompt (12.14). A change that needs
    /// no prompt applies immediately.
    func setShareNewRidesPublicly(_ shared: Bool) {
        guard syncEnabled else { return } // only mutable while sync is on
        if shared, !shareNewRidesPublicly {
            activePrompt = .confirmEnableSharing
            return
        }
        if !shared, shareNewRidesPublicly, hasSharedRides() {
            activePrompt = .confirmDisableSharing
            return
        }
        applyShareNewRidesPublicly(shared)
    }

    // MARK: Prompt resolutions

    /// User confirmed enabling sharing from `confirmEnableSharing`.
    func confirmEnableSharing() {
        applyShareNewRidesPublicly(true)
        activePrompt = nil
    }

    /// User confirmed disabling sharing AND chose to unshare already-shared rides.
    func confirmDisableSharingAndUnshare() {
        applyShareNewRidesPublicly(false)
        onUnshareAllSharedRides?()
        activePrompt = nil
    }

    /// User disabled sharing but chose to keep already-shared rides public.
    func confirmDisableSharingKeepShared() {
        applyShareNewRidesPublicly(false)
        activePrompt = nil
    }

    /// User confirmed disabling sync while rides are shared, unsharing first.
    func confirmDisableSyncAndUnshare() {
        onUnshareAllSharedRides?()
        applyShareNewRidesPublicly(false)
        applySyncEnabled(false)
        activePrompt = nil
    }

    /// User confirmed disabling sync but keeping the shared rides public.
    func confirmDisableSyncKeepShared() {
        applySyncEnabled(false)
        activePrompt = nil
    }

    /// Dismiss a prompt without changing anything.
    func cancelPrompt() {
        activePrompt = nil
    }

    // MARK: Sync/sharing helpers

    /// Whether any stored ride is currently marked public.
    func hasSharedRides() -> Bool {
        ((try? repository.allRides()) ?? []).contains { $0.sharePublicly }
    }

    private func applySyncEnabled(_ enabled: Bool) {
        syncEnabled = enabled
        defaults.set(enabled, forKey: Self.syncEnabledDefaultsKey)
        // Sharing is only available while sync is on; clear the flag when sync
        // turns off (already-shared rides keep their stamp unless unshared).
        if !enabled, shareNewRidesPublicly {
            applyShareNewRidesPublicly(false)
        }
        onSyncEnabledChange?(enabled)
    }

    private func applyShareNewRidesPublicly(_ shared: Bool) {
        shareNewRidesPublicly = shared
        defaults.set(shared, forKey: Self.shareNewRidesDefaultsKey)
    }

    /// Called after a successful "Delete all rides" with the ids of rides that
    /// had been uploaded (synced/pending/failed), so the composition root can
    /// propagate remote deletions (Requirement 12.6). Not persisted.
    @ObservationIgnored var onDidDeleteAllRides: (([UUID]) -> Void)?

    /// Permanently delete every stored ride (Requirement 14.4 / 7.8). On failure
    /// sets `deleteErrorMessage` to a plain, actionable message instead of
    /// throwing raw error text to the UI.
    func deleteAllRides() {
        deleteErrorMessage = nil
        // Collect ids of rides that left the device *before* wiping, so their
        // remote rows can be deleted even though the local copies are gone.
        let previouslyUploaded = ((try? repository.allRides()) ?? [])
            .filter { $0.syncStatus != .localOnly }
            .map(\.id)
        do {
            try repository.deleteAll()
            onDidDeleteAllRides?(previouslyUploaded)
        } catch {
            deleteErrorMessage = "Couldn't delete your rides. Please try again."
        }
    }

    // MARK: Persistence

    private func persistAccuracy() {
        defaults.set(accuracy.rawValue, forKey: Self.accuracyDefaultsKey)
    }
}
