/**
 * The scripted ride for the hidden /vision-story film: a rider without Whoosh gets a close pass
 * with no warning, clips the phone on, and the next car is caught by the rear camera with a buzz.
 *
 * Car A (the first close pass) is placed by hand so it arrives early, and is marked `missed` so the
 * detector never reacts to it: in that part of the film the rider has no phone on the bike.
 * Car B comes from the normal spawn schedule and is the one the detector cues.
 */

import { createSim, type Scenario, type SimState } from "./engine";

export const VISION_FILM_SCENARIO: Scenario = {
  key: "film",
  label: "Vision story",
  description: "A close pass with no warning, then the same kind of pass with Whoosh on the bike.",
  loopSeconds: 1000,
  spawns: [
    { at: 0.5, lane: "oncoming", kind: "car", speed: 12 },
    { at: 7.6, lane: "close", kind: "car", speed: 16 },
  ],
};

/** Vehicle id of car A. Spawned vehicles count up from 1, so this never collides. */
export const CAR_A_ID = 900;

export function createVisionFilmSim(): SimState {
  const sim = createSim(VISION_FILM_SCENARIO);
  sim.vehicles.push({
    id: CAR_A_ID,
    kind: "car",
    x: -0.75,
    z: -70,
    speed: 16,
    direction: 1,
    length: 4.6,
    width: 1.85,
    height: 1.5,
    state: "far",
    missed: true,
  });
  return sim;
}
