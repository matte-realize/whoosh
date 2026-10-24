import Foundation

/// Scriptable `CameraPermission` for tests and SwiftUI previews.
///
/// Lives under `Services/Camera/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Scripting:
/// - Start it in any `status`.
/// - `grantResult` is the status `request()` resolves to from an unresolved
///   (`notDetermined`) state; from a resolved state `request()` returns the
///   current status unchanged (matching the system, which never re-prompts).
/// - `changeStatus(_:)` models the rider flipping access in Settings and fires
///   `onChange`.
/// Callbacks fire synchronously on the main actor so test expectations are
/// deterministic.
@MainActor
final class FakeCameraPermission: CameraPermission {
    private(set) var status: CameraPermissionStatus

    var onChange: ((CameraPermissionStatus) -> Void)?

    /// The status a `request()` resolves to when the current status is
    /// `notDetermined`. Defaults to `authorized` for the happy path.
    var grantResult: CameraPermissionStatus

    // MARK: Recorded interactions (for test assertions)

    /// Number of times `request()` was awaited.
    private(set) var requestCount = 0

    init(
        status: CameraPermissionStatus = .notDetermined,
        grantResult: CameraPermissionStatus = .authorized
    ) {
        self.status = status
        self.grantResult = grantResult
    }

    // MARK: CameraPermission

    @discardableResult
    func request() async -> CameraPermissionStatus {
        requestCount += 1
        // The system prompts only from `notDetermined`; a resolved state is
        // returned unchanged (the rider must use Settings to change it).
        guard status == .notDetermined else { return status }
        if status != grantResult {
            status = grantResult
            onChange?(status)
        } else {
            status = grantResult
        }
        return status
    }

    // MARK: Scripting API (test/preview driven)

    /// Change the status (e.g. the rider toggled access in Settings) and notify
    /// through `onChange`.
    func changeStatus(_ newStatus: CameraPermissionStatus) {
        status = newStatus
        onChange?(newStatus)
    }
}
