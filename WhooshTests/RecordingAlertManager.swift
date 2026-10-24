import Foundation
@testable import Whoosh

/// A recording `AlertManager` fake for tests: counts `fire(_:)` calls and keeps
/// the kinds fired, so demo-mode tests can assert the forced rear-alert path is
/// invoked exactly as expected without real haptics or audio.
///
/// Lives in the test target (test support); the app ships `StubAlertManager`
/// (inert) and `HapticAudioAlertManager` (real).
final class RecordingAlertManager: AlertManager {
    private(set) var firedKinds: [AlertKind] = []
    var fireCount: Int { firedKinds.count }

    func fire(_ kind: AlertKind) {
        firedKinds.append(kind)
    }
}
