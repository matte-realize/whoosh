"use client";

import { useEffect, useMemo, useState } from "react";
import { CommunityMapClient } from "./CommunityMapClient";
import { groupBySpot, loadCityCrashes, monthYear, type LoadCityCrashesResult } from "@/lib/cityCrashes";
import { loadIncidentCells, type LoadIncidentsResult } from "@/lib/incidents";
import { loadRides, type LoadRidesResult } from "@/lib/rides";
import type { CityCrashPoint, IncidentCell, Ride } from "@/lib/types";

const NO_RIDES: Ride[] = [];
const NO_CELLS: IncidentCell[] = [];
const NO_CRASHES: CityCrashPoint[] = [];

/**
 * The community map: all shared routes, the incident cells, and real city crash records, with layer toggles, a legend,
 * the honesty note, and a text list of cells so nothing depends on the map alone. Either layer may
 * fail on its own; the map still shows whatever loaded.
 */
export default function CommunityMapSection() {
  const [rides, setRides] = useState<LoadRidesResult | null>(null);
  const [cells, setCells] = useState<LoadIncidentsResult | null>(null);
  const [crashes, setCrashes] = useState<LoadCityCrashesResult | null>(null);
  const [showRoutes, setShowRoutes] = useState(true);
  const [showIncidents, setShowIncidents] = useState(true);
  const [showCityCrashes, setShowCityCrashes] = useState(true);
  const [showList, setShowList] = useState(false);

  useEffect(() => {
    let cancelled = false;
    loadRides().then((loaded) => {
      if (!cancelled) setRides(loaded);
    });
    loadIncidentCells().then((loaded) => {
      if (!cancelled) setCells(loaded);
    });
    loadCityCrashes().then((loaded) => {
      if (!cancelled) setCrashes(loaded);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  // Stable empty arrays: a new [] on every render would make the map rebuild itself.
  const rideList = rides?.ok ? rides.rides : NO_RIDES;
  const cellList = cells?.ok ? cells.cells : NO_CELLS;
  const crashList = crashes?.ok ? crashes.points : NO_CRASHES;
  // Memoized: the map rebuilds whenever this array changes identity.
  const crashSpots = useMemo(() => groupBySpot(crashList), [crashList]);
  const loading = rides === null || cells === null || crashes === null;
  const usingFixtures = (rides?.ok && rides.source === "fixtures") || (cells?.ok && cells.source === "fixtures");

  return (
    <section className="community card" aria-labelledby="community-heading">
      <div className="section-head">
        <div>
          <h2 id="community-heading">Community map</h2>
          <p className="note">
            Routes riders chose to share, areas where riders reported or the app detected close
            vehicles, and bike crashes the City of Boston has published.
          </p>
        </div>
        {usingFixtures ? <span className="tag">Sample rider data · real city data</span> : null}
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

      {crashes !== null && !crashes.ok ? (
        <p role="alert" className="message message--error">
          {crashes.message}
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
          <button
            type="button"
            className="chip chip--city"
            aria-pressed={showCityCrashes}
            onClick={() => setShowCityCrashes((value) => !value)}
          >
            <span className="swatch swatch--city" aria-hidden="true" />
            City-reported bike crashes
            <span className="chip__count">{crashList.length}</span>
          </button>
        </div>
        <p className="map-toolbar__hint">Hover a route or circle for details. Click the map to zoom with the wheel.</p>
      </div>

      {loading ? (
        <div className="skeleton skeleton--map">
          <span className="visually-hidden">Loading map data…</span>
        </div>
      ) : rideList.length === 0 && cellList.length === 0 && crashList.length === 0 ? (
        <div className="empty-state">
          <h3>Nothing to show yet</h3>
          <p>No shared rides, and no area has enough reports to show.</p>
        </div>
      ) : (
        <CommunityMapClient
          rides={rideList}
          cells={cellList}
          crashSpots={crashSpots}
          showRoutes={showRoutes}
          showIncidents={showIncidents}
          showCityCrashes={showCityCrashes}
        />
      )}

      <p className="note note--small">
        Routes are trimmed at both ends for privacy. Incident areas are rounded to about 100 m and
        appear only after at least 3 reports from at least 2 riders, with a one-day delay. These are
        unverified reports and experimental detections. Not a safety rating: no reports does not
        mean safe.
      </p>

      {crashes?.ok && crashes.sources.length > 0 ? (
        <p className="note note--small source-note">
          City-reported bike crashes:{" "}
          {crashes.sources.map((source, index) => (
            <span key={source.key}>
              {index > 0 ? "; " : null}
              <a href={source.url} target="_blank" rel="noopener noreferrer">
                {source.publisher}, {source.name}
              </a>{" "}
              ({source.license}
              {source.data_through ? `, through ${monthYear(source.data_through)}` : ""})
            </span>
          ))}
          . These are 911 dispatches on city-owned streets that needed a public safety response,
          located by intersection or street segment. Times are dispatch times, and severity is not
          published.
          Many bike crashes are never reported to 911, so fewer circles does not mean safer.
        </p>
      ) : null}

      {cellList.length > 0 || crashSpots.length > 0 ? (
        <div className="disclosure">
          <button
            type="button"
            className="link-button"
            aria-expanded={showList}
            aria-controls="incident-list"
            onClick={() => setShowList((value) => !value)}
          >
            {showList ? "Hide" : "Show"} incident areas and city crash locations as a list
          </button>
          {showList ? (
            <ul id="incident-list" className="incident-list">
              {cellList.map((cell) => (
                <li key={`${cell.latitude},${cell.longitude}`}>
                  <strong>{cell.incident_count} rider reports</strong> near {cell.latitude.toFixed(3)},{" "}
                  {cell.longitude.toFixed(3)} ({cell.rider_reported_count} rider-reported,{" "}
                  {cell.detected_count} detected)
                </li>
              ))}
              {crashSpots.map((spot) => (
                <li key={`city-${spot.latitude},${spot.longitude}`}>
                  <strong>
                    {spot.count} city-reported {spot.count === 1 ? "crash" : "crashes"}
                  </strong>{" "}
                  at {spot.label} ({spot.firstYear === spot.lastYear ? spot.firstYear : `${spot.firstYear} to ${spot.lastYear}`})
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
