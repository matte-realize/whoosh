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
export type ScenarioKey = "light" | "close" | "busy" | "oncoming" | "film";

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

export interface SimState {
  t: number;
  riderDistance: number;
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
}

/** Small deterministic random number generator (mulberry32), so a scenario replays the same way. */
function random(state: SimState): number {
  state.seed = (state.seed + 0x6d2b79f5) | 0;
  let t = state.seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

export function createSim(scenarioOrKey: ScenarioKey | Scenario = "light", mistakes = false, seed = 7): SimState {
  const scenario =
    typeof scenarioOrKey === "string"
      ? [...SCENARIOS, FILM_SCENARIO].find((item) => item.key === scenarioOrKey) ?? SCENARIOS[0]
      : scenarioOrKey;
  return {
    t: 0,
    riderDistance: 0,
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
export function closingSpeed(vehicle: Vehicle): number {
  return vehicle.direction === 1 ? vehicle.speed - RIDER_SPEED : -(vehicle.speed + RIDER_SPEED);
}

/** Seconds until the vehicle's front reaches the rider, or null if it is not closing from behind. */
export function timeToReach(vehicle: Vehicle): number | null {
  const closing = closingSpeed(vehicle);
  const front = vehicle.z + vehicle.length / 2;
  if (vehicle.direction !== 1 || front >= 0 || closing <= DETECTION.minClosingSpeed) return null;
  return -front / closing;
}

function pushEvent(state: SimState, event: SimEvent): void {
  state.events.unshift(event);
  if (state.events.length > MAX_EVENTS) state.events.length = MAX_EVENTS;
  state.lastCue = event;
  state.cueUntil = state.t + DETECTION.cueDisplaySeconds;
}

/** Advances the simulation by dt seconds. Mutates and returns the same state. */
export function step(state: SimState, dt: number): SimState {
  const delta = Math.max(0, Math.min(dt, 0.1));
  state.t += delta;
  state.riderDistance += RIDER_SPEED * delta;

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

  for (const vehicle of state.vehicles) {
    vehicle.z += (vehicle.direction * vehicle.speed - RIDER_SPEED) * delta;

    if (vehicle.direction !== 1) continue; // Oncoming traffic is never an event.
    const rear = vehicle.z - vehicle.length / 2;
    if (rear > 0) {
      vehicle.state = "passed";
      continue;
    }
    if (vehicle.state === "cued" || vehicle.state === "passed" || vehicle.missed) continue;

    const front = vehicle.z + vehicle.length / 2;
    const ttr = timeToReach(vehicle);
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

  if (state.mistakes && state.t >= state.nextFalseAlarm) {
    pushEvent(state, { t: state.t, type: "false-alarm", vehicleId: null, kind: null, hint: null, distance: null });
    state.nextFalseAlarm = state.t + FALSE_ALARM_EVERY_SECONDS * (0.7 + random(state) * 0.6);
  }

  state.vehicles = state.vehicles.filter((vehicle) => vehicle.z < 70 && vehicle.z > -180);
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
