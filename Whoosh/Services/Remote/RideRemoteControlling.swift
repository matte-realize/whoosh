import Foundation

/// The seam an eyes-free surface (the recommended Apple Watch companion, a
/// shutter remote, or audio control) uses to receive ride status and send
/// commands (rear-camera spec Requirement 13.1, 13.2; design "Eyes-free
/// surfaces"). WatchConnectivity lives **only** behind this protocol in
/// `Services/Remote/`, implemented by the separate watch spec; this spec ships
/// `NoopRideRemote` and `FakeRideRemote` so everything else can be built and
/// tested now.
///
/// ## Contract
/// - **Status out, commands in.** `publish(_:)` sends a `RideStatus` snapshot;
///   `onCommand` is invoked when the surface sends a `RideRemoteCommand`, and
///   the handler replies with a `RideRemoteCommandReply`.
/// - **Ride engine unchanged.** Commands are mapped to existing ride intents by
///   `RideRemoteBridge`; the surface never reaches into the ride internals.
/// - **Non-blocking, on-device.** Publishing and command handling never block
///   recording and never touch the network beyond the local watch link.
/// - **Reachability.** `isReachable` reflects whether a surface can receive a
///   command right now; alerts fall back to audio when it is false.
protocol RideRemoteControlling: AnyObject {
    /// Whether a surface is currently reachable (e.g. the watch app is active).
    var isReachable: Bool { get }
    /// Invoked when the surface sends a command; the handler replies.
    var onCommand: ((RideRemoteCommand, _ reply: @escaping (RideRemoteCommandReply) -> Void) -> Void)? { get set }
    /// Publish the latest ride status to the surface.
    func publish(_ status: RideStatus)
}
