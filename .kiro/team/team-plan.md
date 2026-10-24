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
the demo works in airplane mode. Supabase sync is an additive stretch (iOS tasks 26–28).

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
- **You:** iOS tasks 1–12 (project, theme, models, metrics, weekly stats, clock, repositories
  with deleteAll, location protocol + state machine, CoreLocation, formatters). A ride can be
  recorded and summarized in tests, and the design system is in place.
- **B:** Collect/borrow a small rear-facing driving/cycling dataset; stand up a notebook that
  runs a baseline detector on sample clips offline; measure rough precision/recall. **Make no
  reliability claims yet.**
- **C:** Freeze the `HazardDetection` contract with you and B. Create the Supabase project,
  finalize `supabase-contract.md` (tables, RLS, anonymous auth) and mark it "Agreed".
  Scaffold the website against a fixture JSON of rides.

### Checkpoint 2 — "It shows" (integration-ready)
- **You:** iOS tasks 13–21 (settings VM + screen, home + permissions/location-denied, home
  dashboard, map wrapper, active ride with hold-to-stop, summary, history, mid-ride
  persistence). End-to-end ride → summary → history works on device, with the Home dashboard
  and Settings in place.
- **B:** Package the model to run on-device (Core ML / Vision) behind a Swift type that
  conforms to `HazardDetector`; emit `HazardDetection` events from a live camera feed in a
  tiny standalone harness. Share a `.mlmodel`/package + the conforming class.
- **C:** Apply the schema and RLS policies; verify one anonymous user can't read another's
  rows. Website reads rides from Supabase (seeded test rows until the app syncs) and draws
  routes on a map; add a near-miss overlay driven by `HazardDetection` fixtures.
- **You (stretch, after task 23):** iOS tasks 26–28, opt-in sync into C's `rides` table.

