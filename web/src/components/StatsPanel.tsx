"use client";

import { useEffect, useState } from "react";
import { CountUp } from "./CountUp";
import { Icon, type IconName } from "./Icon";
import { loadStats, type LoadStatsResult } from "@/lib/stats";
import { formatDistance, formatDuration } from "@/lib/units";

const whole = (n: number) => Math.round(n).toLocaleString();

/** Totals over shared rides, as animated stat cards. Aggregates only; no individual data. */
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

  if (result !== null && !result.ok) {
    return (
      <p role="alert" className="message message--error">
        {result.message}
      </p>
    );
  }

  const stats = result?.ok ? result.stats : null;
  const cards: { label: string; icon: IconName; value: number | null; format: (n: number) => string; text?: string }[] =
    stats === null
      ? []
      : [
          { label: "Shared rides", icon: "bike", value: stats.shared_rides, format: whole },
          { label: "Distance", icon: "route", value: stats.total_distance_m, format: formatDistance },
          { label: "Riding time", icon: "clock", value: stats.total_active_duration_s, format: formatDuration },
          {
            label: "Riders",
            icon: "riders",
            value: stats.riders,
            format: whole,
            text: stats.riders === null ? "Fewer than 3" : undefined,
          },
          { label: "Incident reports mapped", icon: "alert", value: stats.mapped_incidents, format: whole },
        ];

  return (
    <section className="stats-panel" aria-labelledby="stats-heading" aria-busy={stats === null}>
      <div className="stats-panel__head">
        <h2 id="stats-heading">Shared so far</h2>
        {result?.ok && result.source === "fixtures" ? <span className="tag">Sample data</span> : null}
      </div>
      <dl className="stat-grid">
        {stats === null
          ? Array.from({ length: 5 }, (_, index) => (
              <div key={index} className="stat-card">
                <dt className="skeleton skeleton--text">Loading</dt>
                <dd className="skeleton skeleton--number" />
              </div>
            ))
          : cards.map((card) => (
              <div key={card.label} className="stat-card">
                <dt>
                  <Icon name={card.icon} />
                  {card.label}
                </dt>
                <dd>
                  {card.text !== undefined || card.value === null ? (
                    <span className="stat-card__muted">{card.text}</span>
                  ) : (
                    <CountUp value={card.value} format={card.format} />
                  )}
                </dd>
              </div>
            ))}
      </dl>
    </section>
  );
}
