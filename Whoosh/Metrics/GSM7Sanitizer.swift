import Foundation

/// Pure, Foundation-only GSM-7 sanitizer (spec task 3, Requirement 10.3).
///
/// Any non-GSM character forces UCS-2 encoding and shrinks SMS segments from 153
/// to 67 characters (cost), so message text and the rider label are restricted
/// to an ASCII-safe subset. This sanitizer:
/// - maps common "smart" punctuation (curly quotes, en/em dashes, ellipsis,
///   non-breaking space) to plain ASCII;
/// - strips unsupported characters and emoji;
/// - collapses runs of whitespace to a single space and trims the ends.
///
/// `riderLabel(_:)` additionally restricts to the rider-label charset
/// (ASCII letters, digits, space, `.`, `'`, `-`) and enforces the 20-character
/// limit (Requirement 2.9).
///
/// Conservative definition: "GSM-7" here is the printable ASCII range
/// (`0x20`–`0x7E`) plus newline, which is a strict subset of the real GSM-7
/// basic set — guaranteeing `isGSM7` stays consistent with the output.
enum GSM7Sanitizer {
    /// The rider-label charset: ASCII letters, digits, space, `.`, `'`, `-`.
    private static let labelAllowedPunctuation: Set<Character> = [" ", ".", "'", "-"]

    private static let maxRiderLabelLength = 20

    /// Map of common non-ASCII punctuation to an ASCII replacement.
    private static let punctuationMap: [Character: String] = [
        "\u{2018}": "'",   // left single quote
        "\u{2019}": "'",   // right single quote / apostrophe
        "\u{201A}": "'",   // single low-9 quote
        "\u{201C}": "\"",  // left double quote
        "\u{201D}": "\"",  // right double quote
        "\u{201E}": "\"",  // double low-9 quote
        "\u{2013}": "-",   // en dash
        "\u{2014}": "-",   // em dash
        "\u{2212}": "-",   // minus sign
        "\u{2026}": "...", // ellipsis
        "\u{00A0}": " ",   // non-breaking space
    ]

    /// Sanitize arbitrary message text to GSM-7-safe ASCII with collapsed,
    /// trimmed whitespace.
    static func sanitize(_ input: String) -> String {
        var mapped = ""
        mapped.reserveCapacity(input.count)
        for character in input {
            if let replacement = punctuationMap[character] {
                mapped.append(replacement)
            } else if isGSM7(character) {
                mapped.append(character)
            }
            // Non-GSM, unmapped characters (emoji, accents) are stripped.
        }
        return collapseWhitespace(mapped)
    }

    /// Sanitize and restrict to the rider-label charset, then cap at 20 chars.
    static func riderLabel(_ input: String) -> String {
        // First map smart punctuation to ASCII so e.g. a curly apostrophe
        // becomes a straight one before the charset filter runs.
        var mapped = ""
        mapped.reserveCapacity(input.count)
        for character in input {
            if let replacement = punctuationMap[character] {
                mapped.append(replacement)
            } else {
                mapped.append(character)
            }
        }

        let filtered = String(mapped.filter(isLabelAllowed))
        let collapsed = collapseWhitespace(filtered)
        if collapsed.count <= maxRiderLabelLength {
            return collapsed
        }
        return String(collapsed.prefix(maxRiderLabelLength))
    }

    /// Whether every character of `string` is GSM-7-safe (per this type's
    /// conservative definition).
    static func isGSM7(_ string: String) -> Bool {
        string.allSatisfy(isGSM7)
    }

    // MARK: - Private helpers

    private static func isGSM7(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }
        let value = scalar.value
        // Printable ASCII, plus newline and carriage return.
        return (0x20...0x7E).contains(value) || value == 0x0A || value == 0x0D
    }

    private static func isLabelAllowed(_ character: Character) -> Bool {
        if character.isASCII, character.isLetter { return true }
        if character.isASCII, character.isNumber { return true }
        return labelAllowedPunctuation.contains(character)
    }

    /// Collapse any run of whitespace to a single space and trim the ends.
    private static func collapseWhitespace(_ input: String) -> String {
        let components = input.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        return components.joined(separator: " ")
    }
}
