import Foundation
import Testing
@testable import Whoosh

/// Tests for `SettingsViewModel` (Requirements 14.2, 14.4, 11.4).
///
/// `@MainActor` because the view model inherits the project's default MainActor
/// isolation. Each test uses an isolated `UserDefaults` suite so persistence is
/// deterministic and leaves no global state behind.
@MainActor
struct SettingsViewModelTests {
    /// A fresh, isolated `UserDefaults` suite for one test.
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "whoosh.settings.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create test UserDefaults suite")
        }
        return (defaults, suiteName)
    }

    private func cleanUp(_ defaults: UserDefaults, _ suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: accuracy persistence

    @Test func defaultsToRideTuningAccuracyWhenNothingStored() {
        let (defaults, suite) = makeDefaults()
        defer { cleanUp(defaults, suite) }

        let vm = SettingsViewModel(
            repository: InMemoryRideRepository(),
            defaults: defaults
        )
        #expect(vm.accuracy == RideTuning().accuracy)
    }

    @Test func settingAccuracyPersistsAndReloadsAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { cleanUp(defaults, suite) }

        let first = SettingsViewModel(
            repository: InMemoryRideRepository(),
            defaults: defaults
        )
        first.accuracy = .balanced

        // A new instance over the same defaults must load the persisted value,
        // proving the choice survives relaunch.
        let second = SettingsViewModel(
            repository: InMemoryRideRepository(),
            defaults: defaults
        )
        #expect(second.accuracy == .balanced)
    }

    @Test func accuracyMapsToTrackingAccuracy() {
        let (defaults, suite) = makeDefaults()
        defer { cleanUp(defaults, suite) }

        let vm = SettingsViewModel(
            repository: InMemoryRideRepository(),
            defaults: defaults
        )
        vm.accuracy = .high
        #expect(vm.trackingAccuracy == .high)
        vm.accuracy = .balanced
        #expect(vm.trackingAccuracy == .balanced)
    }

    @Test func unrecognizedStoredValueFallsBackToDefault() {
        let (defaults, suite) = makeDefaults()
        defer { cleanUp(defaults, suite) }

        defaults.set("garbage", forKey: SettingsViewModel.accuracyDefaultsKey)
        let vm = SettingsViewModel(
            repository: InMemoryRideRepository(),
            defaults: defaults
        )
        #expect(vm.accuracy == RideTuning().accuracy)
    }

    // MARK: delete all rides

    @Test func deleteAllRidesCallsRepositoryAndClearsStorage() throws {
        let (defaults, suite) = makeDefaults()
        defer { cleanUp(defaults, suite) }

        let repo = InMemoryRideRepository()
        try repo.save(Ride(startedAt: Date(timeIntervalSince1970: 1_000)))
        try repo.save(Ride(startedAt: Date(timeIntervalSince1970: 2_000)))

        let vm = SettingsViewModel(repository: repo, defaults: defaults)
        vm.deleteAllRides()

        #expect(try repo.allRides().isEmpty)
        #expect(vm.deleteErrorMessage == nil)
    }

    @Test func deleteAllRidesSurfacesUserFacingErrorOnFailure() {
        let (defaults, suite) = makeDefaults()
        defer { cleanUp(defaults, suite) }

        let vm = SettingsViewModel(
            repository: FailingRideRepository(),
            defaults: defaults
        )
        vm.deleteAllRides()

        #expect(vm.deleteErrorMessage != nil)
        // Must not leak raw framework error text.
        #expect(vm.deleteErrorMessage?.contains("RepositoryError") == false)
    }
}

/// A repository whose `deleteAll()` always throws, to exercise the view model's
/// user-facing error path (Requirement 11.4). Other operations are no-ops.
private final class FailingRideRepository: RideRepository {
    private enum RepositoryError: Error { case failed }

    func save(_ ride: Ride) throws {}
    func allRides() throws -> [Ride] { [] }
    func ride(id: UUID) throws -> Ride? { nil }
    func delete(id: UUID) throws {}
    func deleteAll() throws { throw RepositoryError.failed }
}
