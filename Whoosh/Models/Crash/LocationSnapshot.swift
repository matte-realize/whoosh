import Foundation

/// How fresh a captured location fix is, per the location snapshot policy
/// (spec Requirement 7, design "Location snapshot policy").
nonisolated enum LocationFixStatus: String, Codable, Sendable, CaseIterable {
    /// A fix with age ≤ 10 s — described to a contact as the current location.
    case current
    /// An older accepted fix — described as "last known location" with age.
    case lastKnown = "last_known"
    /// No accepted fix in this ride, or the freshest is older than the max age.
    case unavailable
}

/// A point-in-time location fix used in a crash alert: coordinates plus age and
/// horizontal accuracy, or an explicit "unavailable". Precise and **not**
/// privacy-zone trimmed, because a contact needs it (spec Requirement 16.5);
/// the consent screen states this.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`. `age(at:)`
/// is derived from `fixTime` so a persisted snapshot stays correct across
/// relaunches.
nonisolated struct LocationSnapshot: Equatable, Codable, Sendable {
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let fixTime: Date?
    let status: LocationFixStatus

    init(
        latitude: Double?,
        longitude: Double?,
        horizontalAccuracy: Double?,
        fixTime: Date?,
        status: LocationFixStatus
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.fixTime = fixTime
        self.status = status
    }

    /// The canonical "no location" snapshot.
    static let unavailable = LocationSnapshot(
        latitude: nil,
        longitude: nil,
        horizontalAccuracy: nil,
        fixTime: nil,
        status: .unavailable
    )

    /// Age of the fix in seconds at `now`, or `nil` when there is no fix time.
    func age(at now: Date) -> TimeInterval? {
        guard let fixTime else { return nil }
        return now.timeIntervalSince(fixTime)
    }
}
