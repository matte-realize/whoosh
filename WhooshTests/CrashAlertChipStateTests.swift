import Foundation
import Testing
@testable import Whoosh

/// Tests for the crash-alert chip and log status mappings (crash-response task
/// 22, Requirements 11.5, 11.7, 18.6). These verify the pure icon + text
/// mappings — every state has a non-empty title and a symbol, and the on/off
/// chip flips correctly — without rendering SwiftUI.
@MainActor
struct CrashAlertChipStateTests {
    // MARK: - On/off chip (Requirement 18.6)

    @Test func chipStateFromBool() {
        #expect(CrashAlertChipState(isOn: true) == .on)
        #expect(CrashAlertChipState(isOn: false) == .off)
    }

    @Test func chipTitlesAreDistinctAndHonest() {
        #expect(CrashAlertChipState.on.title == "Crash alerts on")
        #expect(CrashAlertChipState.off.title == "Crash alerts off")
    }

    @Test func chipSymbolsDiffer() {
        #expect(CrashAlertChipState.on.systemImage != CrashAlertChipState.off.systemImage)
        #expect(!CrashAlertChipState.on.systemImage.isEmpty)
        #expect(!CrashAlertChipState.off.systemImage.isEmpty)
    }

    // MARK: - Record state mapping (Requirement 11.5)

    @Test func everyRecordStateHasTitleAndSymbol() {
        for state in CrashEventState.allCases {
            let title = CrashAlertLogDisplay.title(for: state, isDrill: false)
            let symbol = CrashAlertLogDisplay.systemImage(for: state, isDrill: false)
            #expect(!title.isEmpty)
            #expect(!symbol.isEmpty)
        }
    }

    @Test func drillRecordIsLabelledDemo() {
        // Regardless of underlying state, a drill reads as a demo (Requirement 19.9).
        let title = CrashAlertLogDisplay.title(for: .sent, isDrill: true)
        #expect(title.lowercased().contains("demo"))
    }

    @Test func sentRecordReadsAsSent() {
        #expect(CrashAlertLogDisplay.title(for: .sent, isDrill: false) == "Alert sent")
    }

    @Test func cancelledRecordMentionsImOk() {
        let title = CrashAlertLogDisplay.title(for: .cancelled, isDrill: false)
        #expect(title.lowercased().contains("cancelled"))
    }

    // MARK: - Attempt status mapping (Requirement 11.2, 11.7)

    @Test func everyAttemptStatusHasTitleAndSymbol() {
        for status in AttemptStatus.allCases {
            let title = CrashAlertLogDisplay.title(for: status)
            let symbol = CrashAlertLogDisplay.systemImage(for: status)
            #expect(!title.isEmpty)
            #expect(!symbol.isEmpty)
        }
    }

    @Test func deliveredStatusReadsAsDelivered() {
        #expect(CrashAlertLogDisplay.title(for: .delivered) == "Delivered")
    }

    // MARK: - Contact verification display (Requirement 2.5)

    @Test func everyVerificationStateHasTitleAndSymbol() {
        for verification in ContactVerification.allCases {
            let title = ContactVerificationDisplay.title(for: verification)
            let symbol = ContactVerificationDisplay.systemImage(for: verification)
            #expect(!title.isEmpty)
            #expect(!symbol.isEmpty)
        }
    }

    @Test func reachableVerificationReadsAsReachable() {
        #expect(ContactVerificationDisplay.title(for: .reachable) == "Reachable")
    }
}
