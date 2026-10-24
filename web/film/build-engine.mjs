// Transpiles src/lib/sim/engine.ts into one plain script for JavaScriptCore, plus a small `film`
// API the Swift renderer calls. Usage: node build-engine.mjs <out.js>
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { ACT1, RIDE } from "./scenarios.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(here, "..");
const require = createRequire(path.join(web, "package.json"));
const ts = require("typescript");

const source = fs.readFileSync(path.join(web, "src/lib/sim/engine.ts"), "utf8");
const engine = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;

const api = `
var film = (function () {
  var E = exports;
  var sims = {};
  var scenarios = ${JSON.stringify({ act1: ACT1, ride: RIDE })};
  function vehicles(s) {
    return s.vehicles.map(function (v) {
      return { id: v.id, kind: v.kind, x: v.x, z: v.z, length: v.length, width: v.width, height: v.height,
        speed: v.speed, direction: v.direction, state: v.state, missed: v.missed };
    });
  }
  return {
    create: function (name, key) { sims[name] = E.createSim(scenarios[key]); },
    advance: function (name, dt) {
      var s = sims[name];
      var left = dt;
      while (left > 1e-9) { var d = Math.min(left, 1 / 120); E.step(s, d); left -= d; }
    },
    state: function (name) {
      var s = sims[name];
      var rp = E.routePoint(s.riderDistance);
      return JSON.stringify({
        t: s.t, riderDistance: s.riderDistance, riderSpeed: s.riderSpeed, rideStartsAt: s.rideStartsAt,
        recording: E.isRecording(s), rideTime: E.rideTime(s), vehicles: vehicles(s), cue: E.cueActive(s),
        lastCueHint: s.lastCue ? s.lastCue.hint : null, lastCueKind: s.lastCue ? s.lastCue.kind : null,
        nearMisses: s.nearMisses, toast: E.nearMissToastActive(s),
        crashPhase: s.crash.phase, crashDetectedAt: s.crash.detectedAt, crashSentAt: s.crash.sentAt,
        crashEndedAt: s.crash.endedAt, remaining: E.countdownRemaining(s), fall: E.fallAmount(s),
        riderDown: E.riderDown(s), message: s.crash.phase === "sent" ? E.drillMessage(s) : null,
        messageTime: s.crash.sentAt !== null ? E.clockTime(s.crash.sentAt) : null,
        clock: E.clockTime(s.t), lat: rp.lat, lon: rp.lon,
      });
    },
    route: function () { return JSON.stringify({ points: E.ROUTE_POINTS, length: E.ROUTE_LENGTH }); },
    routePoint: function (m) { return E.routePoint(m); },
  };
})();
`;

const out = process.argv[2] ?? path.join(here, "build/engine.js");
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `var exports = {};\n${engine}\n${api}`);
console.log(`wrote ${out}`);
