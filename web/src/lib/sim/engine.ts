/**
 * Whoosh ride simulation: pure logic, no drawing, no DOM. Used by the /simulation page.
 *
 * This is an ILLUSTRATION of how the app is designed to behave, built from the rules in
 * `.kiro/team/hazard-contract.md` and `vision/LABELING.md`:
 *   - one caution cue per approaching vehicle (the detector de-duplicates);
 *   - oncoming traffic on the other side of the road is never flagged;
 *   - left / center / right are in the rider's frame (rider's left, facing forward).
 * The simulated detector knows every vehicle's exact position. The real detector is experimental,
 * sees only through a camera, and will miss vehicles and raise false alarms. "Mistakes" mode shows
 * what that looks like. No number from this file is a measurement of the real app.
 *
 * Coordinates, in meters, in the rider's frame: the rider is fixed at z = 0 and rides toward +z.
 * x grows to the rider's right. Roads drive on the right (US), so overtaking traffic passes on the
 * rider's left (negative x).
 */

export type VehicleKind = "car" | "truck" | "bus";
export type PositionHint = "left" | "center" | "right";
export type VehicleState = "far" | "tracking" | "cued" | "passed";
export type ScenarioKey = "light" | "close" | "busy" | "oncoming" | "film" | "recording" | "nearmiss" | "crash";

/**
 * One entry in the ride's near-miss log. "detected" entries are what the simulated detector
 * emitted (one per approaching vehicle, false alarms included). "rider_reported" entries are the
 * rider tapping "Mark close call". Mirrors `near_misses` in hazard-contract.md: no distance is
 * stored, because a single camera cannot measure one.
 */
export interface NearMiss {
  id: number;
  /** Simulation seconds. */
  t: number;
  source: "detected" | "rider_reported";
  kind: VehicleKind | null;
  hint: PositionHint | null;
  /** Detector score, 0..1. Not a probability. Null for rider reports. */
  score: number | null;
  falseAlarm: boolean;
  /** Nearest route point when logged. */
  lat: number;
  lon: number;
  /** Rider distance along the route when logged, meters (places the marker in the 3D scene). */
  at: number;
}

/**
 * Crash response drill, following .kiro/specs/crash-response: a probable crash starts a countdown
 * the rider can cancel ("I'm OK"); if it runs out (or "Send now"), the drill text is sent to the
 * emergency contact. The simulated crash is the spec's "Simulate crash" demo path.
 */
export type CrashPhase = "none" | "countdown" | "sending" | "sent" | "cancelled";

export interface CrashState {
  phase: CrashPhase;
  detectedAt: number;
  deadline: number;
  sentAt: number | null;
  endedAt: number | null;
  lat: number;
  lon: number;
  /** Rider distance along the route at the crash, meters. */
  at: number;
}

export const CRASH = {
  /** The spec allows 15–60 s (default 30). The drill uses the shortest allowed value. */
  countdownSeconds: 15,
  /** Simulated time for the backend to accept the message and the contact's phone to receive it. */
  sendingSeconds: 1.8,
  /** After "I'm OK", seconds until the rider is back up and riding. */
  getUpSeconds: 2,
  /** Seconds from impact until the bike comes to rest. */
  fallSeconds: 0.6,
};

/** Shown on the contact's phone. Text is golden case G6 (drill) from crash-alert-contract.md. */
export const CONTACT = { riderLabel: "Alex", contactName: "Sam" };

export interface Vehicle {
  id: number;
  kind: VehicleKind;
  /** Lateral center, meters. */
  x: number;
  /** Longitudinal position relative to the rider, meters. Negative = behind. */
  z: number;
  /** Ground speed, meters/second. */
  speed: number;
  /** 1 = same direction as the rider, -1 = oncoming. */
  direction: 1 | -1;
  length: number;
  width: number;
  height: number;
  state: VehicleState;
  /** Mistakes mode: the detector never sees this vehicle. */
  missed: boolean;
}

