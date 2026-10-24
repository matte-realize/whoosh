import Foundation

/// Typed errors from `E164Normalizer` (spec Requirement 2.3/2.4) so callers can
/// map each to an inline, actionable message.
enum E164Error: Error, Equatable, Sendable {
    /// No digits were present.
    case empty
    /// Not a 10-digit NANP number (after stripping a leading country code).
    case wrongLength
    /// A non-`+1` country code was given (non-US/CA; out of scope in v1).
    case notNANP
    /// The 3-digit area code (NPA) is not NANP-valid (first digit 2–9, not N11).
    case invalidAreaCode
    /// The 3-digit exchange code (NXX) is not NANP-valid (first digit 2–9, not N11).
    case invalidExchangeCode
}

/// Pure, Foundation-only US/Canada (NANP) phone normalizer (spec task 3).
///
/// Strips punctuation and an optional leading `1`/`+1`, then validates the
/// 10-digit NANP format:
/// - a leading `+` must be `+1` (any other country code ⇒ `notNANP`);
/// - the result must be exactly 10 digits (else `wrongLength`);
/// - the area code (NPA) first digit is 2–9 and it is not an N11 pattern
///   (`x11`) — else `invalidAreaCode`;
/// - the exchange code (NXX) first digit is 2–9 and it is not an N11 pattern
///   — else `invalidExchangeCode`.
///
/// On success returns canonical `+1XXXXXXXXXX`.
enum E164Normalizer {
    static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // A leading '+' with a non-'1' country code is explicitly non-NANP.
        if trimmed.hasPrefix("+") {
            let afterPlus = trimmed.dropFirst()
            let digits = afterPlus.filter(\.isNumber)
            guard digits.isEmpty == false else { throw E164Error.empty }
            guard digits.first == "1" else { throw E164Error.notNANP }
            return try validateNANP(String(digits.dropFirst()))
        }

        var digits = trimmed.filter(\.isNumber)
        guard digits.isEmpty == false else { throw E164Error.empty }

        // A leading '1' is the NANP country code when it yields 10 more digits.
        if digits.count == 11 {
            guard digits.first == "1" else { throw E164Error.notNANP }
            digits.removeFirst()
        } else if digits.count > 11 {
            throw E164Error.wrongLength
        }

        return try validateNANP(digits)
    }

    /// Validate a bare 10-digit NANP national number and return `+1` + it.
    private static func validateNANP(_ national: String) throws -> String {
        guard national.count == 10 else { throw E164Error.wrongLength }
        let chars = Array(national)

        let areaFirst = chars[0]
        let areaSecond = chars[1]
        let areaThird = chars[2]
        // NPA: first digit 2–9; not N11 (second == third == '1').
        guard ("2"..."9").contains(areaFirst) else { throw E164Error.invalidAreaCode }
        if areaSecond == "1", areaThird == "1" { throw E164Error.invalidAreaCode }

        let exchangeFirst = chars[3]
        let exchangeSecond = chars[4]
        let exchangeThird = chars[5]
        // NXX: first digit 2–9; not N11.
        guard ("2"..."9").contains(exchangeFirst) else { throw E164Error.invalidExchangeCode }
        if exchangeSecond == "1", exchangeThird == "1" { throw E164Error.invalidExchangeCode }

        return "+1" + national
    }
}
