// HapticMessage.swift
// Shared by the iPhone target and the watch target of the throwaway spike.
// Foundation only, so it type-checks without Xcode: `swiftc -typecheck HapticMessage.swift`.
//
// WatchConnectivity only carries property-list values, so each message is a plain dictionary
// with these keys.

import Foundation

/// The haptic patterns the spike can request. Names match `WKHapticType` cases on the watch.
enum HapticPattern: String, CaseIterable, Sendable {
    case notification
    case directionUp
    case directionDown
    case success
    case failure
    case retry
    case start
    case stop
    case click
}

/// A request sent from the iPhone to the watch.
struct HapticRequest: Equatable, Sendable {
    let sequence: Int
    let pattern: HapticPattern
    /// Phone clock when the request was created. For the log only: the phone and watch clocks
    /// are not guaranteed to agree, so do not subtract them. Use the round trip instead.
    let sentAt: TimeInterval

    init(sequence: Int, pattern: HapticPattern, sentAt: TimeInterval = Date().timeIntervalSince1970) {
        self.sequence = sequence
        self.pattern = pattern
        self.sentAt = sentAt
    }

    init?(dictionary: [String: Any]) {
        guard
            let sequence = dictionary["seq"] as? Int,
            let raw = dictionary["pattern"] as? String,
            let pattern = HapticPattern(rawValue: raw),
            let sentAt = dictionary["sentAt"] as? Double
        else { return nil }
        self.init(sequence: sequence, pattern: pattern, sentAt: sentAt)
    }

    var dictionary: [String: Any] {
        ["seq": sequence, "pattern": pattern.rawValue, "sentAt": sentAt]
    }
}

/// The watch's reply once it has played the haptic.
struct HapticAck: Equatable, Sendable {
    let sequence: Int
    /// Watch clock when the request arrived (log only, see `HapticRequest.sentAt`).
    let receivedAt: TimeInterval
    /// Whether the watch's workout session was running when the haptic played.
    let workoutActive: Bool

    init(sequence: Int, receivedAt: TimeInterval, workoutActive: Bool) {
        self.sequence = sequence
        self.receivedAt = receivedAt
        self.workoutActive = workoutActive
    }

    init?(dictionary: [String: Any]) {
        guard
            let sequence = dictionary["seq"] as? Int,
            let receivedAt = dictionary["receivedAt"] as? Double,
            let workoutActive = dictionary["workoutActive"] as? Bool
        else { return nil }
        self.init(sequence: sequence, receivedAt: receivedAt, workoutActive: workoutActive)
    }

    var dictionary: [String: Any] {
        ["seq": sequence, "receivedAt": receivedAt, "workoutActive": workoutActive]
    }
}