export interface SimEvent {
  /** Simulation seconds. */
  t: number;
  type: "cue" | "false-alarm";
  vehicleId: number | null;
  kind: VehicleKind | null;
  hint: PositionHint | null;
  /** Meters behind the rider when the cue fired (null for false alarms). */
  distance: number | null;
}

interface Spawn {
  at: number;
  lane: "travel" | "close" | "oncoming";
  kind: VehicleKind;
  speed: number;
}

export interface Scenario {
  key: ScenarioKey;
  label: string;
  description: string;
  loopSeconds: number;
  spawns: Spawn[];
  /** Seconds before the rider taps Start Ride. Default 0: the ride is already recording. */
  rideStartsAt?: number;
  /** Simulation seconds at which a simulated crash happens, if any. */
  crashAt?: number;
}

export const SCENARIOS: Scenario[] = [
  {
    key: "light",
    label: "Light traffic",
    description: "A few cars and a truck overtake, and some oncoming traffic passes on the other side.",
    loopSeconds: 24,
    spawns: [
      { at: 1, lane: "travel", kind: "car", speed: 13 },
      { at: 6, lane: "oncoming", kind: "car", speed: 13 },
      { at: 9, lane: "travel", kind: "car", speed: 12 },
      { at: 16, lane: "travel", kind: "truck", speed: 11 },
      { at: 19, lane: "oncoming", kind: "car", speed: 12 },
    ],
  },
  {
    key: "close",
    label: "Close pass",
    description: "One fast car passes close to the bike lane line.",
    loopSeconds: 14,
    spawns: [{ at: 1, lane: "close", kind: "car", speed: 15 }],
  },
  {
    key: "busy",
    label: "Busy road",
    description: "Steady traffic in both directions, including a bus.",
    loopSeconds: 18,
    spawns: [
      { at: 0.5, lane: "travel", kind: "car", speed: 14 },
      { at: 2, lane: "oncoming", kind: "car", speed: 13 },
      { at: 3.5, lane: "travel", kind: "car", speed: 12 },
      { at: 5, lane: "oncoming", kind: "truck", speed: 11 },
      { at: 6, lane: "travel", kind: "bus", speed: 10.5 },
      { at: 8, lane: "oncoming", kind: "car", speed: 14 },
      { at: 9, lane: "travel", kind: "car", speed: 15 },
      { at: 11, lane: "oncoming", kind: "car", speed: 12 },
      { at: 12, lane: "travel", kind: "truck", speed: 12 },
      { at: 14, lane: "oncoming", kind: "bus", speed: 10 },
      { at: 15, lane: "travel", kind: "car", speed: 13 },
      { at: 17, lane: "oncoming", kind: "car", speed: 13 },
    ],
  },
  {
    key: "oncoming",
    label: "Oncoming only",
    description: "Only oncoming traffic. The detector is designed to flag none of it.",
    loopSeconds: 10,
    spawns: [
      { at: 1, lane: "oncoming", kind: "car", speed: 13 },
      { at: 4, lane: "oncoming", kind: "truck", speed: 11 },
      { at: 7, lane: "oncoming", kind: "car", speed: 14 },
    ],
  },
];

/**
 * The fixed ride used by the home page film: one car overtakes close on the rider's left, and an
 * oncoming truck passes on the other side. Not in SCENARIOS, so it is not offered on /simulation.
 * scripts/sim-check.ts pins its timing (cue around 9 s, car past before 14 s), which the film's
 * shots and captions are cut to.
 */
export const FILM_SCENARIO: Scenario = {
  key: "film",
  label: "Intro film",
  description: "A car overtakes close on the left while an oncoming truck passes.",
  loopSeconds: 1000,
  spawns: [
    { at: 0.2, lane: "close", kind: "car", speed: 17 },
    { at: 2, lane: "oncoming", kind: "truck", speed: 12 },
  ],
};

/**
 * Scripted rides for the three demo features. Not in SCENARIOS (the traffic picker); the
 * simulation page offers them as feature tabs. scripts/sim-check.ts pins their key moments.
 */
