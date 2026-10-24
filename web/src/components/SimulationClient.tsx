"use client";

import dynamic from "next/dynamic";

/** Client-only wrapper: the simulation draws on a canvas and uses browser APIs. */
const SimulationClient = dynamic(() => import("./SimulationDemo"), {
  ssr: false,
  loading: () => (
    <div className="skeleton skeleton--map" role="status">
      <span className="visually-hidden">Loading the simulation…</span>
    </div>
  ),
});

export default SimulationClient;
