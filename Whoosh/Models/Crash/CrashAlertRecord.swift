import Foundation

/// The local, persistable record of a crash event and its send attempts
/// (spec Requirement 11.1). The pure domain shape; the SwiftData `@Model`
/// entity (a later task) encodes this behind `CrashAlertRepository`.
///
/// Stores the rendered text and template version, both location snapshots, and
/// the ordered per-recipient attempts. It **never** stores a full phone number
/// — attempts carry only the masked last-2-digits (Requirement 11.3).
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
struct CrashAlertRecord: Equatable, Codable, Sendable, Identifiable {
    /// The record id mirrors the event id (= `crashEventId`).
    var id: UUID { event.id }
    var event: CrashEvent
    /// A newer fix captured at send time, when one existed (Requirement 7.3).
    var locationAtSend: LocationSnapshot?
    var templateVersion: Int
    var renderedText: String
    var attempts: [AlertAttempt]
    let createdAt: Date
    var updatedAt: Date

    init(
        event: CrashEvent,
        locationAtSend: LocationSnapshot?,
        templateVersion: Int,
        renderedText: String,
        attempts: [AlertAttempt],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.event = event
        self.locationAtSend = locationAtSend
        self.templateVersion = templateVersion
        self.renderedText = renderedText
        self.attempts = attempts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