export const FEATURE_SCENARIOS: Scenario[] = [
  {
    key: "recording",
    label: "Ride recording",
    description:
      "The rider taps Start Ride. The phone records time, distance, speed and the route, and the Watch mirrors it.",
    loopSeconds: 30,
    rideStartsAt: 2,
    spawns: [
      { at: 3, lane: "oncoming", kind: "car", speed: 12 },
      { at: 8, lane: "travel", kind: "car", speed: 12 },
      { at: 14, lane: "oncoming", kind: "bus", speed: 10 },
      { at: 20, lane: "travel", kind: "truck", speed: 11 },
      { at: 25, lane: "oncoming", kind: "car", speed: 13 },
    ],
  },
  {
    key: "nearmiss",
    label: "Near-miss logging",
    description:
      "A fast car passes close. The rear camera spots it, the rider gets a cue, and the close call is logged with where it happened.",
    loopSeconds: 18,
    spawns: [
      { at: 0.2, lane: "close", kind: "car", speed: 18 },
      { at: 5, lane: "oncoming", kind: "truck", speed: 11 },
      { at: 9, lane: "travel", kind: "car", speed: 12 },
      { at: 13, lane: "oncoming", kind: "car", speed: 13 },
    ],
  },
  {
    key: "crash",
    label: "Crash response",
    description:
      "A simulated crash starts a 15-second countdown. Nobody taps I'm OK, so the drill text goes to the emergency contact.",
    loopSeconds: 1000,
    crashAt: 5,
    spawns: [
      { at: 1, lane: "oncoming", kind: "car", speed: 12 },
      { at: 2, lane: "travel", kind: "car", speed: 12 },
      { at: 12, lane: "oncoming", kind: "truck", speed: 10 },
      { at: 16, lane: "travel", kind: "car", speed: 11 },
    ],
  },
];

/**
 * The simulated ride follows the Massachusetts Avenue bike lane northbound from Columbus Ave
 * toward Commonwealth Ave, Boston (points taken from fixtures/bike_network.json). [lon, lat].
 */
const ROUTE: [number, number][] = [
  [-71.08175, 42.34066],
  [-71.08302, 42.34148],
  [-71.0841, 42.3422],
  [-71.08485, 42.34271],
  [-71.0858, 42.34334],
  [-71.08655, 42.34487],
  [-71.08684, 42.34546],
  [-71.08734, 42.34649],
  [-71.08776, 42.34731],
  [-71.08814, 42.34813],
  [-71.08852, 42.34887],
  [-71.08893, 42.34971],
  [-71.08929, 42.35047],
];

const METERS_PER_DEG_LAT = 111_132;
const METERS_PER_DEG_LON = 111_320 * Math.cos((42.345 * Math.PI) / 180);
const ROUTE_CUMULATIVE: number[] = ROUTE.reduce<number[]>((acc, point, i) => {
  if (i === 0) return [0];
  const [lon0, lat0] = ROUTE[i - 1];
  const d = Math.hypot((point[0] - lon0) * METERS_PER_DEG_LON, (point[1] - lat0) * METERS_PER_DEG_LAT);
  acc.push(acc[i - 1] + d);
  return acc;
}, []);
export const ROUTE_LENGTH = ROUTE_CUMULATIVE[ROUTE_CUMULATIVE.length - 1];

/** Latitude and longitude after riding `meters` along the route (stays at the end past it). */
export function routePoint(meters: number): { lat: number; lon: number } {
  const m = Math.max(0, Math.min(meters, ROUTE_LENGTH));
  let i = 1;
  while (i < ROUTE_CUMULATIVE.length - 1 && ROUTE_CUMULATIVE[i] < m) i += 1;
  const span = ROUTE_CUMULATIVE[i] - ROUTE_CUMULATIVE[i - 1] || 1;
  const f = (m - ROUTE_CUMULATIVE[i - 1]) / span;
  const [lon0, lat0] = ROUTE[i - 1];
  const [lon1, lat1] = ROUTE[i];
  return { lat: lat0 + (lat1 - lat0) * f, lon: lon0 + (lon1 - lon0) * f };
}

