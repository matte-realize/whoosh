"use client";

import { RideMapClient } from "./RideMapClient";
import {
  formatDateTime,
  formatDistance,
  formatDuration,
  formatSpeed,
  formatTimeOfDay,
} from "@/lib/units";
import type { RideWithNearMisses } from "@/lib/types";

/** Stats and map for one ride. */
export function RideDetail({ ride }: { ride: RideWithNearMisses }) {
  const nearMisses = ride.near_misses ?? [];

  return (
    <article className="ride-detail" aria-labelledby="ride-detail-title">
      <h2 id="ride-detail-title">{formatDateTime(ride.started_at)}</h2>

      <dl className="stats">
        <div>
          <dt>Distance</dt>
          <dd>{formatDistance(ride.distance_m)}</dd>
        </div>
        <div>
          <dt>Active time</dt>
          <dd>{formatDuration(ride.active_duration_s)}</dd>
        </div>
        <div>
          <dt>Average speed</dt>
          <dd>{formatSpeed(ride.avg_speed_mps)}</dd>
        </div>
      </dl>

      <RideMapClient ride={ride} />
      <p className="note">
        The start and end of each route are trimmed for privacy, so the line is shorter than the
        distance shown.
      </p>

      {nearMisses.length > 0 ? (
        <section aria-labelledby="detections-title">
          <h3 id="detections-title">Experimental vehicle detections (sample data)</h3>
          <p className="note">
            Shown as dashed red circles on the map. These are experimental sample detections, not
            validated measurements.
          </p>
          <ul className="detections">
            {nearMisses.map((nearMiss) => (
              <li key={nearMiss.id}>
                {formatTimeOfDay(nearMiss.occurred_at)} · {nearMiss.kind} ·{" "}
                {Math.round(nearMiss.confidence * 100)}% confidence
                {nearMiss.position_hint ? ` · position: ${nearMiss.position_hint}` : ""}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </article>
  );
}
