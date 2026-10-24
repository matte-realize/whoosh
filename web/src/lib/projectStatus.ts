/**
 * What the home page says is available. Written for riders, not engineers, and kept truthful:
 * a feature is "Preview online" only if a visitor can try it on this website today. Update this
 * file, and only this file, as things ship.
 */

export type Status = "preview" | "testing" | "development";

export const STATUS_LABEL: Record<Status, string> = {
  preview: "Try it now",
  testing: "Testing prototypes",
  development: "In development",
};

/** Text symbol shown next to each status, so status is not conveyed by color alone. */
export const STATUS_SYMBOL: Record<Status, string> = {
  preview: "✓",
  testing: "◐",
  development: "○",
};

export interface Feature {
  name: string;
  summary: string;
  status: Status;
  statusNote: string;
}

/** Last time someone checked every status below. */
export const STATUS_CHECKED_ON = "October 24, 2026";

export const FEATURES: Feature[] = [
  {
    name: "A heads-up for traffic behind you",
    summary:
      "Your phone's back camera watches the road behind your bike and lets you know when a car is coming up.",
    status: "development",
    statusNote: "Experimental, and not measured yet. Being built and tested now.",
  },
  {
    name: "Feel it or hear it",
    summary: "A tap on your wrist or a short tone, so your eyes never have to leave the road ahead.",
    status: "testing",
    statusNote: "We are trying a watch tap, phone vibration, and sound.",
  },
  {
    name: "Ride tracking that works offline",
    summary: "Your route, distance, time and speed, saved on your phone. No signal needed.",
    status: "development",
    statusNote: "The iPhone app is being built.",
  },
  {
    name: "Private by default",
    summary: "No account. Your rides stay on your phone unless you choose to back them up or share them.",
    status: "development",
    statusNote: "The secure storage behind it is built and tested; the app side is being built.",
  },
  {
    name: "Ride map",
    summary: "See the routes riders chose to share, all on one map.",
    status: "preview",
    statusNote: "Open the ride map to explore it with sample rides.",
  },
  {
    name: "Close-call map",
    summary: "Spots where riders reported cars passing too close, shown only once several riders agree.",
    status: "preview",
    statusNote: "On the ride map, with sample reports.",
  },
  {
    name: "See it in action",
    summary: "A 3D simulation of a ride, showing when and how the heads-up works.",
    status: "preview",
    statusNote: "Runs in your browser.",
  },
];