/** The whole route, for drawing the map. [lon, lat]. */
export const ROUTE_POINTS: readonly [number, number][] = ROUTE;

/** Road layout, meters. */
export const ROAD = {
  bikeLaneLeft: 0,
  bikeLaneRight: 1.8,
  travelLaneLeft: -3.6,
  oncomingLaneLeft: -7.2,
  sidewalkRight: 4.6,
  sidewalkLeft: -10,
};

export const RIDER_X = 0.9;
export const RIDER_SPEED = 5; // m/s, about 11 mph

/** Simulated detector rules. Illustrative values, not the real app's tuning. */
export const DETECTION = {
  rangeMeters: 60,
  minClosingSpeed: 0.5,
  cueTimeToReachSeconds: 3.5,
  cueDistanceMeters: 10,
  cueDisplaySeconds: 1.6,
};

const LANE_X = { travel: -1.8, close: -0.75, oncoming: -5.4 } as const;
const SIZE: Record<VehicleKind, { length: number; width: number; height: number }> = {
  car: { length: 4.6, width: 1.85, height: 1.5 },
  truck: { length: 7.5, width: 2.4, height: 3.0 },
  bus: { length: 12, width: 2.55, height: 3.2 },
};

const SPAWN_BEHIND = -150;
const SPAWN_AHEAD = 120;
const MISS_RATE = 0.25;
const FALSE_ALARM_EVERY_SECONDS = 20;
const MAX_EVENTS = 50;

/** Rider acceleration when setting off, m/s². */
const RIDER_ACCEL = 1.6;

export interface SimState {
  t: number;
  riderDistance: number;
  /** Current rider speed, m/s. Zero before Start Ride and after a crash. */
  riderSpeed: number;
  vehicles: Vehicle[];
  events: SimEvent[];
  scenario: Scenario;
  mistakes: boolean;
  /** Seconds into the current scenario loop. */
  loopTime: number;
  spawnIndex: number;
  nextId: number;
  seed: number;
  nextFalseAlarm: number;
  /** Simulation time until which the caution banner shows. */
  cueUntil: number;
  lastCue: SimEvent | null;
  /** Simulation time the rider taps Start Ride. */
  rideStartsAt: number;
  nearMisses: NearMiss[];
  nextNearMissId: number;
  /** Simulation time until which the "Near miss logged" toast shows. */
  loggedUntil: number;
  crash: CrashState;
  scriptedCrashDone: boolean;
}

