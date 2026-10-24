// Checks for src/lib/sim/engine.ts. Run from web/:  node scripts/sim-check.ts
// (Node 23.6+ runs TypeScript directly by stripping types.)
import {
  FILM_SCENARIO,
  createSim,
  nearestBehind,
  positionHint,
  RIDER_X,
  SCENARIOS,
  step,
  timeToReach,
  type SimState,
} from "../src/lib/sim/engine.ts";

let failures = 0;
function check(ok: boolean, name: string): void {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}`);
  if (!ok) failures += 1;
}

function run(state: SimState, seconds: number, dt = 1 / 60): SimState {
  for (let t = 0; t < seconds; t += dt) step(state, dt);
  return state;
}

// Oncoming only: nothing is ever flagged.
{
  const sim = run(createSim("oncoming"), 60);
  check(sim.events.length === 0, "oncoming-only scenario raises no cues in 60 s");
  check(sim.vehicles.every((v) => v.direction === -1), "oncoming-only scenario spawns only oncoming vehicles");
}

// Close pass: exactly one cue per loop, on the left, before the car reaches the rider.
{
  const sim = run(createSim("close"), 14 * 3 - 0.5);
  const cues = sim.events.filter((e) => e.type === "cue");
  check(cues.length === 3, `close-pass scenario gives one cue per loop (3 loops -> ${cues.length})`);
  check(cues.every((e) => e.hint === "left"), "close pass is on the rider's left");
  check(cues.every((e) => e.distance !== null && e.distance > 0), "every cue fires while the car is still behind");
  const ids = new Set(cues.map((e) => e.vehicleId));
  check(ids.size === cues.length, "no vehicle is cued twice");
}

// Light traffic: each same-direction vehicle is cued at most once; oncoming never.
{
  const sim = createSim("light");
  const cuedIds: number[] = [];
  const oncomingIds = new Set<number>();
  for (let t = 0; t < 120; t += 1 / 60) {
    step(sim, 1 / 60);
    for (const v of sim.vehicles) if (v.direction === -1) oncomingIds.add(v.id);
  }
  for (const e of sim.events) if (e.vehicleId !== null) cuedIds.push(e.vehicleId);
  check(new Set(cuedIds).size === cuedIds.length, "light traffic: no vehicle cued twice in 120 s");
  check(cuedIds.every((id) => !oncomingIds.has(id)), "light traffic: no oncoming vehicle cued");
  check(cuedIds.length >= 10, `light traffic: overtaking vehicles are cued (${cuedIds.length} cues in 120 s)`);
}

// Mistakes mode: some vehicles are missed, and false alarms appear; with it off, neither happens.
{
  const withMistakes = run(createSim("busy", true), 120);
  const falseAlarms = withMistakes.events.filter((e) => e.type === "false-alarm").length;
  check(falseAlarms >= 1, `mistakes mode raises false alarms (${falseAlarms} in 120 s)`);
  const clean = run(createSim("busy", false), 120);
  check(clean.events.every((e) => e.type === "cue"), "without mistakes mode there are no false alarms");
  check(clean.vehicles.every((v) => !v.missed), "without mistakes mode no vehicle is marked missed");

  const missed = createSim("busy", true);
  let sawMissed = false;
  for (let t = 0; t < 120; t += 1 / 60) {
    step(missed, 1 / 60);
    if (missed.vehicles.some((v) => v.missed)) sawMissed = true;
  }
  check(sawMissed, "mistakes mode marks some vehicles as missed");
}

// Same seed, same run (so a demo replays identically).
{
  const a = run(createSim("busy", true, 42), 60);
  const b = run(createSim("busy", true, 42), 60);
  check(JSON.stringify(a.events) === JSON.stringify(b.events), "same seed replays the same events");
}

// Rider-frame hints and helpers.
check(positionHint(RIDER_X - 2.5) === "left", "vehicle 2.5 m to the rider's left is 'left'");
check(positionHint(RIDER_X) === "center", "vehicle in line with the rider is 'center'");
check(positionHint(RIDER_X + 2) === "right", "vehicle 2 m to the rider's right is 'right'");
{
  // step() caps each call at 0.1 s, so advance in small steps.
  const sim = run(createSim("close"), 1.05);
  const car = sim.vehicles[0];
  check(car !== undefined, "the close-pass car has spawned after 1.05 s");
  const ttr = car ? timeToReach(car) : null;
  check(ttr !== null && ttr > 10, "a car just spawned far behind has a long time-to-reach");
  check(car !== undefined && nearestBehind(sim)?.id === car.id, "nearestBehind finds the approaching car");
}
check(SCENARIOS.every((s) => s.spawns.every((sp, i, all) => i === 0 || all[i - 1].at <= sp.at)),
  "every scenario's spawn schedule is in time order");
{
  const sim = createSim("light");
  step(sim, 5);
  check(sim.t <= 0.1 + 1e-9, "a single huge time step is capped at 0.1 s");
}

// The home page film is cut to these moments; if they move, the captions and shots must move too.
{
  const sim = createSim(FILM_SCENARIO);
  let passAt: number | null = null;
  for (let i = 0; i < 16.5 * 60; i += 1) {
    step(sim, 1 / 60);
    const car = sim.vehicles.find((v) => v.direction === 1);
    if (passAt === null && car !== undefined && car.state === "passed") passAt = sim.t;
  }
  const cues = sim.events.filter((e) => e.type === "cue");
  check(cues.length === 1, `film: exactly one cue (${cues.length})`);
  const cue = cues[0];
  check(cue !== undefined && cue.t > 8.6 && cue.t < 9.5, `film: cue lands during the phone shot (${cue?.t.toFixed(2)} s)`);
  check(cue?.hint === "left", "film: the cue says 'on your left'");
  check(passAt !== null && passAt < 14, `film: the car is past the rider before the end card (${passAt?.toFixed(2)} s)`);
}

console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
