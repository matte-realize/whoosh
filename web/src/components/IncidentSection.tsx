"use client";

import { useEffect, useState } from "react";
import { IncidentMapClient } from "./IncidentMapClient";
import { loadIncidentCells, type LoadIncidentsResult } from "@/lib/incidents";

/** The incident map, with the honesty note and a text list so nothing depends on the map alone. */
export default function IncidentSection() {
  const [result, setResult] = useState<LoadIncidentsResult | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadIncidentCells().then((loaded) => {
      if (!cancelled) setResult(loaded);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <section className="incidents" aria-labelledby="incidents-heading">
      <h2 id="incidents-heading">Incident map</h2>
      <p className="note">
        Unverified reports and experimental detections from riders who opted in. Places are
        rounded to about 100 m, shown only after at least 3 reports from at least 2 riders, and
        delayed by a day. Not a safety rating: no reports does not mean safe.
      </p>

      {result === null ? (
        <p role="status" className="message">
          Loading incidents…
        </p>
      ) : !result.ok ? (
        <p role="alert" className="message message--error">
          {result.message}
        </p>
      ) : (
        <>
          {result.source === "fixtures" ? (
            <p className="banner">Showing sample incident data, not real reports.</p>
          ) : null}
          {result.cells.length === 0 ? (
            <p className="message">No area has enough reports to show yet.</p>
          ) : (
            <>
              <IncidentMapClient cells={result.cells} />
              <ul className="incident-list">
                {result.cells.map((cell) => (
                  <li key={`${cell.latitude},${cell.longitude}`}>
                    {cell.incident_count} reports near {cell.latitude.toFixed(3)}, {cell.longitude.toFixed(3)}{" "}
                    ({cell.rider_reported_count} rider-reported, {cell.detected_count} detected)
                  </li>
                ))}
              </ul>
            </>
          )}
        </>
      )}
    </section>
  );
}
