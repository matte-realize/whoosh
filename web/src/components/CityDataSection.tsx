"use client";

import { useEffect, useMemo, useState } from "react";
import { Bars, type Bar } from "./Bars";
import { loadCityCrashes, monthYear, type LoadCityCrashesResult } from "@/lib/cityCrashes";
import {
  counterLabel,
  counterOnLanes,
  countsAround,
  equalRateP,
  laneProjects,
  loadBikeCounts,
  loadBikeNetwork,
  loadCrashContext,
  PANDEMIC_YEARS,
  PROTECTION_LABEL,
  routeLengthM,
  type LoadBikeCountsResult,
  type LoadBikeNetworkResult,
  type LoadCrashContextResult,
} from "@/lib/cityStreets";

const number = new Intl.NumberFormat("en-US");

function yearsText(years: number): string {
  const rounded = Math.round(years * 10) / 10;
  return `${rounded} ${rounded === 1 ? "year" : "years"}`;
}

function perYear(crashes: number, years: number): string {
  return years > 0 ? (crashes / years).toFixed(1) : "–";
}

function range(first: number, last: number): string {
  return first === last ? String(first) : `${first} to ${last}`;
}

/**
 * Real city data in numbers: bike counts, the bike lane inventory, and city-reported crashes
 * matched to the lane that was there. Every figure states its sample size. Nothing here is
 * Whoosh rider data.
 */
