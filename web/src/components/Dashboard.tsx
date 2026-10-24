"use client";

import { useEffect, useState } from "react";
import { RideDetail } from "./RideDetail";
import { RideList } from "./RideList";
import { loadRides, type LoadRidesResult } from "@/lib/rides";

/** Loads rides once, then shows the list and the selected ride. `null` means still loading. */
export default function Dashboard() {
  const [result, setResult] = useState<LoadRidesResult | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadRides().then((loaded) => {
      if (!cancelled) setResult(loaded);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  if (result === null) {
    return (
      <p role="status" className="message">
        Loading rides…
      </p>
    );
  }

  if (!result.ok) {
    return (
      <p role="alert" className="message message--error">
        {result.message}
      </p>
    );
  }

  const { rides, source } = result;
  const selected = rides.find((ride) => ride.id === selectedId) ?? rides[0];

  return (
    <>
      {source === "fixtures" ? (
        <p className="banner">Showing bundled sample data, not live rides.</p>
      ) : null}

      {selected === undefined ? (
        <p className="message">
          No shared rides yet. A ride appears here only after the rider chooses to share it.
        </p>
      ) : (
        <div className="layout">
          <nav aria-label="Ride list">
            <RideList rides={rides} selectedId={selected.id} onSelect={setSelectedId} />
          </nav>
          <RideDetail ride={selected} />
        </div>
      )}
    </>
  );
}
