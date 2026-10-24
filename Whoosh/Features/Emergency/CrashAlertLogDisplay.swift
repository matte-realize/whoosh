import SwiftUI

/// Pure icon + text mappings for the crash alert log (spec Requirement 11.5,
/// 11.7 — status is always conveyed with icon + text, never color alone).
///
/// Both the overall record disposition and each per-recipient attempt status
/// map to a plain, honest title and an SF Symbol. The static helpers are
/// Foundation-level enough to assert in unit tests; the `tint` is decorative.
enum CrashAlertLogDisplay {
    // MARK: - Overall record state

    /// Plain-language title for a record's overall state (Requirement 11.5).
    static func title(for state: CrashEventState, isDrill: Bool) -> String {
        if isDrill { return "Demo — not real" }
        switch state {
        case .idle, .detected, .countdown: return "In progress"
        case .cancelled: return "Cancelled — you tapped I'm OK"
        case .sending: return "Sending…"
        case .sent: return "Alert sent"
        case .queuedOffline: return "Waiting to send"
        case .failed: return "Couldn't send"
        case .fallbackPrompted: return "Not sent — text manually"
        case .recoveryPrompted: return "Needs your choice"
        case .stale: return "Not sent"
        }
    }

    static func systemImage(for state: CrashEventState, isDrill: Bool) -> String {
        if isDrill { return "theatermasks" }
        switch state {
        case .idle, .detected, .countdown, .sending: return "clock"
        case .cancelled: return "hand.raised.fill"
        case .sent: return "checkmark.circle.fill"
        case .queuedOffline: return "wifi.slash"
        case .failed, .fallbackPrompted, .stale: return "exclamationmark.triangle.fill"
        case .recoveryPrompted: return "questionmark.circle"
        }
    }

    static func tint(for state: CrashEventState, isDrill: Bool) -> Color {
        if isDrill { return Theme.Colors.textSecondary }
        switch state {
        case .sent: return Theme.Colors.positive
        case .cancelled: return Theme.Colors.textSecondary
        case .failed, .fallbackPrompted, .stale: return Theme.Palette.alert
        case .queuedOffline, .recoveryPrompted: return Theme.Palette.amber
        default: return Theme.Colors.textSecondary
        }
    }

    // MARK: - Per-recipient attempt status (Requirement 11.2, 11.7)

    static func title(for status: AttemptStatus) -> String {
        switch status {
        case .queued: return "Queued"
        case .sent: return "Sent"
        case .delivered: return "Delivered"
        case .undelivered: return "Not delivered"
        case .failed: return "Failed"
        case .rejected: return "Not sent"
        }
    }

    static func systemImage(for status: AttemptStatus) -> String {
        switch status {
        case .queued: return "clock"
        case .sent: return "paperplane.fill"
        case .delivered: return "checkmark.circle.fill"
        case .undelivered: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .rejected: return "nosign"
        }
    }

    static func tint(for status: AttemptStatus) -> Color {
        switch status {
        case .delivered, .sent: return Theme.Colors.positive
        case .queued: return Theme.Colors.textSecondary
        case .undelivered, .failed, .rejected: return Theme.Palette.alert
        }
    }
}
