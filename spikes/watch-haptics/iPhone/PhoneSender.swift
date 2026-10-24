// PhoneSender.swift (iPhone target)
// Throwaway spike code. NOT compiled or run yet: it needs Xcode and the iOS SDK.
// Set the target's Swift Language Mode to 5 for the spike to avoid strict-concurrency noise.

import Foundation
import Observation
import WatchConnectivity

@Observable
final class PhoneSender: NSObject, WCSessionDelegate {
    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
    }

    var log: [LogLine] = []
    var status = "starting"
    private(set) var roundTripsMs: [Int] = []
    private var sequence = 0

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            status = "WatchConnectivity not supported"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Median round trip in milliseconds, measured on the phone clock only. Nil with no replies yet.
    var medianRoundTripMs: Int? {
        guard !roundTripsMs.isEmpty else { return nil }
        let sorted = roundTripsMs.sorted()
        return sorted[sorted.count / 2]
    }

    func send(_ pattern: HapticPattern) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            append("not activated yet")
            return
        }
        sequence += 1
        let request = HapticRequest(sequence: sequence, pattern: pattern)
        let started = Date()

        session.sendMessage(request.dictionary, replyHandler: { [weak self] reply in
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            let ack = HapticAck(dictionary: reply)
            DispatchQueue.main.async {
                self?.roundTripsMs.append(elapsedMs)
                let workout = ack.map { $0.workoutActive ? "workout on" : "workout off" } ?? "bad reply"
                self?.append("#\(request.sequence) \(pattern.rawValue): reply in \(elapsedMs) ms, \(workout)")
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.append("#\(request.sequence) \(pattern.rawValue): FAILED \(error.localizedDescription)")
            }
        })
        append("#\(request.sequence) \(pattern.rawValue): sent (reachable: \(session.isReachable))")
    }

    func clearLog() {
        log.removeAll()
        roundTripsMs.removeAll()
    }

    private func append(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.insert(LogLine(text: "\(stamp)  \(text)"), at: 0)
    }

    private func refreshStatus(_ session: WCSession) {
        status = "paired: \(session.isPaired), watch app installed: \(session.isWatchAppInstalled), reachable: \(session.isReachable)"
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error {
                self?.status = "activation failed: \(error.localizedDescription)"
            } else {
                self?.refreshStatus(session)
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.refreshStatus(session) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
