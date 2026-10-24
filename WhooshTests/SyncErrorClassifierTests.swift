import Testing
@testable import Whoosh

/// Tests for the pure `SyncErrorClassifier` (Requirement 12.22).
struct SyncErrorClassifierTests {
    @Test func checkViolationIsPermanent() {
        #expect(SyncErrorClassifier.classify(postgrestCode: "23514") == .permanent)
    }

    @Test func permissionDeniedIsAuthRetryable() {
        #expect(SyncErrorClassifier.classify(postgrestCode: "42501") == .authRetryable)
    }

    @Test func unknownCodeIsRetryable() {
        #expect(SyncErrorClassifier.classify(postgrestCode: "08006") == .retryable)
    }

    @Test func missingCodeIsRetryable() {
        #expect(SyncErrorClassifier.classify(postgrestCode: nil) == .retryable)
    }
}
