"use client";

import dynamic from "next/dynamic";

/** Client-only wrapper: `ssr: false` is only allowed in a Client Component. */
export const CommunityMapClient = dynamic(() => import("./CommunityMap"), {
  ssr: false,
  loading: () => (
    <div className="skeleton skeleton--map" role="status">
      <span className="visually-hidden">Loading map…</span>
    </div>
  ),
});
