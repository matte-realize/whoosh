# Whoosh — Team Plan (3 people)

A hackathon-scoped split of Whoosh across three owners. The goal is **parallelism with a
working demo at every checkpoint**. The seams defined in the iOS spec (`HazardDetector`,
`AlertManager`, `HazardDetection`) are the contract that lets the three workstreams proceed
independently and integrate late.

## Roles

| Person | Role | Owns |
| ------ | ---- | ---- |
| **You** | iOS App | The native SwiftUI app: ride recording, GPS, map, persistence, UI, alert playback, and the integration seams. This is the demo surface. |
| **Teammate B** | Vision / Detection | On-device rear-camera vehicle detection: dataset, model, and the `HazardDetector` implementation that emits `HazardDetection` events. |
| **Teammate C** | Backend / Data & Integration | The Supabase project (schema, Row Level Security, anonymous auth), the Whoosh website/dashboard that reads synced rides and near-misses, the shared data contracts, and dataset/eval tooling to unblock B. |

### Role C (decided): Backend / Data & Integration on Supabase

C keeps the data contracts honest (so B's model output and your `HazardDetector` protocol
line up), owns the Supabase backend, and builds the website that shows synced rides and
near-misses on a big screen. C is never on the iOS critical path: the app is local-first and
the demo works in airplane mode. Supabase sync is an additive stretch (iOS tasks 21–23).

C's source of truth for the backend is `supabase-contract.md` in this folder. The iOS app
implements sync only after C marks it "Agreed."

## The integration contract (the one thing all three must agree on)

Everything hinges on a small, shared shape. It already lives in the iOS design as the seam:

```
HazardDetection {
    timestamp: Date
    kind: String                 // e.g. "vehicle" — open, not an enum yet
    confidence: Double           // 0...1
    relativePositionHint: String?  // "left" | "center" | "right" | nil
}

HazardDetector { onDetection callback; start(); stop() }
AlertManager   { fire(AlertKind) }   // iOS owns playback
```

Contract rules:
- Detector runs **on-device** and must **never block or slow ride recording**.
- iOS consumes `HazardDetection` events and decides whether/how to alert (debounce, cooldown).
- The same `HazardDetection` is what C logs as a near-miss (tied to the current route point).
- Agree on this shape first; freeze it before deep work. Changes go through a quick 3-way OK.

## Workstreams and checkpoints

Three checkpoints keep everyone converging on a demo.

### Checkpoint 1 — "It records" (foundation)
- **You:** iOS tasks 1–10 (project, models, metrics, clock, repositories, location protocol +
  state machine, CoreLocation, formatters). A ride can be recorded and summarized in tests.
- **B:** Collect/borrow a small rear-facing driving/cycling dataset; stand up a notebook that
  runs a baseline detector on sample clips offline; measure rough precision/recall. **Make no
  reliability claims yet.**
- **C:** Freeze the `HazardDetection` contract with you and B. Create the Supabase project,
  finalize `supabase-contract.md` (tables, RLS, anonymous auth) and mark it "Agreed".
  Scaffold the website against a fixture JSON of rides.

### Checkpoint 2 — "It shows" (integration-ready)
- **You:** iOS tasks 11–16 (home + permissions, map wrapper, active ride, summary, history,
  mid-ride persistence). End-to-end ride → summary → history works on device.
- **B:** Package the model to run on-device (Core ML / Vision) behind a Swift type that
  conforms to `HazardDetector`; emit `HazardDetection` events from a live camera feed in a
  tiny standalone harness. Share a `.mlmodel`/package + the conforming class.
- **C:** Apply the schema and RLS policies; verify one anonymous user can't read another's
  rows. Website reads rides from Supabase (seeded test rows until the app syncs) and draws
  routes on a map; add a near-miss overlay driven by `HazardDetection` fixtures.
- **You (stretch, after task 18):** iOS tasks 21–23, opt-in sync into C's `rides` table.

### Checkpoint 3 — "It warns" (demo)
- **You:** iOS task 17 seams are real injection points; swap `NoopDetector` for B's detector
  and `StubAlertManager` for a real haptic/audio alert. Tasks 18–20 (composition, resilience,
  accessibility/privacy). Demo path: ride with rear camera → detection → haptic/audio alert,
  with honest "experimental" framing.
- **B:** Tune thresholds/cooldown with you; provide the measured performance numbers so copy
  stays honest.
- **C:** Live demo dashboard showing the ride + logged near-misses; owns the demo script and
  pitch; final polish.

## Dependency map

```
            freeze HazardDetection contract (all 3)  ── Checkpoint 1
                     │
   You: app core ────┼──── B: offline baseline ──── C: demo scaffold / contract
                     │
   You: UI + persist ┼── B: on-device HazardDetector ── C: demo renders real data  ── Checkpoint 2
                     │
   You: inject B+real alerts ── B: tune + numbers ── C: dashboard + pitch           ── Checkpoint 3
```

Critical path: the **contract freeze** at Checkpoint 1. After that, the three streams only
reconverge at integration, so blockers are minimized.

## Interfaces & ownership boundaries

- **iOS ↔ Vision:** the `HazardDetector`/`HazardDetection` Swift types. B delivers a type
  conforming to `HazardDetector`; you own injection, debouncing, and `AlertManager` playback.
  You never depend on B's internals; B never imports your app code.
- **iOS ↔ Backend:** Supabase, defined by `supabase-contract.md`. The app is local-first;
  sync is opt-in, behind `RideSyncService`, and uses only the anon key + RLS. C owns the schema
  and policies; you own the client. It must never become a demo dependency.
- **Vision ↔ Backend:** C provides dataset storage and eval tooling; B provides detections and
  measured performance. Keep training data off any public bucket.

## Risk register (team-level)

| Risk | Owner | Mitigation |
| ---- | ----- | ---------- |
| Detection not reliable by demo | B + You | Frame as experimental; demo works without warnings as fallback (ride recording alone). |
| Contract churn breaks integration | All | Freeze `HazardDetection` at Checkpoint 1; changes need 3-way OK. |
| Camera/GPS battery drain in demo | You + B | Keep camera optional; GPS accuracy tunable; charged devices; short demo ride. |
| Scope creep (near-miss, routing) | All | Those are post-MVP; see product steering "NOT in MVP". |
| Backend becomes a blocker | C | App never hard-depends on cloud; cloud is additive only. |
| Overclaiming safety in the pitch | C + You | Honest copy rule from privacy steering applies to the pitch too. |

## What is explicitly NOT in the hackathon MVP

Background location, routing/directions, safer-route recommendations, infrastructure
analysis, smartwatch app, accounts/auth, and any claim that the app reliably predicts or
prevents collisions. These are future; keep them out of the demo scope.

## First actions (today)

- **All three:** 30-minute sync to freeze the `HazardDetection` contract and review the draft
  `supabase-contract.md`.
- **You:** start iOS task 1 (scaffold) once the spec is approved.
- **B:** gather a handful of sample rear-camera clips and run a baseline.
- **C:** create the Supabase project, share the URL + anon key privately (not in Git), and
  scaffold the website against a fixture ride JSON.