### Checkpoint 3 — "It warns" (demo)
- **You:** iOS task 22 seams are real injection points; swap `NoopDetector` for B's detector
  and `StubAlertManager` for a real haptic/audio alert. Tasks 23–25 (composition, resilience,
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

## Crash response workstreams (post-MVP, opt-in — new)

Spec: `.kiro/specs/crash-response/` (requirements, design, tasks). Backend contract:
`crash-alert-contract.md` (DRAFT, owned by Role C). Nothing here is part of the MVP demo scope or
changes the three MVP checkpoints; it is a fourth, optional checkpoint after "It warns". **No
code is written until the iOS owner approves the spec and Role C marks the contract Agreed.**

| Workstream | Owner | Scope | Spec tasks |
| ---------- | ----- | ----- | ---------- |
| iOS crash response | **You (iOS)** | Models, pure message builder and state machine, contact store (Keychain), consent, connectivity, notifier protocol + fakes, coordinator, countdown/status/log/setup screens, Supabase client implementation, privacy-script update, integration with `RideSessionViewModel`, Simulate-crash demo path, QA checklist | `crash-response/tasks.md` 0–29 |
| Backend SMS alerts | **Role C** | Edge Functions `send-crash-alert`, `crash-alert-status`, `sms-status-callback`, `delete-crash-audit`; provider trial setup and limits; audit tables + RLS + retention; cost caps and kill switch; contract tests; contract finalization | `crash-response/tasks.md` C1–C12 |
| Crash detector (optional) | **Teammate B** (or the iOS owner) | Experimental Core Motion heuristic behind the `CrashDetector` seam, field testing with measured false-positive numbers; later, the camera-side `FootageBuffer` | `crash-response/tasks.md` 32–34 |

### Checkpoint 4 — "It alerts" (optional, after Checkpoint 3)

- **You:** crash-response iOS tasks, **Tier 0 first** (Simulate crash → countdown → cancel/expire →
  composer fallback, works in airplane mode), then Tier 1 when the backend is ready.
- **Role C:** contract Agreed → provider trial account → migrations/RLS → `send-crash-alert` →
  status callback/status endpoints → caps and kill switch → staging + rehearsed kill switch.
- **B (optional):** pure signal core for the motion heuristic, then device field-testing. Nothing
  about detection reliability is claimed until measured.
- **Demo tiers:** Tier 0 (iOS only) must never depend on the backend; Tier 1 adds a real trial SMS
  to a verified teammate phone ("WHOOSH DEMO - NOT REAL"). If the provider fails, show Tier 0.

### New interfaces

- **iOS ↔ Backend:** `crash-alert-contract.md` (anonymous Supabase JWT, fixed templates, idempotent
  by `crashEventId`). No provider credentials in the app or the repo; the backend stores no
  plaintext numbers, message bodies, or coordinates.
- **iOS ↔ Detector:** the `CrashDetector` protocol (probable-crash signal with timestamp,
  confidence, source). B never imports app code; the iOS owner owns arming, countdown, and alerts.
  Camera-assisted cues could later arrive behind the same protocol.
- **Shared test data:** Appendix A of the contract (golden messages) is the single source of truth
  for the iOS message builder tests and the backend renderer tests.

## Risk register (team-level)

| Risk | Owner | Mitigation |
| ---- | ----- | ---------- |
| Detection not reliable by demo | B + You | Frame as experimental; demo works without warnings as fallback (ride recording alone). |
| Contract churn breaks integration | All | Freeze `HazardDetection` at Checkpoint 1; changes need 3-way OK. |
| Camera/GPS battery drain in demo | You + B | Keep camera optional; GPS accuracy tunable; charged devices; short demo ride. |
| Scope creep (near-miss, routing) | All | Those are post-MVP; see product steering "NOT in MVP". |
| Backend becomes a blocker | C | App never hard-depends on cloud; cloud is additive only. |
| Overclaiming safety in the pitch | C + You | Honest copy rule from privacy steering applies to the pitch too. |
| Crash alerts overclaim ("we detect crashes / help is coming") | All | Experimental framing; "not a guaranteed emergency-response service" in setup, consent, countdown, status, and the pitch; privacy script flags claims. |
| False crash alerts annoy contacts | You + B | Countdown with one-tap cancel, suppression window, per-ride cap, detector off by default, measure before enabling. |
| SMS provider trial limits / registration lead time | C | Trial route with verified numbers for the demo; 10DLC/toll-free registration is production work; Tier 0 fallback demo. |
| SMS cost or abuse (anonymous accounts are cheap) | C | Fixed templates, per-user and per-recipient caps, spend cap, kill switch (rehearsed), App Attest later. |
| Safety feature depends on the cloud | You + C | Opt-in and labeled non-guaranteed; queue + composer fallback; core ride recording unaffected. |
| Foreground-only limits (app closed/suspended) | You | Documented in consent; time-sensitive local notification backup; server-side countdown is a v2 option. |
| Message text drifts between iOS and backend | You + C | Shared golden cases (contract Appendix A) and `templateVersion`. |
| Accidental real 911 call during the demo | You | Call 911 is manual-only and hidden for drills. |
| Time pressure on a post-MVP feature | All | Tier 0 first; stretch items (motion detector, all-clear, footage) never block. |

## What is explicitly NOT in the hackathon MVP

Background location, routing/directions, safer-route recommendations, infrastructure
analysis, smartwatch app, accounts/auth, and any claim that the app reliably predicts or
prevents collisions. These are future; keep them out of the demo scope. Emergency contacts and
crash alerts are a separate **post-MVP opt-in feature** (see "Crash response workstreams" above).

## First actions (today)

- **All three:** 30-minute sync to freeze the `HazardDetection` contract and review the draft
  `supabase-contract.md`.
- **You:** start iOS task 1 (scaffold) once the spec is approved.
- **B:** gather a handful of sample rear-camera clips and run a baseline.
- **C:** create the Supabase project, share the URL + anon key privately (not in Git), and
  scaffold the website against a fixture ride JSON.
