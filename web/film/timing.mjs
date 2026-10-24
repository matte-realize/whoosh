// Prints when things happen in the film's two simulated rides, to cut shots and captions to.
import { load } from "./load-engine.mjs";

const E = await load();
const { ACT1, RIDE } = await import("./scenarios.mjs");

function trace(scenario, seconds, label) {
  const sim = E.createSim(scenario);
  const seen = new Map();
  let lastPhase = "none";
  for (let i = 0; i < seconds * 120; i += 1) {
    E.step(sim, 1 / 120);
    for (const v of sim.vehicles) {
      const key = `${v.id}`;
      const rec = seen.get(key) ?? { id: v.id, kind: v.kind, dir: v.direction, x: v.x };
      if (rec.spawn === undefined) rec.spawn = sim.t;
      if (v.state === "tracking" && rec.track === undefined) rec.track = sim.t;
      if (v.state === "cued" && rec.cue === undefined) rec.cue = sim.t;
      if (rec.atRider === undefined && Math.abs(v.z) < v.length / 2) rec.atRider = sim.t;
      if (rec.behind20 === undefined && v.direction === -1 && v.z < -20) rec.behind20 = sim.t;
      seen.set(key, rec);
    }
    if (sim.crash.phase !== lastPhase) {
      console.log(`${label} t=${sim.t.toFixed(2)} crash -> ${sim.crash.phase}`);
      lastPhase = sim.crash.phase;
    }
  }
  console.log(`--- ${label}: rider ${sim.riderDistance.toFixed(0)} m`);
  for (const r of seen.values()) {
    const f = (n) => (n === undefined ? "  -  " : n.toFixed(2).padStart(5));
    console.log(`#${r.id} ${r.kind.padEnd(5)} ${r.dir === 1 ? "same" : "onc "} x=${r.x} spawn ${f(r.spawn)} track ${f(r.track)} cue ${f(r.cue)} atRider ${f(r.atRider)} onc-behind20 ${f(r.behind20)}`);
  }
}

trace(ACT1, 15, "ACT1");
trace(RIDE, 50, "RIDE");
