// The two scripted rides in the film. Times are seconds into each ride.

/** Act 1, the problem: no Whoosh. A car goes by, then one passes close. */
export const ACT1 = {
  key: "film",
  label: "Film act 1",
  description: "",
  loopSeconds: 1000,
  spawns: [
    { at: 0, lane: "travel", kind: "car", speed: 21 },
    { at: 1.5, lane: "oncoming", kind: "bus", speed: 10 },
    { at: 0.3, lane: "close", kind: "car", speed: 16.5 },
    { at: 6, lane: "oncoming", kind: "car", speed: 13 },
  ].sort((a, b) => a.at - b.at),
};

/** Acts 2 to 5: one continuous ride with Whoosh, from mounting the phone to the crash alert. */
export const RIDE = {
  key: "film",
  label: "Film ride",
  description: "",
  loopSeconds: 1000,
  rideStartsAt: 9,
  crashAt: 30,
  spawns: [
    { at: 4, lane: "oncoming", kind: "car", speed: 13 },
    { at: 11.5, lane: "close", kind: "car", speed: 16 },
    { at: 13, lane: "oncoming", kind: "truck", speed: 11 },
    { at: 19, lane: "oncoming", kind: "car", speed: 12 },
    { at: 24, lane: "travel", kind: "bus", speed: 10.5 },
    { at: 31, lane: "oncoming", kind: "car", speed: 9 },
    { at: 38, lane: "oncoming", kind: "car", speed: 8 },
    { at: 41, lane: "travel", kind: "car", speed: 9 },
  ],
};
