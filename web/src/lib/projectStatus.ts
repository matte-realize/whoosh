/**
 * What the project page says is built. Update this file, and only this file, before the demo,
 * so the page never claims more than is true. Each status must be backed by a run or a test,
 * not by code merely existing.
 */

export type Status = "tested" | "built" | "prototype" | "planned";

export const STATUS_LABEL: Record<Status, string> = {
  tested: "Built and tested",
  built: "Built, testing pending",
  prototype: "Prototype",
  planned: "Planned",
};

/** Text symbol shown next to each status, so status is not conveyed by color alone. */
export const STATUS_SYMBOL: Record<Status, string> = {
  tested: "✓",
  built: "●",
  prototype: "◐",
  planned: "○",
};

export interface Feature {
  name: string;
  summary: string;
  status: Status;
  statusNote: string;
}

/** Last time someone checked every status below against the repo. */
export const STATUS_CHECKED_ON = "October 24, 2026";

export const FEATURES: Feature[] = [
  {
    name: "Ride recording",
    summary:
      "Start, pause, resume and stop a ride. Live GPS route on a map, then a summary with distance, " +
      "time and average speed. Rides are stored on the phone and the whole flow works offline.",
    status: "planned",
    statusNote: "iOS app specified (23 tasks); implementation not started.",
  },
  {
    name: "Experimental rear-vehicle detection",
    summary:
      "The phone's rear camera looks for vehicles closing in from behind, on the device. Video never " +
      "leaves the phone.",
    status: "planned",
    statusNote: "Labeling rules and evaluation scripts are ready; the detector itself is not built.",
  },
  {
    name: "Caution cues you can feel or hear",
    summary:
      "A short vibration or sound when a vehicle is detected, so the rider never has to look at a " +
      "screen. Options under test: phone haptics, earbuds, and an Apple Watch tap.",
    status: "prototype",
    statusNote: "Apple Watch and Bluetooth test apps written; not yet run on devices.",
  },
  {
    name: "Private, opt-in cloud backup",
    summary:
      "Riders can choose to back up finished rides. Each rider sees only their own data, without an " +
      "email or password.",
    status: "tested",
    statusNote: "Database, access rules and upload limits pass 81 automated tests on a local database.",
  },
  {
    name: "Community map",
    summary:
      "Routes that riders chose to share, drawn together on one map, with totals for the whole " +
      "community.",
    status: "built",
    statusNote: "Database views tested; the website build is pending.",
  },
  {
    name: "Incident map",
    summary:
      "Where riders reported, or the app detected, close vehicles. Shown only as rounded areas with " +
      "enough reports from enough riders.",
    status: "built",
    statusNote: "Database view and privacy thresholds tested; website build pending; uses sample data for now.",
  },
];
