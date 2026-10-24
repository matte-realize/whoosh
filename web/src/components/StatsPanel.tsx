"use client";

import { useEffect, useState } from "react";
import { loadStats, type LoadStatsResult } from "@/lib/stats";
import { formatDistance, formatDuration } from "@/lib/units";

/** Big-screen totals over shared rides. Aggregates only; no individual data. */
export default function StatsPanel() {
  const [result, setResult] = useState<LoadStatsResult | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadStats().then((loaded) => {
      if (!cancelled) setResult(loaded);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  if (result === null) {
    return (
      <p role="status" className="message">
        Loading totals…
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

  const { stats } = result;
  return (
    <section className="stats-panel" aria-labelledby="stats-heading">
      <h2 id="stats-heading">Shared so far{result.source === "fixtures" ? " (sample data)" : ""}</h2>
      <dl className="stats">
        <div>
          <dt>Shared rides</dt>
          <dd>{stats.shared_rides}</dd>
        </div>
        <div>
          <dt>Distance</dt>
          <dd>{formatDistance(stats.total_distance_m)}</dd>
        </div>
        <div>
          <dt>Riding time</dt>
          <dd>{formatDuration(stats.total_active_duration_s)}</dd>
        </div>
        <div>
          <dt>Riders</dt>
          <dd>{stats.riders === null ? "Fewer than 3" : stats.riders}</dd>
        </div>
        <div>
          <dt>Mapped incident reports</dt>
          <dd>{stats.mapped_incidents}</dd>
        </div>
      </dl>
    </section>
  );
}
