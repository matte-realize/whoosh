import Foundation

/// The inert `RideRemoteControlling` used when no eyes-free surface exists
/// (rear-camera spec task 13; design "Eyes-free surfaces"). It accepts publishes
/// and never invokes `onCommand`, so the app runs unchanged with audio and the
/// on-phone unlock gesture as the only control paths (Requirement 13.8).
///
/// `@MainActor` (project default isolation); matches how the composition root
/// injects it.
@MainActor
final class NoopRideRemote: RideRemoteControlling {
    /// Never reachable: there is no surface.
    var isReachable: Bool { false }
    /// Never invoked.
    var onCommand: ((RideRemoteCommand, @escaping (RideRemoteCommandReply) -> Void) -> Void)?

    init() {}

    /// No-op: there is no surface to publish to.
    func publish(_ status: RideStatus) {}
}
