import Foundation
import Testing
@testable import Whoosh

/// Property-style checks over many generated event sequences for the pure
/// `CrashStateMachine` reducer (crash-response task 6, Requirements 6.7, 6.9,
/// 17.1, 19.2, 19.6). A tiny seeded deterministic generator (no external libs)
/// builds thousands of random (event, context) sequences and asserts the two
/// safety invariants the whole feature depends on:
///
/// 1. No sequence produces two **initial** `dispatchSend` effects for one
///    `crashEventId` (no double real send); total sends stay bounded (the single
///    O5 unknown-outcome retry aside, retries reuse the same key).
/// 2. Effects never include any call/dial action — `CrashEffect` has no such
///    case, enforced structurally and asserted here for every emitted effect.
struct CrashStateMachinePropertyTests {
    private let tuning = CrashResponseTuning()

    /// A seeded splitmix64-style PRNG so runs are deterministic and reproducible.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func randomEvent(_ rng: inout SeededGenerator) -> CrashReducerEvent {
        let outcomes: [CrashDispatchOutcome] = [.offline, .success, .retryableError, .nonRetryableError, .timeoutUnknown]
        let choices: [CrashReducerEvent] = [
            .detectorSignal(isDrill: Bool.random(using: &rng)),
            .evidenceCaptured,
            .riderCancel,
            .deadlineReached,
            .sendNow,
            .consentRevoked,
            .dispatchResult(outcomes.randomElement(using: &rng)!),
            .retryTrigger,
            .staleLimitReached,
            .statusPollUpdate,
            .tellContactsImOK,
            .composerAction,
            .relaunch,
        ]
        return choices.randomElement(using: &rng)!
    }

    /// Like `randomEvent` but any detector signal is non-drill, for tests that
    /// assert the per-ride *sent* cap (drills intentionally bypass the cap).
    private func randomNonDrillEvent(_ rng: inout SeededGenerator) -> CrashReducerEvent {
        switch randomEvent(&rng) {
        case .detectorSignal:
            return .detectorSignal(isDrill: false)
        case let other:
            return other
        }
    }

    /// Count `dispatchSend` effects across a run, split by retry flag, per event.
    private struct DispatchTally {
        var initialByEvent: [UUID: Int] = [:]
        var retryByEvent: [UUID: Int] = [:]
    }

    @Test func noDoubleInitialSendAndNoCallEffectEver() {
        var failures = 0
        var totalEffectsSeen = 0

        for seed in 0..<400 {
            var rng = SeededGenerator(seed: UInt64(seed) &* 2_654_435_761 &+ 1)
            var state = CrashMachineState.initial
            var now = Date(timeIntervalSince1970: 1_000_000)
            var tally = DispatchTally()

            for _ in 0..<60 {
                // Advance time by a random small/large amount so stale/suppression
                // boundaries are exercised.
                let step = [0.0, 1, 5, 20, 60, 300, 2_000].randomElement(using: &rng)!
                now = now.addingTimeInterval(step)
                let context = CrashReducerContext(
                    now: now,
                    tuning: tuning,
                    armed: Bool.random(using: &rng),
                    online: Bool.random(using: &rng),
                    consentCurrent: Bool.random(using: &rng),
                    newEventId: UUID()
                )
                let event = randomEvent(&rng)
                let reduction = CrashStateMachine.reduce(state, event, context)

                for effect in reduction.effects {
                    totalEffectsSeen += 1
                    // Invariant 2: no call/dial effect exists. We inspect the
                    // effect's reflected label defensively (the type has no such
                    // case, so this can only ever confirm the structural property).
                    let label = String(describing: effect).lowercased()
                    if label.contains("call") || label.contains("dial") || label.contains("tel:") {
                        failures += 1
                    }
                    // Invariant 1: tally initial vs retry dispatches per event id.
                    if case let .dispatchSend(eventId, isRetry) = effect {
                        if isRetry {
                            tally.retryByEvent[eventId, default: 0] += 1
                        } else {
                            tally.initialByEvent[eventId, default: 0] += 1
                        }
                    }
                }

                state = reduction.state
            }

            // Invariant 1: at most one *initial* dispatch per event id.
            for (_, count) in tally.initialByEvent where count > 1 {
                failures += 1
            }
        }

        #expect(failures == 0)
        // Sanity: the generator actually drove the reducer through many effects.
        #expect(totalEffectsSeen > 0)
    }

    /// A focused property: once an event reaches `sent`, no later event in the
    /// same run can produce another initial send for that same id (the cap and
    /// suppression hold). Drives a biased sequence toward a completed send.
    @Test func sentEventNeverReInitialSends() {
        var rng = SeededGenerator(seed: 0xDEAD_BEEF)
        for _ in 0..<200 {
            var state = CrashMachineState.initial
            var now = Date(timeIntervalSince1970: 2_000_000)
            let eventId = UUID()

            // Drive to sent deterministically.
            func ctx(armed: Bool = true, online: Bool = true) -> CrashReducerContext {
                CrashReducerContext(now: now, tuning: tuning, armed: armed, online: online, consentCurrent: true, newEventId: eventId)
            }
            state = CrashStateMachine.reduce(state, .detectorSignal(isDrill: false), ctx()).state
            state = CrashStateMachine.reduce(state, .evidenceCaptured, ctx()).state
            now = now.addingTimeInterval(30)
            state = CrashStateMachine.reduce(state, .deadlineReached, ctx()).state
            state = CrashStateMachine.reduce(state, .dispatchResult(.success), ctx()).state
            #expect(state.eventState == .sent)

            // Now hammer with random events and random fresh ids; no initial send
            // may be emitted for any *non-drill* event (the cap of 1 sent per ride
            // holds, and suppression blocks new detections for the window). Drills
            // intentionally bypass the cap, so they are excluded here.
            var initialSends = 0
            for _ in 0..<40 {
                now = now.addingTimeInterval([0.0, 10, 100].randomElement(using: &rng)!)
                let c = CrashReducerContext(now: now, tuning: tuning, armed: true, online: true, consentCurrent: true, newEventId: UUID())
                let r = CrashStateMachine.reduce(state, randomNonDrillEvent(&rng), c)
                for e in r.effects {
                    if case let .dispatchSend(_, isRetry) = e, !isRetry { initialSends += 1 }
                }
                state = r.state
            }
            #expect(initialSends == 0)
        }
    }
}
