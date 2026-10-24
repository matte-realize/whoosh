"use client";

import dynamic from "next/dynamic";

/** Client-only wrapper: `ssr: false` is only allowed in a Client Component. */
export const RideMapClient = dynamic(() => import("./RideMap"), {
  ssr: false,
  loading: () => (
    <div className="ride-map ride-map--loading" role="status">
      Loading map…
    </div>
  ),
});
