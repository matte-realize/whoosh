"use client";

import { useEffect, useState } from "react";
import { Bars, type Bar } from "./Bars";
import { Ring } from "./Ring";
import {
  countByBlock,
  countByYear,
  loadCityCrashes,
  monthYear,
  streetName,
  type LoadCityCrashesResult,
} from "@/lib/cityCrashes";
import { loadIncidentCells, type LoadIncidentsResult } from "@/lib/incidents";
import { loadRides, type LoadRidesResult } from "@/lib/rides";
import { formatDistance } from "@/lib/units";

/** Hour of day in Boston, so the buckets match the riders' local time whatever the viewer's zone. */
function bostonHour(iso: string): number | null {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  const hour = new Intl.DateTimeFormat("en-US", { hour: "numeric", hourCycle: "h23", timeZone: "America/New_York" })
    .formatToParts(date)
    .find((part) => part.type === "hour");
  return hour ? Number(hour.value) : null;
}

const BUCKETS: { label: string; from: number; to: number }[] = [
  { label: "Morning", from: 5, to: 11 },
  { label: "Midday", from: 11, to: 15 },
  { label: "Evening", from: 15, to: 20 },
  { label: "Night", from: 20, to: 29 },
];

function bucketFor(hour: number): string {
  const h = hour < 5 ? hour + 24 : hour;
  return BUCKETS.find((bucket) => h >= bucket.from && h < bucket.to)?.label ?? "Night";
}

/** Charts computed from the shared rides, incident areas, and city crash records the page already loaded. */
export default function CommunityInsights() {
  const [rides, setRides] = useState<LoadRidesResult | null>(null);
  const [cells, setCells] = useState<LoadIncidentsResult | null>(null);
  const [crashes, setCrashes] = useState<LoadCityCrashesResult | null>(null);

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

  if (rides === null || cells === null || crashes === null) {
    return <div className="skeleton skeleton--panel insights-skeleton" aria-busy="true" />;
  }

  const rideList = rides.ok ? rides.rides : [];
  const cellList = cells.ok ? cells.cells : [];
  const crashList = crashes.ok ? crashes.points : [];
  if (rideList.length === 0 && cellList.length === 0 && crashList.length === 0) return null;

  const timeBars: Bar[] = BUCKETS.map((bucket) => ({ label: bucket.label, value: 0 }));
  for (const ride of rideList) {
    const hour = bostonHour(ride.started_at);
    if (hour === null) continue;
    const bar = timeBars.find((item) => item.label === bucketFor(hour));
    if (bar) bar.value += 1;
  }

  const distanceBars: Bar[] = [...rideList]
    .sort((a, b) => b.distance_m - a.distance_m)
    .slice(0, 5)
    .map((ride) => ({
      label: new Date(ride.started_at).toLocaleDateString(undefined, { month: "short", day: "numeric" }),
      value: ride.distance_m,
      display: formatDistance(ride.distance_m),
    }));

  const riderReported = cellList.reduce((sum, cell) => sum + cell.rider_reported_count, 0);
  const detected = cellList.reduce((sum, cell) => sum + cell.detected_count, 0);
  const reports = riderReported + detected;

  const kindCounts = new Map<string, number>();
  for (const cell of cellList) {
    for (const kind of cell.vehicle_kinds) kindCounts.set(kind, (kindCounts.get(kind) ?? 0) + 1);
  }
  const kindBars: Bar[] = [...kindCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([kind, count]) => ({ label: kind === "vehicle" ? "Unspecified" : kind[0].toUpperCase() + kind.slice(1), value: count }));

  const dataThrough = crashes.ok ? crashes.sources.find((source) => source.data_through)?.data_through ?? null : null;
  const throughYear = dataThrough ? Number(dataThrough.slice(0, 4)) : null;
  const yearRows = countByYear(crashList);
  const yearBars: Bar[] = yearRows.map(({ year, count }) => ({
    label: year === throughYear && dataThrough && !dataThrough.endsWith("-12-31") ? `${year}*` : String(year),
    value: count,
  }));
  const blockRows = countByBlock(crashList);
  // When every record is on one street (the Mass Ave snapshot), name it once in the heading.
  const streets = new Set(crashList.map((point) => point.street));
  const oneStreet = streets.size === 1 && crashList[0]?.street ? streetName(crashList[0].street) : null;
  const blockBars: Bar[] = blockRows.slice(0, 5).map(({ label, count }) => ({
    label: oneStreet && label.startsWith(`${oneStreet}, `) ? label.slice(oneStreet.length + 2) : label,
    value: count,
  }));
  const topFiveShare = crashList.length > 0 ? blockRows.slice(0, 5).reduce((sum, row) => sum + row.count, 0) / crashList.length : 0;

  return (
    <section className="insights card" aria-labelledby="insights-heading">
      <div className="section-head">
        <div>
          <p className="eyebrow">Insights</p>
          <h2 id="insights-heading">What riders share, next to what the city records</h2>
        </div>
      </div>

      <div className="insights__grid">
        {reports > 0 ? (
          <div className="insight">
            <h3>Close calls, by who spotted them</h3>
            <div className="insight__rings">
              <Ring
                value={riderReported / reports}
                display={`${Math.round((riderReported / reports) * 100)}%`}
                label="Rider reported"
                caption={`${riderReported} of ${reports} reports`}
                tone="amber"
                size={128}
              />
              <Ring
                value={detected / reports}
                display={`${Math.round((detected / reports) * 100)}%`}
                label="Detected by the app"
                caption={`${detected} of ${reports} · experimental`}
                tone="red"
                size={128}
              />
            </div>
          </div>
        ) : null}

        {rideList.length > 0 ? (
          <div className="insight">
            <h3>When shared rides start</h3>
            <Bars bars={timeBars} tone="green" label="Shared rides by time of day, Boston time" />
            <p className="note note--small">Boston time. Counts of shared rides.</p>
          </div>
        ) : null}

        {distanceBars.length > 0 ? (
          <div className="insight">
            <h3>Longest shared rides</h3>
            <Bars bars={distanceBars} tone="blue" label="Longest shared rides by distance" />
          </div>
        ) : null}

        {yearBars.length > 0 ? (
          <div className="insight">
            <h3>City-reported bike crashes, by year</h3>
            <Bars bars={yearBars} tone="amber" label="City-reported bike crashes per year, Boston time" />
            <p className="note note--small">
              {crashList.length} records in total.
              {dataThrough ? ` * Partial year: data through ${monthYear(dataThrough)}.` : ""} With counts
              this small, a change from one year to the next is mostly chance.
            </p>
          </div>
        ) : null}

        {blockBars.length > 0 ? (
          <div className="insight">
            <h3>{oneStreet ? `${oneStreet} blocks` : "Blocks"} with the most city-reported bike crashes</h3>
            <Bars bars={blockBars} tone="amber" stacked label="Blocks with the most city-reported bike crashes" />
            <p className="note note--small">
              These 5 of {blockRows.length} blocks hold {Math.round(topFiveShare * 100)}% of the {crashList.length}{" "}
              records. Counts, not rates: busier blocks see more riders.
            </p>
          </div>
        ) : null}

        {kindBars.length > 0 ? (
          <div className="insight">
            <h3>Vehicles in close-call areas</h3>
            <Bars bars={kindBars} tone="violet" label="Number of close-call areas each vehicle type appears in" />
            <p className="note note--small">Number of areas where each type was reported at least once.</p>
          </div>
        ) : null}
      </div>
    </section>
  );
}
