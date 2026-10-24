/**
 * What the home page says is available. Written for riders, not engineers, and kept truthful:
 * a feature is "Try it now" only if a visitor can try it on this website today. Update this
 * file, and only this file, as things ship.
 */

export type Status = "preview" | "testing" | "development";

export const STATUS_LABEL: Record<Status, string> = {
  preview: "Try it now",
  testing: "Being tested",
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

/** Last time someone checked every status below against the repo. */
export const STATUS_CHECKED_ON = "October 24, 2026";

export const FEATURES: Feature[] = [
  {
    name: "Ride tracking that works offline",
    summary: "Your route, distance, time and speed, saved on your phone. No signal needed.",
    status: "testing",
    statusNote: "Recording, the live map, ride summaries and history are built in the iPhone app and being tested.",
  },
  {
    name: "A heads-up for traffic behind you",
    summary:
      "Your phone's back camera watches the road behind your bike and lets you know when a car is coming up.",
    status: "development",
    statusNote: "The vehicle detector finds cars in test footage. It isn't connected to the app yet, and it hasn't been measured.",
  },
  {
    name: "Feel it or hear it",
    summary: "A tap on your wrist or a short tone, so your eyes never have to leave the road ahead.",
    status: "testing",
    statusNote: "We are trying a watch tap, phone vibration, and sound.",
  },
  {
    name: "Crash alerts to your contacts",
    summary:
      "If your phone detects a possible crash and you don't cancel, Whoosh texts your emergency contacts where you are.",
    status: "development",
    statusNote: "The texting service is built; the app side is being built. It is not an emergency service.",
  },
  {
    name: "Private by default",
    summary: "No account. Your rides stay on your phone unless you choose to back them up or share them.",
    status: "development",
    statusNote: "The secure storage behind backup is built and tested; turning it on in the app comes next.",
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
    name: "Real crash history",
    summary: "Bike crashes the City of Boston has published, on the same map as riders' close calls.",
    status: "preview",
    statusNote: "On the ride map: 65 city-reported bike crashes on Mass Ave since 2015, public data.",
  },
  {
    name: "See it in action",
    summary: "A 3D simulation of a ride, showing when and how the heads-up works.",
    status: "preview",
    statusNote: "Runs in your browser.",
  },
];
