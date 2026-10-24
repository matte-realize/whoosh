import Foundation

/// A location subsystem failure surfaced through `LocationTracking.onFailure`.
///
/// Decoupled from `CLError` so the engine never imports Core Location. The
/// `unknown` case carries a short description for logging/diagnostics without
/// exposing raw framework error text to the user (Requirement 11.4 is handled
/// in the view model/UI layer).
enum LocationFailure: Equatable, Sendable {
    /// The user denied or revoked location permission.
    case denied
    /// Location services are disabled device-wide.
    case servicesDisabled
    /// Any other failure; the string is for diagnostics, not user display.
    case unknown(String)
}
