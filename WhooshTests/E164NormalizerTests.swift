import Foundation
import Testing
@testable import Whoosh

/// Parameterized tests for `E164Normalizer` (NANP-only phone normalization) and
/// `GSM7Sanitizer` (rider-label sanitization), spec task 3 / Requirements 2.3,
/// 2.4, 2.9, 10.3 and contract Appendix A.3.
struct E164NormalizerTests {
    // MARK: - Valid NANP numbers normalize to +1XXXXXXXXXX

    @Test(arguments: [
        // raw input, expected normalized E.164
        ("6175550123", "+16175550123"),
        ("16175550123", "+16175550123"),
        ("+16175550123", "+16175550123"),
        ("(617) 555-0123", "+16175550123"),
        ("617-555-0123", "+16175550123"),
        ("617.555.0123", "+16175550123"),
        ("617 555 0123", "+16175550123"),
        ("+1 (617) 555-0123", "+16175550123"),
        ("1-617-555-0123", "+16175550123"),
        ("  617 555 0123  ", "+16175550123"),
        // Canadian area code 416
        ("4165550123", "+14165550123"),
    ])
    func validNumbersNormalize(raw: String, expected: String) throws {
        let result = try E164Normalizer.normalize(raw)
        #expect(result == expected)
    }

    // MARK: - Invalid numbers are rejected with a typed error

    @Test(arguments: [
        "",
        "   ",
        "abc",
    ])
    func emptyOrNoDigitsThrowsEmpty(raw: String) {
        #expect(throws: E164Error.empty) {
            _ = try E164Normalizer.normalize(raw)
        }
    }

    @Test(arguments: [
        "61755501",       // 8 digits
        "617555012",      // 9 digits
        "6175550",        // 7 digits
        "617555012345",   // 12 digits
    ])
    func wrongDigitCountThrows(raw: String) {
        #expect(throws: E164Error.wrongLength) {
            _ = try E164Normalizer.normalize(raw)
        }
    }

    @Test(arguments: [
        "+447911123456",  // UK
        "+33612345678",   // France
        "+919876543210",  // India
        "+525512345678",  // Mexico (+52)
    ])
    func nonNANPNumbersThrow(raw: String) {
        #expect(throws: E164Error.notNANP) {
            _ = try E164Normalizer.normalize(raw)
        }
    }

    @Test(arguments: [
        "1175550123",   // area code starts with 1
        "0175550123",   // area code starts with 0
        "9115550123",   // N11 area code (911)
        "4115550123",   // N11 area code (411)
        "2115550123",   // N11 area code (211)
    ])
    func invalidAreaCodeThrows(raw: String) {
        #expect(throws: E164Error.invalidAreaCode) {
            _ = try E164Normalizer.normalize(raw)
        }
    }

    @Test(arguments: [
        "6171550123",   // exchange starts with 1
        "6170550123",   // exchange starts with 0
        "6179110123",   // N11 exchange (911)
        "6174110123",   // N11 exchange (411)
    ])
    func invalidExchangeCodeThrows(raw: String) {
        #expect(throws: E164Error.invalidExchangeCode) {
            _ = try E164Normalizer.normalize(raw)
        }
    }

    @Test func leadingOneWithTenValidDigitsNormalizes() throws {
        #expect(try E164Normalizer.normalize("1 617 555 0123") == "+16175550123")
    }

    @Test func plusOneWithPunctuationNormalizes() throws {
        #expect(try E164Normalizer.normalize("+1 (617) 555.0123") == "+16175550123")
    }
}

/// GSM-7 sanitization and rider-label charset/length enforcement (spec
/// Requirement 2.9, 10.3; contract Appendix A.3 label row).
struct GSM7SanitizerTests {
    // MARK: - Message-level GSM-7 sanitization (smart punctuation → ASCII)

    @Test(arguments: [
        // smart double quotes → straight
        ("\u{201C}A\u{201D}", "\"A\""),
        // smart single quotes / apostrophe → straight
        ("it\u{2019}s", "it's"),
        ("\u{2018}x\u{2019}", "'x'"),
        // en dash / em dash → hyphen
        ("a\u{2013}b", "a-b"),
        ("a\u{2014}b", "a-b"),
        // ellipsis → three dots
        ("wait\u{2026}", "wait..."),
        // non-breaking space → normal space then collapsed
        ("a\u{00A0}b", "a b"),
    ])
    func sanitizeMapsCommonPunctuation(input: String, expected: String) {
        #expect(GSM7Sanitizer.sanitize(input) == expected)
    }

    @Test(arguments: [
        // emoji and other non-GSM characters are stripped
        ("hi \u{1F600}", "hi"),
        ("a\u{1F6B4}b", "ab"),
    ])
    func sanitizeStripsEmoji(input: String, expected: String) {
        #expect(GSM7Sanitizer.sanitize(input) == expected)
    }

    @Test func sanitizeCollapsesWhitespace() {
        #expect(GSM7Sanitizer.sanitize("a   b\t\tc") == "a b c")
    }

    @Test func sanitizeTrimsLeadingAndTrailingWhitespace() {
        #expect(GSM7Sanitizer.sanitize("   hello   ") == "hello")
    }

    @Test func sanitizeOutputIsGSM7Only() {
        let out = GSM7Sanitizer.sanitize("\u{00C1}lex \u{201D}A\u{201D}") // "Álex ”A”"
        #expect(GSM7Sanitizer.isGSM7(out))
    }

    // MARK: - Rider label: charset, collapse, 20-char limit

    @Test(arguments: [
        ("Alex", "Alex"),
        ("Mary Jane", "Mary Jane"),
        ("O'Brien", "O'Brien"),
        ("Jean-Luc", "Jean-Luc"),
        ("J.R.", "J.R."),
        ("Anne  Marie", "Anne Marie"),   // collapsed whitespace
        ("  Alex  ", "Alex"),            // trimmed
    ])
    func labelValidCharactersPreserved(input: String, expected: String) {
        #expect(GSM7Sanitizer.riderLabel(input) == expected)
    }

    @Test func labelStripsDisallowedCharacters() {
        // Letters, digits, space, '.', '\'', '-' only; others removed.
        #expect(GSM7Sanitizer.riderLabel("Alex!@#$%") == "Alex")
        #expect(GSM7Sanitizer.riderLabel("A+B=C") == "ABC")
    }

    @Test func labelMapsSmartPunctuationThenRestrictsCharset() {
        // Contract A.3: "Álex ”A”" → non-GSM replaced/stripped, collapsed.
        // Á is not in the label charset (letters means ASCII a-z/A-Z here), so
        // it is dropped; smart quotes are not in the charset either.
        let out = GSM7Sanitizer.riderLabel("\u{00C1}lex \u{201D}A\u{201D}")
        #expect(out == "lex A")
    }

    @Test func labelEnforces20CharacterLimit() {
        let long = "Abcdefghij Klmnopqrstuvwxyz"
        let out = GSM7Sanitizer.riderLabel(long)
        #expect(out.count == 20)
        #expect(out == "Abcdefghij Klmnopqrs")
    }

    @Test func labelExactly20CharsIsKept() {
        let twenty = "Abcdefghij Klmnopqrs" // 20 chars
        #expect(twenty.count == 20)
        #expect(GSM7Sanitizer.riderLabel(twenty) == twenty)
    }

    @Test func labelEmptyAfterSanitizationIsEmpty() {
        #expect(GSM7Sanitizer.riderLabel("\u{1F600}\u{1F601}") == "")
    }
}
