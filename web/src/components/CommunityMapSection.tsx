"use client";

import { useEffect, useState } from "react";
import { CommunityMapClient } from "./CommunityMapClient";
import { loadIncidentCells, type LoadIncidentsResult } from "@/lib/incidents";
import { loadRides, type LoadRidesResult } from "@/lib/rides";
import type { IncidentCell, Ride } from "@/lib/types";

const NO_RIDES: Ride[] = [];
const NO_CELLS: IncidentCell[] = [];

/**
 * The community map: all shared routes plus the incident cells, with layer toggles, a legend,
 * the honesty note, and a text list of cells so nothing depends on the map alone. Either layer may
 * fail on its own; the map still shows whatever loaded.
 */
export default function CommunityMapSection() {
  const [rides, setRides] = useState<LoadRidesResult | null>(null);
  const [cells, setCells] = useState<LoadIncidentsResult | null>(null);
  const [showRoutes, setShowRoutes] = useState(true);
  const [showIncidents, setShowIncidents] = useState(true);
  const [showList, setShowList] = useState(false);

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
    <section className="community card" aria-labelledby="community-heading">
      <div className="section-head">
        <div>
          <h2 id="community-heading">Community map</h2>
          <p className="note">
            Routes riders chose to share, and areas where riders reported or the app detected close
            vehicles.
          </p>
        </div>
        {usingFixtures ? <span className="tag">Sample data</span> : null}
      </div>

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

      <div className="map-toolbar">
        <div className="chips" role="group" aria-label="Map layers">
          <button
            type="button"
            className="chip chip--route"
            aria-pressed={showRoutes}
            onClick={() => setShowRoutes((value) => !value)}
          >
            <span className="swatch swatch--route" aria-hidden="true" />
            Shared routes
            <span className="chip__count">{rideList.length}</span>
          </button>
          <button
            type="button"
            className="chip chip--incident"
            aria-pressed={showIncidents}
            onClick={() => setShowIncidents((value) => !value)}
          >
            <span className="swatch swatch--incident" aria-hidden="true" />
            Incident areas
            <span className="chip__count">{cellList.length}</span>
          </button>
        </div>
        <p className="map-toolbar__hint">Hover a route or circle for details. Click the map to zoom with the wheel.</p>
      </div>

      {loading ? (
        <div className="skeleton skeleton--map">
          <span className="visually-hidden">Loading map data…</span>
        </div>
      ) : rideList.length === 0 && cellList.length === 0 ? (
        <div className="empty-state">
          <h3>Nothing to show yet</h3>
          <p>No shared rides, and no area has enough reports to show.</p>
        </div>
      ) : (
        <CommunityMapClient rides={rideList} cells={cellList} showRoutes={showRoutes} showIncidents={showIncidents} />
      )}

      <p className="note note--small">
        Routes are trimmed at both ends for privacy. Incident areas are rounded to about 100 m and
        appear only after at least 3 reports from at least 2 riders, with a one-day delay. These are
        unverified reports and experimental detections. Not a safety rating: no reports does not
        mean safe.
      </p>

      {cellList.length > 0 ? (
        <div className="disclosure">
          <button
            type="button"
            className="link-button"
            aria-expanded={showList}
            aria-controls="incident-list"
            onClick={() => setShowList((value) => !value)}
          >
            {showList ? "Hide" : "Show"} incident areas as a list
          </button>
          {showList ? (
            <ul id="incident-list" className="incident-list">
              {cellList.map((cell) => (
                <li key={`${cell.latitude},${cell.longitude}`}>
                  <strong>{cell.incident_count} reports</strong> near {cell.latitude.toFixed(3)},{" "}
                  {cell.longitude.toFixed(3)} ({cell.rider_reported_count} rider-reported,{" "}
                  {cell.detected_count} detected)
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
