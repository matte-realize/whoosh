"use client";

import { RideMapClient } from "./RideMapClient";
import { Ring } from "./Ring";
import {
  formatDateTime,
  formatDistance,
  formatDuration,
  formatSpeed,
  formatTimeOfDay,
} from "@/lib/units";
import type { RideWithNearMisses } from "@/lib/types";

export interface RideBests {
  distance_m: number;
  active_duration_s: number;
  avg_speed_mps: number;
}

/** Stats, rings and map for one ride. Each ring compares the ride with the best shared ride. */
export function RideDetail({ ride, bests }: { ride: RideWithNearMisses; bests: RideBests }) {
  const nearMisses = ride.near_misses ?? [];
  const share = (value: number, best: number) => (best > 0 ? value / best : 0);

  return (
    <article className="ride-detail" aria-labelledby="ride-detail-title">
      <p className="eyebrow">Ride</p>
      <h2 id="ride-detail-title">{formatDateTime(ride.started_at)}</h2>

      <div className="ride-rings">
        <Ring
          value={share(ride.distance_m, bests.distance_m)}
          display={formatDistance(ride.distance_m)}
          label="Distance"
          caption={`Longest shared: ${formatDistance(bests.distance_m)}`}
          tone="blue"
          size={132}
        />
        <Ring
          value={share(ride.active_duration_s, bests.active_duration_s)}
          display={formatDuration(ride.active_duration_s)}
          label="Riding time"
          caption={`Longest shared: ${formatDuration(bests.active_duration_s)}`}
          tone="green"
          size={132}
        />
        <Ring
          value={share(ride.avg_speed_mps, bests.avg_speed_mps)}
          display={formatSpeed(ride.avg_speed_mps).replace(" mph", "")}
          label="Avg speed, mph"
          caption={`Fastest shared: ${formatSpeed(bests.avg_speed_mps)}`}
          tone="amber"
          size={132}
        />
      </div>
      <p className="note note--small">Each ring fills to this ride&apos;s share of the best shared ride.</p>

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
