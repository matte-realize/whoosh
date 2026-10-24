import Foundation

/// `UserDefaults`-backed `ConsentStore`. The record is stored as a single JSON
/// blob under a dedicated key (injectable suite + key for tests). It holds only
/// the consent version, timestamp, and acknowledgement — **no contact data**
/// (Requirement 16; design "Entities").
@MainActor
final class UserDefaultsConsentStore: ConsentStore {
    /// The `UserDefaults` key under which the consent record is stored.
    static let defaultsKey = "whoosh.crash.consentRecord"

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    func current() -> ConsentRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        // A record written by a newer/corrupt build reads back as "no consent"
        // (fail closed): the feature stays disarmed rather than crashing.
        return try? decoder.decode(ConsentRecord.self, from: data)
    }

    func record(version: Int, acknowledgedNotGuaranteed: Bool, acceptedAt: Date) {
        let record = ConsentRecord(
            version: version,
            acceptedAt: acceptedAt,
            acknowledgedNotGuaranteed: acknowledgedNotGuaranteed
        )
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func revoke() {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory `ConsentStore` for unit tests and previews.
@MainActor
final class InMemoryConsentStore: ConsentStore {
    private var consent: ConsentRecord?

    init(consent: ConsentRecord? = nil) {
        self.consent = consent
    }

    func current() -> ConsentRecord? { consent }

    func record(version: Int, acknowledgedNotGuaranteed: Bool, acceptedAt: Date) {
        consent = ConsentRecord(
            version: version,
            acceptedAt: acceptedAt,
            acknowledgedNotGuaranteed: acknowledgedNotGuaranteed
        )
    }

    func revoke() {
        consent = nil
    }
}
