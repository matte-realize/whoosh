"use client";

import dynamic from "next/dynamic";

/** Client-only wrapper: `ssr: false` is only allowed in a Client Component. */
export const CommunityMapClient = dynamic(() => import("./CommunityMap"), {
  ssr: false,
  loading: () => (
    <div className="ride-map community-map ride-map--loading" role="status">
      Loading map…
    </div>
  ),
});
