"use client";

import { useEffect, useMemo, useState } from "react";
import { RideDetail } from "./RideDetail";
import { RideList } from "./RideList";
import { loadRides, type LoadRidesResult } from "@/lib/rides";
import type { RideWithNearMisses } from "@/lib/types";

type SortKey = "newest" | "longest" | "fastest";

const SORTS: { key: SortKey; label: string; compare: (a: RideWithNearMisses, b: RideWithNearMisses) => number }[] = [
  { key: "newest", label: "Newest first", compare: (a, b) => Date.parse(b.started_at) - Date.parse(a.started_at) },
  { key: "longest", label: "Longest first", compare: (a, b) => b.distance_m - a.distance_m },
  { key: "fastest", label: "Fastest average first", compare: (a, b) => b.avg_speed_mps - a.avg_speed_mps },
];

/** Loads rides once, then shows a sortable list and the selected ride. `null` means still loading. */
export default function Dashboard() {
  const [result, setResult] = useState<LoadRidesResult | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("newest");

  useEffect(() => {
    let cancelled = false;
    loadRides().then((loaded) => {
      if (!cancelled) setResult(loaded);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const rides = result?.ok ? result.rides : null;
  const sorted = useMemo(() => {
    if (rides === null) return [];
    const sort = SORTS.find((item) => item.key === sortKey) ?? SORTS[0];
    return [...rides].sort(sort.compare);
  }, [rides, sortKey]);

  if (result === null) {
    return (
      <div className="layout" aria-busy="true">
        <div className="ride-list">
          {Array.from({ length: 3 }, (_, index) => (
            <div key={index} className="skeleton skeleton--card" />
          ))}
        </div>
        <div className="skeleton skeleton--panel">
          <span className="visually-hidden">Loading rides…</span>
        </div>
      </div>
    );
  }

  if (!result.ok) {
    return (
      <p role="alert" className="message message--error">
        {result.message}
      </p>
    );
  }

  const selected = sorted.find((ride) => ride.id === selectedId) ?? sorted[0];

  return (
    <>
      {result.source === "fixtures" ? (
        <p className="banner">Showing bundled sample data, not live rides.</p>
      ) : null}

      {selected === undefined ? (
        <div className="empty-state">
          <h3>No shared rides yet</h3>
          <p>A ride appears here only after the rider chooses to share it.</p>
        </div>
      ) : (
        <div className="layout">
          <nav aria-label="Ride list" className="ride-browser">
            <div className="toolbar">
              <span className="toolbar__count">
                {sorted.length} {sorted.length === 1 ? "ride" : "rides"}
              </span>
              <label className="toolbar__sort">
                <span className="visually-hidden">Sort rides</span>
                <select value={sortKey} onChange={(event) => setSortKey(event.target.value as SortKey)}>
                  {SORTS.map((sort) => (
                    <option key={sort.key} value={sort.key}>
                      {sort.label}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <RideList rides={sorted} selectedId={selected.id} onSelect={setSelectedId} />
          </nav>
          <RideDetail ride={selected} />
        </div>
      )}
    </>
  );
}
