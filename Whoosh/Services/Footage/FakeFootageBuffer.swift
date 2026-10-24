import Foundation

/// Scriptable `FootageBuffer` for tests and previews that records calls and can
/// be scripted to return a reference from `preserve`.
///
/// `@MainActor` so its mutable call log is race-free (it conforms to the
/// `Sendable` `FootageBuffer` protocol by being main-actor isolated); the
/// coordinator that drives it is also main-actor isolated. Tests reach it via
/// `@testable import`.
///
/// It never captures, stores, or transmits real media; `referenceToReturn`
/// stands in for a local-only reference so call plumbing can be exercised.
@MainActor
final class FakeFootageBuffer: FootageBuffer {
    /// The reference `preserve` returns, or `nil` to model "no footage".
    var referenceToReturn: String?

    /// Every `(eventId, detectedAt)` passed to `preserve`, in call order.
    private(set) var preserveCalls: [(eventId: UUID, detectedAt: Date)] = []
    /// Every reference passed to `delete`, in call order.
    private(set) var deletedReferences: [String] = []

    init(referenceToReturn: String? = nil) {
        self.referenceToReturn = referenceToReturn
    }

    func preserve(eventId: UUID, around detectedAt: Date) -> String? {
        preserveCalls.append((eventId, detectedAt))
        return referenceToReturn
    }

    func delete(reference: String) {
        deletedReferences.append(reference)
    }
}
