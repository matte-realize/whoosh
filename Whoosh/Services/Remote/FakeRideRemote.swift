import Foundation

/// Scriptable `RideRemoteControlling` for tests and previews (rear-camera spec
/// task 13; design "Eyes-free surfaces"). Records published statuses and can
/// deliver a scripted command into `onCommand`, capturing the reply.
///
/// Lives under `Services/Remote/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// `@MainActor` so its mutable log is race-free; the publisher and bridge that
/// drive it are also main-actor isolated.
@MainActor
final class FakeRideRemote: RideRemoteControlling {
    var isReachable: Bool
    var onCommand: ((RideRemoteCommand, @escaping (RideRemoteCommandReply) -> Void) -> Void)?

    /// Every status published, in order.
    private(set) var published: [RideStatus] = []

    init(isReachable: Bool = true) {
        self.isReachable = isReachable
    }

    func publish(_ status: RideStatus) {
        published.append(status)
    }

    // MARK: Scripting API (test/preview driven)

    /// Deliver a command through `onCommand` and return the reply the handler
    /// produced (or `.ignored(reason: .invalidState)` if no handler is set).
    @discardableResult
    func deliver(_ command: RideRemoteCommand) -> RideRemoteCommandReply {
        var captured: RideRemoteCommandReply = .ignored(reason: .invalidState)
        guard let onCommand else { return captured }
        onCommand(command) { reply in captured = reply }
        return captured
    }
}