/** Small deterministic random number generator (mulberry32), so a scenario replays the same way. */
function random(state: SimState): number {
  state.seed = (state.seed + 0x6d2b79f5) | 0;
  let t = state.seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

export function findScenario(key: ScenarioKey): Scenario {
  return [...SCENARIOS, ...FEATURE_SCENARIOS, FILM_SCENARIO].find((item) => item.key === key) ?? SCENARIOS[0];
}

export function createSim(scenarioOrKey: ScenarioKey | Scenario = "light", mistakes = false, seed = 7): SimState {
  const scenario = typeof scenarioOrKey === "string" ? findScenario(scenarioOrKey) : scenarioOrKey;
  const rideStartsAt = scenario.rideStartsAt ?? 0;
  return {
    t: 0,
    riderDistance: 0,
    riderSpeed: rideStartsAt > 0 ? 0 : RIDER_SPEED,
    vehicles: [],
    events: [],
    scenario,
    mistakes,
    loopTime: 0,
    spawnIndex: 0,
    nextId: 1,
    seed,
    nextFalseAlarm: FALSE_ALARM_EVERY_SECONDS * 0.6,
    cueUntil: -1,
    lastCue: null,
    rideStartsAt,
    nearMisses: [],
    nextNearMissId: 1,
    loggedUntil: -1,
    crash: { phase: "none", detectedAt: -1, deadline: -1, sentAt: null, endedAt: null, lat: 0, lon: 0, at: 0 },
    scriptedCrashDone: false,
  };
}

function spawn(state: SimState, item: Spawn): void {
  const size = SIZE[item.kind];
  const oncoming = item.lane === "oncoming";
  const vehicle: Vehicle = {
    id: state.nextId,
    kind: item.kind,
    x: LANE_X[item.lane],
    z: oncoming ? SPAWN_AHEAD : SPAWN_BEHIND,
    speed: item.speed,
    direction: oncoming ? -1 : 1,
    ...size,
    state: "far",
    missed: false,
  };
  state.nextId += 1;
  if (!oncoming && state.mistakes) vehicle.missed = random(state) < MISS_RATE;
  state.vehicles.push(vehicle);
}

/** Rider-frame position hint from the vehicle's lateral offset. */
export function positionHint(vehicleX: number): PositionHint {
  const dx = vehicleX - RIDER_X;
  if (dx < -1.2) return "left";
  if (dx > 1.2) return "right";
  return "center";
}

/** Closing speed toward the rider, m/s. Positive means getting closer. Oncoming traffic is negative. */
export function closingSpeed(vehicle: Vehicle, riderSpeed = RIDER_SPEED): number {
  return vehicle.direction === 1 ? vehicle.speed - riderSpeed : -(vehicle.speed + riderSpeed);
}

/** Seconds until the vehicle's front reaches the rider, or null if it is not closing from behind. */
export function timeToReach(vehicle: Vehicle, riderSpeed = RIDER_SPEED): number | null {
  const closing = closingSpeed(vehicle, riderSpeed);
  const front = vehicle.z + vehicle.length / 2;
  if (vehicle.direction !== 1 || front >= 0 || closing <= DETECTION.minClosingSpeed) return null;
  return -front / closing;
}

/** True once the rider has tapped Start Ride. */
export function isRecording(state: SimState): boolean {
  return state.t >= state.rideStartsAt;
}

/** Ride time shown on the phone and Watch, seconds. */
export function rideTime(state: SimState): number {
  return Math.max(0, state.t - state.rideStartsAt);
}

/** True while the rider is on the ground (crash countdown, sending, sent, or getting up). */
export function riderDown(state: SimState): boolean {
  const { phase, endedAt } = state.crash;
  if (phase === "countdown" || phase === "sending" || phase === "sent") return true;
  return phase === "cancelled" && endedAt !== null && state.t < endedAt + CRASH.getUpSeconds;
}

/** How far over the bike is, 0 (upright) to 1 (on the ground). Drives the 3D fall and get-up. */
export function fallAmount(state: SimState): number {
  const { phase, detectedAt, endedAt } = state.crash;
  if (phase === "none") return 0;
  if (phase === "cancelled" && endedAt !== null) {
    return Math.max(0, 1 - (state.t - endedAt) / CRASH.getUpSeconds);
  }
  return Math.min(1, Math.max(0, (state.t - detectedAt) / CRASH.fallSeconds));
}

/** Seconds left on the crash countdown, or null when no countdown is running. */
export function countdownRemaining(state: SimState): number | null {
  return state.crash.phase === "countdown" ? Math.max(0, state.crash.deadline - state.t) : null;
}

/** A stable detector score per vehicle, so the log reads the same on every replay. */
function detectorScore(vehicleId: number | null, t: number): number {
  const n = vehicleId ?? Math.round(t * 10);
  return 0.58 + ((n * 0.6180339887) % 1) * 0.36;
}

function logNearMiss(state: SimState, entry: Omit<NearMiss, "id" | "t" | "lat" | "lon" | "at">): NearMiss {
  const where = routePoint(state.riderDistance);
  const nearMiss: NearMiss = {
    id: state.nextNearMissId,
    t: state.t,
    lat: where.lat,
    lon: where.lon,
    at: state.riderDistance,
    ...entry,
  };
  state.nextNearMissId += 1;
  state.nearMisses.unshift(nearMiss);
  if (state.nearMisses.length > MAX_EVENTS) state.nearMisses.length = MAX_EVENTS;
  state.loggedUntil = state.t + 2.4;
  return nearMiss;
}

function pushEvent(state: SimState, event: SimEvent): void {
  state.events.unshift(event);
  if (state.events.length > MAX_EVENTS) state.events.length = MAX_EVENTS;
  state.lastCue = event;
  state.cueUntil = state.t + DETECTION.cueDisplaySeconds;
  // Every detector emission goes into the near-miss log (hazard-contract.md, decision 2).
  logNearMiss(state, {
    source: "detected",
    kind: event.kind,
    hint: event.hint,
    score: detectorScore(event.vehicleId, event.t),
    falseAlarm: event.type === "false-alarm",
  });
}

/** The rider taps Start Ride now (earlier than the script would). */
export function startRide(state: SimState): boolean {
  if (isRecording(state)) return false;
  state.rideStartsAt = state.t;
  return true;
}

/** The rider taps "Mark close call". Returns the entry, or null if no ride is recording. */
export function markCloseCall(state: SimState): NearMiss | null {
  if (!isRecording(state) || riderDown(state)) return null;
  return logNearMiss(state, { source: "rider_reported", kind: null, hint: null, score: null, falseAlarm: false });
}

/** A probable crash (the spec's "Simulate crash" drill). Ignored if one is already in progress. */
export function triggerCrash(state: SimState): boolean {
  if (!isRecording(state) || riderDown(state)) return false;
  const where = routePoint(state.riderDistance);
  state.crash = {
    phase: "countdown",
    detectedAt: state.t,
    deadline: state.t + CRASH.countdownSeconds,
    sentAt: null,
    endedAt: null,
    lat: where.lat,
    lon: where.lon,
    at: state.riderDistance,
  };
  state.cueUntil = -1;
  return true;
}

/** "I'm OK — Cancel". Only works before the deadline; expiry wins a tie (design.md, row 9). */
export function cancelCrash(state: SimState): boolean {
  if (state.crash.phase !== "countdown" || state.t >= state.crash.deadline) return false;
  state.crash.phase = "cancelled";
  state.crash.endedAt = state.t;
  return true;
}

/** "Send now": skip the rest of the countdown. */
export function sendCrashNow(state: SimState): boolean {
  if (state.crash.phase !== "countdown") return false;
  state.crash.phase = "sending";
  state.crash.deadline = state.t;
  return true;
}

function stepCrash(state: SimState): void {
  const crash = state.crash;
  if (crash.phase === "countdown" && state.t >= crash.deadline) {
    crash.phase = "sending";
    crash.deadline = state.t;
  }
  if (crash.phase === "sending" && state.t >= crash.deadline + CRASH.sendingSeconds) {
    crash.phase = "sent";
    crash.sentAt = state.t;
    crash.endedAt = state.t;
  }
}

function stepRider(state: SimState, delta: number): void {
  if (riderDown(state)) {
    // Skid to a stop over the fall.
    const decel = RIDER_SPEED / CRASH.fallSeconds;
    state.riderSpeed = Math.max(0, state.riderSpeed - decel * delta);
  } else if (isRecording(state) && state.riderSpeed < RIDER_SPEED) {
    state.riderSpeed = Math.min(RIDER_SPEED, state.riderSpeed + RIDER_ACCEL * delta);
  }
}

/** Advances the simulation by dt seconds. Mutates and returns the same state. */
export function step(state: SimState, dt: number): SimState {
  const delta = Math.max(0, Math.min(dt, 0.1));
  state.t += delta;

  if (!state.scriptedCrashDone && state.scenario.crashAt !== undefined && state.t >= state.scenario.crashAt) {
    state.scriptedCrashDone = true;
    triggerCrash(state);
  }
  stepCrash(state);
  stepRider(state, delta);
  state.riderDistance += state.riderSpeed * delta;

  // Spawns, looping the scenario's schedule.
  state.loopTime += delta;
  const spawns = state.scenario.spawns;
  while (state.spawnIndex < spawns.length && state.loopTime >= spawns[state.spawnIndex].at) {
    spawn(state, spawns[state.spawnIndex]);
    state.spawnIndex += 1;
  }
  if (state.loopTime >= state.scenario.loopSeconds) {
    state.loopTime -= state.scenario.loopSeconds;
    state.spawnIndex = 0;
  }

  // The detector runs only while a ride is recording and the rider is up.
  const detecting = isRecording(state) && !riderDown(state);

  for (const vehicle of state.vehicles) {
    vehicle.z += (vehicle.direction * vehicle.speed - state.riderSpeed) * delta;

    if (vehicle.direction !== 1) continue; // Oncoming traffic is never an event.
    const rear = vehicle.z - vehicle.length / 2;
    if (rear > 0) {
      vehicle.state = "passed";
      continue;
    }
    if (vehicle.state === "cued" || vehicle.state === "passed" || vehicle.missed) continue;
    if (!detecting) {
      vehicle.state = "far";
      continue;
    }

    const front = vehicle.z + vehicle.length / 2;
    const ttr = timeToReach(vehicle, state.riderSpeed);
    const inRange = front < 0 && -front <= DETECTION.rangeMeters && ttr !== null;
    if (!inRange) continue;
    vehicle.state = "tracking";
    if (ttr <= DETECTION.cueTimeToReachSeconds || -front <= DETECTION.cueDistanceMeters) {
      vehicle.state = "cued";
      pushEvent(state, {
        t: state.t,
        type: "cue",
        vehicleId: vehicle.id,
        kind: vehicle.kind,
        hint: positionHint(vehicle.x),
        distance: Math.round(-front),
      });
    }
  }

  if (state.mistakes && detecting && state.t >= state.nextFalseAlarm) {
    pushEvent(state, { t: state.t, type: "false-alarm", vehicleId: null, kind: null, hint: null, distance: null });
    state.nextFalseAlarm = state.t + FALSE_ALARM_EVERY_SECONDS * (0.7 + random(state) * 0.6);
  }

  // Oncoming traffic spawns SPAWN_AHEAD in front, so the far edge must include it.
  state.vehicles = state.vehicles.filter((vehicle) => vehicle.z <= SPAWN_AHEAD + 1 && vehicle.z > -180);
  return state;
}

/** The nearest same-direction vehicle behind the rider that is still closing, for the readout. */
export function nearestBehind(state: SimState): Vehicle | null {
  let best: Vehicle | null = null;
  for (const vehicle of state.vehicles) {
    if (vehicle.direction !== 1 || vehicle.z + vehicle.length / 2 >= 0) continue;
    if (best === null || vehicle.z > best.z) best = vehicle;
  }
  return best;
}

export function cueActive(state: SimState): boolean {
  return state.t < state.cueUntil;
}

export function nearMissToastActive(state: SimState): boolean {
  return state.t < state.loggedUntil;
}

/** Formats a time of day for the drill text: "1:41 PM". Uses a fixed ride start of 1:40:30 PM. */
export function clockTime(simSeconds: number): string {
  const total = 13 * 3600 + 40 * 60 + 30 + Math.floor(simSeconds);
  const h24 = Math.floor(total / 3600) % 24;
  const m = Math.floor((total % 3600) / 60);
  const h = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h}:${m.toString().padStart(2, "0")} ${h24 < 12 ? "AM" : "PM"}`;
}

/**
 * The drill text the contact receives, in the format of golden case G6 (crash-alert-contract.md,
 * Appendix A): fixed English, 5-decimal coordinates, Apple and Google Maps links.
 */
export function drillMessage(state: SimState): string {
  const { lat, lon, detectedAt } = state.crash;
  const ll = `${lat.toFixed(5)},${lon.toFixed(5)}`;
  return [
    `WHOOSH DEMO - NOT REAL: ${CONTACT.riderLabel} is demonstrating Whoosh crash alerts. No crash happened.`,
    `Time: Sat Oct 24, ${clockTime(detectedAt)} (UTC-4)`,
    "Location (+/-8 m):",
    `Apple Maps: https://maps.apple.com/?ll=${ll}&q=Rider`,
    `Google Maps: https://www.google.com/maps/search/?api=1&query=${ll}`,
    "Sent by Whoosh, not an emergency service. Reply STOP to opt out.",
  ].join("\n");
}
