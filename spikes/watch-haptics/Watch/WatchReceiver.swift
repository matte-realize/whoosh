// WatchReceiver.swift (watchOS target)
// Throwaway spike code. NOT compiled or run yet: it needs Xcode and the watchOS SDK.
// Set the target's Swift Language Mode to 5 for the spike to avoid strict-concurrency noise.
//
// Needs: the HealthKit capability on the watch target, and these Info.plist keys on it:
//   NSHealthShareUsageDescription, NSHealthUpdateUsageDescription
// (Starting a workout session asks for permission to share workouts.)

import Foundation
import HealthKit
import Observation
import WatchConnectivity
import WatchKit

extension HapticPattern {
    var watchHaptic: WKHapticType {
        switch self {
        case .notification: return .notification
        case .directionUp: return .directionUp
        case .directionDown: return .directionDown
        case .success: return .success
        case .failure: return .failure
        case .retry: return .retry
        case .start: return .start
        case .stop: return .stop
        case .click: return .click
        }
    }
}

@Observable
final class WatchReceiver: NSObject, WCSessionDelegate, HKWorkoutSessionDelegate {
    var lastPattern = "none yet"
    var received = 0
    var workoutState = "off"
    var connection = "starting"

    private let store = HKHealthStore()
    private var workout: HKWorkoutSession?

    var workoutActive: Bool { workoutState == "running" }

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            connection = "WatchConnectivity not supported"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Plays a pattern on the watch itself, with no phone involved. Used to feel each pattern.
    func playLocally(_ pattern: HapticPattern) {
        WKInterfaceDevice.current().play(pattern.watchHaptic)
    }

    // MARK: Workout session (the only way a watch app keeps running with the wrist down)

    func startWorkout() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            workoutState = "HealthKit unavailable"
            return
        }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .cycling
            configuration.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            session.delegate = self
            workout = session
            session.startActivity(with: Date())
        } catch {
            workoutState = "error: \(error.localizedDescription)"
        }
    }

    /// Ends the session without a builder, so nothing is saved to the Health app.
    func stopWorkout() {
        workout?.end()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            switch toState {
            case .running: self?.workoutState = "running"
            case .ended, .stopped: self?.workoutState = "off"
            case .paused: self?.workoutState = "paused"
            default: self?.workoutState = "state \(toState.rawValue)"
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.workoutState = "failed: \(error.localizedDescription)"
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.connection = error.map { "activation failed: \($0.localizedDescription)" }
                ?? "activated, reachable: \(session.isReachable)"
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.connection = "reachable: \(session.isReachable)"
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let receivedAt = Date().timeIntervalSince1970
        guard let request = HapticRequest(dictionary: message) else {
            replyHandler([:])
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            WKInterfaceDevice.current().play(request.pattern.watchHaptic)
            lastPattern = request.pattern.rawValue
            received += 1
            let ack = HapticAck(sequence: request.sequence, receivedAt: receivedAt, workoutActive: workoutActive)
            replyHandler(ack.dictionary)
        }
    }
}
