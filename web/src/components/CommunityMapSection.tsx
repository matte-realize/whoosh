"use client";

import { useEffect, useState } from "react";
import { CommunityMapClient } from "./CommunityMapClient";
import { loadIncidentCells, type LoadIncidentsResult } from "@/lib/incidents";
import { loadRides, type LoadRidesResult } from "@/lib/rides";
import type { IncidentCell, Ride } from "@/lib/types";

const NO_RIDES: Ride[] = [];
const NO_CELLS: IncidentCell[] = [];

/**
 * The community map: all shared routes plus the incident cells, with the honesty note and a
 * text list of cells so nothing depends on the map alone. Either layer may fail on its own;
 * the map still shows whatever loaded.
 */
export default function CommunityMapSection() {
  const [rides, setRides] = useState<LoadRidesResult | null>(null);
  const [cells, setCells] = useState<LoadIncidentsResult | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadRides().then((loaded) => {
      if (!cancelled) setRides(loaded);
    });
    loadIncidentCells().then((loaded) => {
      if (!cancelled) setCells(loaded);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  // Stable empty arrays: a new [] on every render would make the map rebuild itself.
  const rideList = rides?.ok ? rides.rides : NO_RIDES;
  const cellList = cells?.ok ? cells.cells : NO_CELLS;
  const loading = rides === null || cells === null;
  const usingFixtures = (rides?.ok && rides.source === "fixtures") || (cells?.ok && cells.source === "fixtures");

  return (
    <section className="community" aria-labelledby="community-heading">
      <h2 id="community-heading">Community map</h2>
      <p className="note">
        Blue lines are rides riders chose to share, trimmed at both ends for privacy. Orange
        circles are unverified reports and experimental detections from riders who opted in,
        rounded to about 100 m, shown only after at least 3 reports from at least 2 riders, and
        delayed by a day. Not a safety rating: no reports does not mean safe.
      </p>

      {usingFixtures ? <p className="banner">Showing sample data, not real rides or reports.</p> : null}
      {rides !== null && !rides.ok ? (
        <p role="alert" className="message message--error">
          {rides.message}
        </p>
      ) : null}
      {cells !== null && !cells.ok ? (
        <p role="alert" className="message message--error">
          {cells.message}
        </p>
      ) : null}

      {loading ? (
        <p role="status" className="message">
          Loading map data…
        </p>
      ) : rideList.length === 0 && cellList.length === 0 ? (
        <p className="message">Nothing to show yet: no shared rides, and no area has enough reports.</p>
      ) : (
        <>
          <CommunityMapClient rides={rideList} cells={cellList} />
          <p className="note">
            {rideList.length} shared routes. {cellList.length} areas with enough reports to show.
          </p>
          {cellList.length > 0 ? (
            <ul className="incident-list" aria-label="Areas with incident reports">
              {cellList.map((cell) => (
                <li key={`${cell.latitude},${cell.longitude}`}>
                  {cell.incident_count} reports near {cell.latitude.toFixed(3)}, {cell.longitude.toFixed(3)} (
                  {cell.rider_reported_count} rider-reported, {cell.detected_count} detected)
                </li>
              ))}
            </ul>
          ) : null}
        </>
      )}
    </section>
  );
}
