// Checks for Shared/HapticMessage.swift. Run from spikes/watch-haptics:
//   swiftc -swift-version 6 Shared/HapticMessage.swift Checks/main.swift -o /tmp/hapticcheck && /tmp/hapticcheck
import Foundation

nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ name: String) {
    print(ok ? "PASS  \(name)" : "FAIL  \(name)")
    if !ok { failures += 1 }
}

// Request round trip through a property-list-style dictionary, for every pattern.
for pattern in HapticPattern.allCases {
    let request = HapticRequest(sequence: 7, pattern: pattern, sentAt: 1234.5)
    check(HapticRequest(dictionary: request.dictionary) == request, "request round trip: \(pattern.rawValue)")
}

// Ack round trip.
let ack = HapticAck(sequence: 3, receivedAt: 99.25, workoutActive: true)
check(HapticAck(dictionary: ack.dictionary) == ack, "ack round trip")

// Bad input must return nil, never crash.
check(HapticRequest(dictionary: [:]) == nil, "empty dictionary is rejected")
check(HapticRequest(dictionary: ["seq": 1, "pattern": "nope", "sentAt": 1.0]) == nil, "unknown pattern is rejected")
check(HapticRequest(dictionary: ["seq": "1", "pattern": "click", "sentAt": 1.0]) == nil, "wrong seq type is rejected")
check(HapticAck(dictionary: ["seq": 1]) == nil, "incomplete ack is rejected")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
