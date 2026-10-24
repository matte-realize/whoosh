import Foundation

/// The wire privacy allowlist (watch-companion design "Privacy and network
/// invariants"; Requirement 19.1, 19.2, test PR-1).
///
/// The wire payload may carry **enums, rounded numbers, booleans, and
/// identifiers only — no free-form text and no sensitive field**. This checker
/// serializes a value to JSON and walks it, failing on:
/// 1. any object key that names a forbidden concept (coordinate, latitude,
///    longitude, route, name, phone/number, message/text, address, …), or
/// 2. any string value longer than the short-code limit (free text), with an
///    exception for identifier-shaped strings (UUIDs / short codes).
///
/// It is Foundation-only and pure so it runs in `swift test` and can be reused
/// by the phone-side PR-1 test over the same encoded payloads.
public enum WireAllowlist {
    /// Maximum length of an ordinary short-code string value (enum raw values,
    /// state codes). Longer strings are only allowed if they are
    /// identifier-shaped (see `isIdentifierShaped`).
    public static let shortCodeMaxLength = 40

    /// Maximum length of an identifier-shaped string (a UUID is 36 chars; allow
    /// a little headroom).
    public static let identifierMaxLength = 64

    /// Forbidden substrings in an object key (case-insensitive). A key whose
    /// name contains any of these would carry a sensitive field. The terms are
    /// chosen to catch sensitive concepts (a contact's name or number, a
    /// coordinate, a route, message text, footage references) **without**
    /// colliding with the allowlisted short-code fields (for example
    /// `patternName` names a haptic pattern code, not a person; `rideId` and
    /// `eventId` are identifiers).
    public static let forbiddenKeySubstrings: [String] = [
        "coordinate", "latitude", "longitude",
        "route", "polyline", "location", "geo",
        "contactname", "contactnumber", "phonenumber", "msisdn",
        "firstname", "lastname", "fullname", "displayname",
        "message", "messagetext", "freetext", "address", "email",
        "thumbnail", "footage", "frameid", "clipid",
    ]

    /// A violation found while walking a payload.
    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        public enum Kind: Equatable, Sendable {
            case forbiddenKey(String)
            case stringTooLong(key: String, length: Int)
        }
        public var kind: Kind
        public var path: String

        public var description: String {
            switch kind {
            case let .forbiddenKey(key):
                return "forbidden key '\(key)' at \(path)"
            case let .stringTooLong(key, length):
                return "string too long (\(length) chars) at \(path).\(key) — looks like free text"
            }
        }
    }

    /// Validate a `Codable` wire payload. Returns all violations (empty = OK).
    public nonisolated static func validate<P: Encodable>(_ value: P) -> [Violation] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard
            let data = try? encoder.encode(value),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return []
        }
        var violations: [Violation] = []
        walk(object, key: "", path: "root", into: &violations)
        return violations
    }

    // MARK: - Walking

    private nonisolated static func walk(
        _ node: Any,
        key: String,
        path: String,
        into violations: inout [Violation]
    ) {
        switch node {
        case let dict as [String: Any]:
            for (childKey, childValue) in dict {
                if let bad = forbiddenKey(childKey) {
                    violations.append(Violation(kind: .forbiddenKey(bad), path: path))
                }
                walk(childValue, key: childKey, path: "\(path).\(childKey)", into: &violations)
            }
        case let array as [Any]:
            for (index, element) in array.enumerated() {
                walk(element, key: key, path: "\(path)[\(index)]", into: &violations)
            }
        case let string as String:
            if !isAllowedString(string) {
                violations.append(
                    Violation(kind: .stringTooLong(key: key, length: string.count), path: path)
                )
            }
        default:
            // Numbers and booleans are always allowed.
            break
        }
    }

    /// The matched forbidden substring, if the key is disallowed.
    private nonisolated static func forbiddenKey(_ key: String) -> String? {
        let lower = key.lowercased()
        for substring in forbiddenKeySubstrings where lower.contains(substring) {
            return key
        }
        return nil
    }

    /// A string value is allowed if it is a short code, or an identifier-shaped
    /// string within the identifier limit.
    private nonisolated static func isAllowedString(_ string: String) -> Bool {
        if string.count <= shortCodeMaxLength { return true }
        if string.count <= identifierMaxLength, isIdentifierShaped(string) { return true }
        return false
    }

    /// Identifier-shaped: only hex digits, dashes, dots, and underscores (a
    /// UUID, a build string, a capability code). No spaces or sentence
    /// punctuation — so it cannot be free text.
    private nonisolated static func isIdentifierShaped(_ string: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF-._")
        return string.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
