import Foundation

/// Marker for the WhooshWire package — the Foundation-only shared wire contract
/// compiled into both the Whoosh iOS app and the WhooshWatch watchOS app.
///
/// The real contract (envelope, codec, DTOs, versioning, pure watch-side logic)
/// is added in watch-companion tasks 4, 5, and 8–12. This enum exists so the
/// package has a trivially buildable symbol from task 3 onward.
public enum WhooshWire {
    /// A human-readable name for the shared module.
    public static let name = "WhooshWire"
}