export default function CityDataSection() {
  const [crashes, setCrashes] = useState<LoadCityCrashesResult | null>(null);
  const [network, setNetwork] = useState<LoadBikeNetworkResult | null>(null);
  const [counts, setCounts] = useState<LoadBikeCountsResult | null>(null);
  const [context, setContext] = useState<LoadCrashContextResult | null>(null);
  const [counterId, setCounterId] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadCityCrashes().then((loaded) => !cancelled && setCrashes(loaded));
    loadBikeNetwork().then((loaded) => !cancelled && setNetwork(loaded));
    loadBikeCounts().then((loaded) => !cancelled && setCounts(loaded));
    loadCrashContext().then((loaded) => !cancelled && setContext(loaded));
    return () => {
      cancelled = true;
    };
  }, []);

  const lanes = useMemo(() => (network?.ok ? network.facilities : []), [network]);
  const counters = useMemo(() => (counts?.ok ? counts.locations : []), [counts]);
  const years = useMemo(() => (counts?.ok ? counts.years : []), [counts]);
  const contextRows = useMemo(() => (context?.ok ? context.rows : []), [context]);
  const crashPoints = useMemo(() => (crashes?.ok ? crashes.points : []), [crashes]);
  const crashSource = crashes?.ok ? crashes.sources.find((source) => source.data_through) : undefined;

  const crashFirstYear = useMemo(
    () => (crashPoints.length > 0 ? Math.min(...crashPoints.map((p) => new Date(p.occurred_at).getUTCFullYear())) : null),
    [crashPoints],
  );

  const project = useMemo(() => {
    if (crashFirstYear === null || !crashSource?.data_through) return null;
    const found = laneProjects(lanes, contextRows, crashFirstYear, crashSource.data_through)[0];
    if (!found) return null;
    const counter = counterOnLanes(counters, lanes, found.facilityIds);
    return {
      ...found,
      counter,
      volume: counter ? countsAround(years, counter.location_id, found.installYear) : null,
      pValue: equalRateP(found.before.crashes, found.before.years, found.after.crashes, found.after.years),
    };
  }, [lanes, contextRows, counters, years, crashFirstYear, crashSource]);

  if (crashes === null || network === null || counts === null || context === null) {
    return <div className="skeleton skeleton--panel insights-skeleton" aria-busy="true" />;
  }
  if (lanes.length === 0 && counters.length === 0 && crashPoints.length === 0) return null;

  // --- Headline numbers ---
  const laneLength = lanes.reduce((sum, lane) => sum + routeLengthM(lane.route.coordinates), 0);
  const protectedLength = lanes
    .filter((lane) => lane.protection === "separated" || lane.protection === "partly_separated")
    .reduce((sum, lane) => sum + routeLengthM(lane.route.coordinates), 0);
  const busiest = [...counters].sort((a, b) => b.latest_avg_daily_bikes - a.latest_avg_daily_bikes)[0];

  // --- Counters, latest year ---
  const counterBars: Bar[] = [...counters]
    .sort((a, b) => b.latest_avg_daily_bikes - a.latest_avg_daily_bikes)
    .map((counter) => ({
      label: `${counterLabel(counter.name)} (${counter.last_year}, ${counter.latest_year_days} days)`,
      value: counter.latest_avg_daily_bikes,
      display:
        counter.latest_bike_share === null
          ? number.format(counter.latest_avg_daily_bikes)
          : `${number.format(counter.latest_avg_daily_bikes)} · ${Math.round(counter.latest_bike_share * 100)}%`,
    }));

  // --- One counter over the years ---
  const selectedId = counterId ?? project?.counter?.location_id ?? busiest?.location_id ?? null;
  const selected = counters.find((counter) => counter.location_id === selectedId) ?? null;
  const yearBars: Bar[] = years
    .filter((year) => year.location_id === selectedId)
    .sort((a, b) => a.year - b.year)
    .map((year) => ({
      label: project && selected && project.counter?.location_id === selected.location_id && year.year > project.installYear
        ? `${year.year} ●`
        : String(year.year),
      value: year.avg_daily_bikes,
      display: `${number.format(year.avg_daily_bikes)} · ${year.days_counted}d`,
    }));

  // --- Crashes by the lane there at the time ---
  const tally = { separated: 0, partly_separated: 0, painted: 0, other: 0, before: 0, sameYear: 0, none: 0 };
  for (const row of contextRows) {
    if (row.facility_code === null) tally.none += 1;
    else if (row.facility_status === "before_install") tally.before += 1;
    else if (row.facility_status === "install_year" || row.facility_status === null) tally.sameYear += 1;
    else if (row.protection === "separated") tally.separated += 1;
    else if (row.protection === "partly_separated") tally.partly_separated += 1;
    else if (row.protection === "painted") tally.painted += 1;
    else tally.other += 1;
  }
  const crashLaneBars: Bar[] = [
    { label: `${PROTECTION_LABEL.separated}, already there`, value: tally.separated },
    { label: `${PROTECTION_LABEL.partly_separated}, already there`, value: tally.partly_separated },
    { label: `${PROTECTION_LABEL.painted}, already there`, value: tally.painted },
    { label: "Shared lane or path, already there", value: tally.other },
    { label: "Before today's lane was built", value: tally.before },
    { label: "No mapped lane within 25 m", value: tally.none },
  ].filter((bar) => bar.value > 0);
  const classified = crashLaneBars.reduce((sum, bar) => sum + bar.value, 0);

  const sources = [
    ...(counts.ok ? counts.sources : []),
    ...(network.ok ? network.sources : []),
    ...(crashes.ok ? crashes.sources : []),
  ].filter((source, index, all) => all.findIndex((other) => other.key === source.key) === index);

  return (
    <section className="city-data card" aria-labelledby="city-data-heading">
      <div className="section-head">
        <div>
          <p className="eyebrow">Public data</p>
          <h2 id="city-data-heading">What the city measures on the same street</h2>
          <p className="note">
            Real records published by the City of Boston: how many bikes its counters see, which
            lanes are on each block, and where bike crashes were reported. Not Whoosh rider data.
          </p>
        </div>
        <span className="tag">Real data</span>
      </div>

      <dl className="city-data__numbers">
        {lanes.length > 0 ? (
          <div>
            <dt>Mapped bike lane</dt>
            <dd>
              {(laneLength / 1000).toFixed(1)}
              <span className="city-data__unit"> km</span>
            </dd>
            <p className="city-data__caption">
              {Math.round((protectedLength / laneLength) * 100)}% separated on at least one side
            </p>
          </div>
        ) : null}
        {busiest ? (
          <div>
            <dt>Busiest counter</dt>
            <dd>
              {number.format(busiest.latest_avg_daily_bikes)}
              <span className="city-data__unit"> bikes a day</span>
            </dd>
            <p className="city-data__caption">
              {counterLabel(busiest.name)}, {busiest.last_year} average of {busiest.latest_year_days} count days
            </p>
          </div>
        ) : null}
        {crashPoints.length > 0 && crashFirstYear !== null ? (
          <div>
            <dt>City-reported bike crashes</dt>
            <dd>{crashPoints.length}</dd>
            <p className="city-data__caption">
              Since {crashFirstYear}
              {crashSource?.data_through ? `, through ${monthYear(crashSource.data_through)}` : ""}
            </p>
          </div>
        ) : null}
      </dl>

      <div className="insights__grid">
        {counterBars.length > 0 ? (
          <div className="insight">
            <h3>Bikes counted per day</h3>
            <Bars bars={counterBars} tone="green" stacked label="Average bikes per day at each city counter, latest year" />
            <p className="note note--small">
              Average of the full days counted in each counter&apos;s latest year, both directions. The
              percentage is bikes as a share of all counted vehicles. Counters run a few days a year,
              so these are snapshots, not yearly totals.
            </p>
          </div>
        ) : null}

        {selected && yearBars.length > 0 ? (
          <div className="insight">
            <h3>Bikes per day over the years</h3>
            <div className="chips chips--small" role="group" aria-label="Choose a counter">
              {counters.map((counter) => (
                <button
                  key={counter.location_id}
                  type="button"
                  className="chip"
                  aria-pressed={counter.location_id === selectedId}
                  onClick={() => setCounterId(counter.location_id)}
                >
                  {counterLabel(counter.name)}
                </button>
              ))}
            </div>
            <Bars bars={yearBars} tone="blue" label={`Average bikes per day by year, ${selected.name}`} />
            <p className="note note--small">
              Each bar averages that year&apos;s count days (the number after the dot). Months
              counted vary by year, and {PANDEMIC_YEARS.join(" and ")} were pandemic years.
              {project && project.counter?.location_id === selected.location_id
                ? ` ● marks years after the ${project.installYear} separated lanes on these blocks.`
                : ""}
            </p>
          </div>
        ) : null}

        {crashLaneBars.length > 0 ? (
          <div className="insight">
            <h3>Crashes, by the lane there at the time</h3>
            <Bars bars={crashLaneBars} tone="amber" stacked label="City-reported bike crashes by the bike lane in place at the time" />
            <p className="note note--small">
              {classified} crashes, each matched to the nearest mapped lane.
              {tally.sameYear > 0 ? ` ${tally.sameYear} more happened in the year their lane was built and are left out.` : ""}{" "}
              Counts, not rates: the lanes differ in length, traffic, and years in place. The
              inventory does not say what was there before today&apos;s lane.
            </p>
          </div>
        ) : null}
      </div>

      {project ? (
        <div className="city-data__callout">
          <h3>
            The {project.installYear} {project.protection === "separated" ? "separated" : "partly separated"} lanes,{" "}
            {(project.lengthM / 1000).toFixed(1)} km
          </h3>
          <dl className="before-after">
            <div>
              <dt>
                Before, {range(project.before.firstYear, project.before.lastYear)} ({yearsText(project.before.years)})
              </dt>
              <dd>
                {perYear(project.before.crashes, project.before.years)}
                <span className="city-data__unit"> crashes a year</span>
              </dd>
              <p className="city-data__caption">{project.before.crashes} city-reported bike crashes</p>
            </div>
            <div>
              <dt>
                After, {range(project.after.firstYear, project.after.lastYear)} ({yearsText(project.after.years)})
              </dt>
              <dd>
                {perYear(project.after.crashes, project.after.years)}
                <span className="city-data__unit"> crashes a year</span>
              </dd>
              <p className="city-data__caption">{project.after.crashes} city-reported bike crashes</p>
            </div>
            {project.counter && project.volume ? (
              <div>
                <dt>Bikes a day, {counterLabel(project.counter.name).toLowerCase()}</dt>
                <dd>
                  {number.format(project.volume.before.avg)} → {number.format(project.volume.after.avg)}
                </dd>
                <p className="city-data__caption">
                  {range(project.volume.before.firstYear, project.volume.before.lastYear)} ({project.volume.before.days} days) vs{" "}
                  {range(project.volume.after.firstYear, project.volume.after.lastYear)} ({project.volume.after.days} days),
                  without {PANDEMIC_YEARS.join(" and ")}
                </p>
              </div>
            ) : null}
          </dl>
          <p className="note note--small">
            The install year is left out of both sides.{" "}
            {project.pValue >= 0.05
              ? `With ${project.before.crashes + project.after.crashes} crashes in all, a gap this size is well within chance (p = ${project.pValue.toFixed(2)}, exact test of equal yearly rates).`
              : `A gap this size would be unusual by chance alone (p = ${project.pValue.toFixed(3)}, exact test of equal yearly rates), but crashes are also reported and located differently over time.`}{" "}
            More riders on the same blocks also changes what a crash count means. This describes the
            records; it is not a finding about whether the lanes made the street safer.
          </p>
        </div>
      ) : null}

      {sources.length > 0 ? (
        <p className="note note--small source-note">
          Sources:{" "}
          {sources.map((source, index) => (
            <span key={source.key}>
              {index > 0 ? "; " : null}
              <a href={source.url} target="_blank" rel="noopener noreferrer">
                {source.publisher}, {source.name}
              </a>{" "}
              ({source.license})
            </span>
          ))}
          .
        </p>
      ) : null}
    </section>
  );
}
