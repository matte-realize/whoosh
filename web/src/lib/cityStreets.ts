import { loadCityCrashes } from "./cityCrashes";
import { getSupabaseClient } from "./supabase";
import type {
  BikeCountLocation,
  BikeCountYear,
  BikeFacility,
  CityCrashPoint,
  CityDataSource,
  CrashFacilityContext,
  DataSource,
  FacilityStatus,
  LaneProtection,
} from "./types";

/**
 * Real city street data: the bike network (lane segments) and bike counts, plus each city
 * crash's nearest lane. Every loader reads the anon views in "supabase" mode and the snapshot
 * fixtures otherwise. In fixtures mode the crash context is computed here with the same rules
 * as the `public_crash_facility_context` view (25 m, ties to the lower record id).
 */

export type Loaded<T> = { ok: true; source: DataSource; sources: CityDataSource[] } & T;
export type LoadResult<T> = Loaded<T> | { ok: false; message: string };

export type LoadBikeNetworkResult = LoadResult<{ facilities: BikeFacility[] }>;
export type LoadBikeCountsResult = LoadResult<{ locations: BikeCountLocation[]; years: BikeCountYear[] }>;
export type LoadCrashContextResult = LoadResult<{ rows: CrashFacilityContext[] }>;

const MAX_FACILITIES = 5000;
const MAX_POINTS_PER_ROUTE = 10000;
/** Same limit as the view. */
export const MATCH_LIMIT_M = 25;

const PROTECTIONS: readonly LaneProtection[] = ["separated", "partly_separated", "painted", "shared", "path"];
const STATUSES: readonly FacilityStatus[] = ["in_place", "before_install", "install_year"];

// ---------------------------------------------------------------------------
// Parsing (all data is untrusted: anything malformed is dropped)
// ---------------------------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function isCount(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0;
}
function isYear(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 1970 && value <= 2100;
}
function isLat(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= -90 && value <= 90;
}
function isLon(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= -180 && value <= 180;
}
function text(value: unknown, max = 120): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim().slice(0, max) : null;
}
function list(raw: unknown, limit: number): unknown[] {
  return Array.isArray(raw) ? raw.slice(0, limit) : [];
}
function keep<T>(items: (T | null)[]): T[] {
  return items.filter((item): item is T => item !== null);
}

function parseSource(value: unknown): CityDataSource | null {
  if (!isRecord(value)) return null;
  const { key, name, publisher, url, license, retrieved_on, data_through } = value;
  if (
    typeof key !== "string" ||
    typeof name !== "string" ||
    typeof publisher !== "string" ||
    typeof license !== "string" ||
    typeof url !== "string" ||
    !url.startsWith("https://") ||
    typeof retrieved_on !== "string"
  ) {
    return null;
  }
  return {
    key,
    name,
    publisher,
    url,
    license,
    retrieved_on,
    data_through: typeof data_through === "string" ? data_through : null,
  };
}

function parseFacility(value: unknown): BikeFacility | null {
  if (!isRecord(value)) return null;
  const { source_record_id, facility_code, facility_label, protection, install_year, route } = value;
  if (
    typeof source_record_id !== "string" ||
    typeof facility_code !== "string" ||
    typeof facility_label !== "string" ||
    !PROTECTIONS.includes(protection as LaneProtection) ||
    !(install_year === null || isYear(install_year)) ||
    !isRecord(route) ||
    route.type !== "LineString" ||
    !Array.isArray(route.coordinates)
  ) {
    return null;
  }
  const coordinates: [number, number][] = [];
  for (const point of route.coordinates.slice(0, MAX_POINTS_PER_ROUTE)) {
    if (!Array.isArray(point) || !isLon(point[0]) || !isLat(point[1])) return null;
    coordinates.push([point[0], point[1]]);
  }
  if (coordinates.length < 2) return null;
  return {
    source_record_id,
    street: text(value.street),
    facility_code,
    facility_label: facility_label.slice(0, 120),
    protection: protection as LaneProtection,
    install_year: install_year as number | null,
    route: { type: "LineString", coordinates },
  };
}

function parseYear(value: unknown): BikeCountYear | null {
  if (!isRecord(value)) return null;
  const { location_id, year, days_counted, avg_daily_bikes, min_daily_bikes, max_daily_bikes } = value;
  const mv = value.avg_daily_motor_vehicles;
  if (
    typeof location_id !== "string" ||
    !isYear(year) ||
    !isCount(days_counted) ||
    days_counted === 0 ||
    !isCount(avg_daily_bikes) ||
    !isCount(min_daily_bikes) ||
    !isCount(max_daily_bikes) ||
    !(mv === null || isCount(mv))
  ) {
    return null;
  }
  return {
    location_id,
    year,
    days_counted,
    avg_daily_bikes,
    min_daily_bikes,
    max_daily_bikes,
    avg_daily_motor_vehicles: mv as number | null,
  };
}

function parseLocation(value: unknown): BikeCountLocation | null {
  if (!isRecord(value)) return null;
  const v = value;
  const name = text(v.name);
  const share = v.latest_bike_share;
  const mv = v.latest_avg_daily_motor_vehicles;
  if (
    typeof v.location_id !== "string" ||
    name === null ||
    !isLat(v.latitude) ||
    !isLon(v.longitude) ||
    !isCount(v.days_counted) ||
    !isYear(v.first_year) ||
    !isYear(v.last_year) ||
    !isCount(v.latest_year_days) ||
    !isCount(v.latest_avg_daily_bikes) ||
    !(mv === null || isCount(mv)) ||
    !(share === null || (typeof share === "number" && share >= 0 && share <= 1))
  ) {
    return null;
  }
  return {
    location_id: v.location_id,
    name,
    latitude: v.latitude,
    longitude: v.longitude,
    days_counted: v.days_counted,
    first_year: v.first_year,
    last_year: v.last_year,
    latest_year_days: v.latest_year_days,
    latest_avg_daily_bikes: v.latest_avg_daily_bikes,
    latest_avg_daily_motor_vehicles: mv as number | null,
    latest_bike_share: share as number | null,
  };
}

function parseContext(value: unknown): CrashFacilityContext | null {
  if (!isRecord(value)) return null;
  const v = value;
  if (typeof v.source_record_id !== "string" || typeof v.occurred_at !== "string") return null;
  const matched = typeof v.facility_code === "string";
  return {
    source_record_id: v.source_record_id,
    occurred_at: v.occurred_at,
    facility_source_record_id: matched && typeof v.facility_source_record_id === "string" ? v.facility_source_record_id : null,
    facility_code: matched ? (v.facility_code as string) : null,
    protection: matched && PROTECTIONS.includes(v.protection as LaneProtection) ? (v.protection as LaneProtection) : null,
    install_year: matched && isYear(v.install_year) ? v.install_year : null,
    distance_m: matched && typeof v.distance_m === "number" ? v.distance_m : null,
    facility_status: STATUSES.includes(v.facility_status as FacilityStatus) ? (v.facility_status as FacilityStatus) : null,
  };
}

// ---------------------------------------------------------------------------
// Loaders (each runs once per page load; failures are not cached)
// ---------------------------------------------------------------------------

function once<T extends { ok: boolean }>(load: () => Promise<T>): () => Promise<T> {
  let cached: Promise<T> | null = null;
  return () => {
    if (cached === null) {
      cached = load().then((result) => {
        if (!result.ok) cached = null;
        return result;
      });
    }
    return cached;
  };
}

function mode(): string {
  return process.env.NEXT_PUBLIC_DATA_SOURCE || "fixtures";
}

const MISSING_KEYS =
  "Supabase mode is selected, but the Supabase URL or publishable key is missing in web/.env.local.";
const BAD_MODE = 'NEXT_PUBLIC_DATA_SOURCE must be "fixtures" or "supabase".';

async function supabaseSources(keys: string[]): Promise<CityDataSource[]> {
  const client = getSupabaseClient();
  if (client === null || keys.length === 0) return [];
  const { data, error } = await client
    .from("public_data_sources")
    .select("key,name,publisher,url,license,retrieved_on,data_through")
    .in("key", keys);
  return error ? [] : keep(list(data, 50).map(parseSource));
}

export const loadBikeNetwork = once(async (): Promise<LoadBikeNetworkResult> => {
  const failure = { ok: false as const, message: "Could not load the city bike network. Check your connection, then reload." };
  try {
    if (mode() === "fixtures") {
      const fixture: unknown = (await import("../../fixtures/bike_network.json")).default;
      if (!isRecord(fixture)) return failure;
      const source = parseSource(fixture.source);
      if (source === null) return failure;
      const facilities = keep(list(fixture.facilities, MAX_FACILITIES).map(parseFacility));
      return { ok: true, source: "fixtures", sources: [source], facilities };
    }
    if (mode() === "supabase") {
      const client = getSupabaseClient();
      if (client === null) return { ok: false, message: MISSING_KEYS };
      const { data, error } = await client
        .from("public_bike_facilities")
        .select("source,source_record_id,street,facility_code,facility_label,protection,install_year,route")
        .limit(MAX_FACILITIES);
      if (error) return failure;
      const rows = list(data, MAX_FACILITIES);
      const keys = [...new Set(rows.map((row) => (isRecord(row) ? row.source : null)).filter((k): k is string => typeof k === "string"))];
      return { ok: true, source: "supabase", sources: await supabaseSources(keys), facilities: keep(rows.map(parseFacility)) };
    }
  } catch {
    return failure;
  }
  return { ok: false, message: BAD_MODE };
});

export const loadBikeCounts = once(async (): Promise<LoadBikeCountsResult> => {
  const failure = { ok: false as const, message: "Could not load the city bike counts. Check your connection, then reload." };
  try {
    if (mode() === "fixtures") {
      const fixture: unknown = (await import("../../fixtures/bike_counts.json")).default;
      if (!isRecord(fixture)) return failure;
      const source = parseSource(fixture.source);
      if (source === null) return failure;
      return {
        ok: true,
        source: "fixtures",
        sources: [source],
        locations: keep(list(fixture.locations, 500).map(parseLocation)),
        years: keep(list(fixture.years, 20000).map(parseYear)),
      };
    }
    if (mode() === "supabase") {
      const client = getSupabaseClient();
      if (client === null) return { ok: false, message: MISSING_KEYS };
      const [locations, years] = await Promise.all([
        client
          .from("public_bike_count_locations")
          .select(
            "source,location_id,name,latitude,longitude,days_counted,first_year,last_year,latest_year_days," +
              "latest_avg_daily_bikes,latest_avg_daily_motor_vehicles,latest_bike_share",
          )
          .limit(500),
        client
          .from("public_bike_count_years")
          .select("location_id,year,days_counted,avg_daily_bikes,min_daily_bikes,max_daily_bikes,avg_daily_motor_vehicles")
          .order("year")
          .limit(20000),
      ]);
      if (locations.error || years.error) return failure;
      const rows = list(locations.data, 500);
      const keys = [...new Set(rows.map((row) => (isRecord(row) ? row.source : null)).filter((k): k is string => typeof k === "string"))];
      return {
        ok: true,
        source: "supabase",
        sources: await supabaseSources(keys),
        locations: keep(rows.map(parseLocation)),
        years: keep(list(years.data, 20000).map(parseYear)),
      };
    }
  } catch {
    return failure;
  }
  return { ok: false, message: BAD_MODE };
});

export const loadCrashContext = once(async (): Promise<LoadCrashContextResult> => {
  const failure = { ok: false as const, message: "Could not match crashes to bike lanes." };
  try {
    if (mode() === "fixtures") {
      const [crashes, network] = await Promise.all([loadCityCrashes(), loadBikeNetwork()]);
      if (!crashes.ok || !network.ok) return failure;
      return {
        ok: true,
        source: "fixtures",
        sources: [...crashes.sources, ...network.sources],
        rows: matchCrashesToLanes(crashes.points, network.facilities),
      };
    }
    if (mode() === "supabase") {
      const client = getSupabaseClient();
      if (client === null) return { ok: false, message: MISSING_KEYS };
      const { data, error } = await client
        .from("public_crash_facility_context")
        .select("source_record_id,occurred_at,facility_source_record_id,facility_code,protection,install_year,distance_m,facility_status")
        .limit(20000);
      if (error) return failure;
      return { ok: true, source: "supabase", sources: [], rows: keep(list(data, 20000).map(parseContext)) };
    }
  } catch {
    return failure;
  }
  return { ok: false, message: BAD_MODE };
});

// ---------------------------------------------------------------------------
// Geometry and matching (mirrors the SQL in migration 20261024170000)
// ---------------------------------------------------------------------------

/** Meters from a point to a segment on a local flat projection (same formula as the SQL helper). */
export function segmentDistanceM(
  pLat: number,
  pLon: number,
  aLat: number,
  aLon: number,
  bLat: number,
  bLon: number,
): number {
  const kx = 111320 * Math.cos((pLat * Math.PI) / 180);
  const ky = 110574;
  const ax = (aLon - pLon) * kx;
  const ay = (aLat - pLat) * ky;
  const dx = (bLon - aLon) * kx;
  const dy = (bLat - aLat) * ky;
  const dd = dx * dx + dy * dy;
  const t = dd === 0 ? 1 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / dd));
  return Math.hypot(ax + t * dx, ay + t * dy);
}

/** Meters from a point to a whole lane (its nearest piece). */
export function routeDistanceM(lat: number, lon: number, coordinates: [number, number][]): number {
  let best = Infinity;
  for (let i = 0; i + 1 < coordinates.length; i += 1) {
    const [aLon, aLat] = coordinates[i];
    const [bLon, bLat] = coordinates[i + 1];
    best = Math.min(best, segmentDistanceM(lat, lon, aLat, aLon, bLat, bLon));
  }
  return best;
}

function statusFor(installYear: number | null, crashYear: number): FacilityStatus | null {
  if (installYear === null) return null;
  if (installYear < crashYear) return "in_place";
  if (installYear > crashYear) return "before_install";
  return "install_year";
}

/** The crash context for fixtures mode: nearest lane within 25 m; ties go to the lower record id. */
export function matchCrashesToLanes(points: CityCrashPoint[], facilities: BikeFacility[]): CrashFacilityContext[] {
  return points
    .filter((point) => point.mode === "bike")
    .map((point) => {
      let best: { facility: BikeFacility; distance: number; cm: number } | null = null;
      for (const facility of facilities) {
        const distance = routeDistanceM(point.latitude, point.longitude, facility.route.coordinates);
        if (distance > MATCH_LIMIT_M) continue;
        // Compared at centimeter precision, like the view, so lanes meeting at a point tie exactly.
        const cm = Math.round(distance * 100);
        if (
          best === null ||
          cm < best.cm ||
          (cm === best.cm && facility.source_record_id < best.facility.source_record_id)
        ) {
          best = { facility, distance, cm };
        }
      }
      // The view uses the UTC year of the timestamp (Supabase runs in UTC).
      const year = new Date(point.occurred_at).getUTCFullYear();
      return {
        source_record_id: point.source_record_id,
        occurred_at: point.occurred_at,
        facility_source_record_id: best?.facility.source_record_id ?? null,
        facility_code: best?.facility.facility_code ?? null,
        protection: best?.facility.protection ?? null,
        install_year: best?.facility.install_year ?? null,
        distance_m: best ? Math.round(best.distance * 10) / 10 : null,
        facility_status: best ? statusFor(best.facility.install_year, year) : null,
      };
    });
}

/** Lane length in meters (sum of its pieces), on the same flat projection. */
export function routeLengthM(coordinates: [number, number][]): number {
  let total = 0;
  for (let i = 0; i + 1 < coordinates.length; i += 1) {
    const [aLon, aLat] = coordinates[i];
    const [bLon, bLat] = coordinates[i + 1];
    // Point A to the zero-length segment at B: the straight distance A to B.
    total += segmentDistanceM(aLat, aLon, bLat, bLon, bLat, bLon);
  }
  return total;
}

// ---------------------------------------------------------------------------
// Summaries for the page
// ---------------------------------------------------------------------------

export const PROTECTION_LABEL: Record<LaneProtection, string> = {
  separated: "Separated lane",
  partly_separated: "Separated on one side",
  painted: "Painted lane",
  shared: "Shared lane",
  path: "Off-street path",
};

/** "Massachusetts Avenue north of Back Street" -> "North of Back Street" when the street is known. */
export function counterLabel(name: string, street = "Massachusetts Avenue"): string {
  if (!name.startsWith(`${street} `)) return name;
  const rest = name.slice(street.length + 1);
  return rest.charAt(0).toUpperCase() + rest.slice(1);
}

export interface LaneProject {
  protection: LaneProtection;
  installYear: number;
  lengthM: number;
  facilityIds: Set<string>;
  before: { crashes: number; years: number; firstYear: number; lastYear: number };
  after: { crashes: number; years: number; firstYear: number; lastYear: number };
}

/**
 * Groups lanes into "projects" (same protection class and install year) and compares crashes per
 * year before and after, leaving out the install year itself. Only projects with at least 3 years
 * of crash data before and 1 after are returned, largest first. Years after run to the crash
 * data's end date, so a partial last year counts as a fraction.
 */
export function laneProjects(
  facilities: BikeFacility[],
  context: CrashFacilityContext[],
  crashFirstYear: number,
  crashDataThrough: string,
): LaneProject[] {
  const through = new Date(`${crashDataThrough}T23:59:59Z`);
  if (Number.isNaN(through.getTime())) return [];
  const throughYear = through.getUTCFullYear();
  const yearStart = Date.UTC(throughYear, 0, 1);
  const yearEnd = Date.UTC(throughYear + 1, 0, 1);
  const partialLastYear = (through.getTime() - yearStart) / (yearEnd - yearStart);

  const groups = new Map<string, LaneProject>();
  for (const facility of facilities) {
    if (facility.install_year === null) continue;
    if (facility.protection !== "separated" && facility.protection !== "partly_separated") continue;
    const key = `${facility.protection}:${facility.install_year}`;
    let group = groups.get(key);
    if (!group) {
      const installYear = facility.install_year;
      const yearsBefore = installYear - crashFirstYear;
      // Full years strictly after the install year, plus the covered part of the last year.
      const yearsAfter = throughYear > installYear ? throughYear - installYear - 1 + partialLastYear : 0;
      group = {
        protection: facility.protection,
        installYear,
        lengthM: 0,
        facilityIds: new Set(),
        before: { crashes: 0, years: yearsBefore, firstYear: crashFirstYear, lastYear: installYear - 1 },
        after: { crashes: 0, years: yearsAfter, firstYear: installYear + 1, lastYear: throughYear },
      };
      groups.set(key, group);
    }
    group.lengthM += routeLengthM(facility.route.coordinates);
    group.facilityIds.add(facility.source_record_id);
  }
  for (const row of context) {
    if (row.facility_source_record_id === null || row.install_year === null || row.protection === null) continue;
    const group = groups.get(`${row.protection}:${row.install_year}`);
    if (!group || !group.facilityIds.has(row.facility_source_record_id)) continue;
    if (row.facility_status === "before_install") group.before.crashes += 1;
    if (row.facility_status === "in_place") group.after.crashes += 1;
  }
  return [...groups.values()]
    .filter((group) => group.before.years >= 3 && group.after.years >= 1)
    .sort((a, b) => b.lengthM - a.lengthM);
}

/**
 * Two-sided exact test of "same crash rate before and after". Given n crashes in total, under
 * equal rates the after-count is Binomial(n, yearsAfter / (yearsBefore + yearsAfter)). Returns
 * the p-value: the chance of a split at least this uneven if nothing changed.
 */
export function equalRateP(before: number, yearsBefore: number, after: number, yearsAfter: number): number {
  const n = before + after;
  if (n === 0 || yearsBefore <= 0 || yearsAfter <= 0) return 1;
  const p = yearsAfter / (yearsBefore + yearsAfter);
  const probabilities: number[] = [];
  let logChoose = 0; // log C(n, 0)
  for (let k = 0; k <= n; k += 1) {
    if (k > 0) logChoose += Math.log(n - k + 1) - Math.log(k);
    probabilities.push(Math.exp(logChoose + k * Math.log(p) + (n - k) * Math.log(1 - p)));
  }
  const observed = probabilities[after];
  // Small tolerance so equal probabilities on both tails are both counted.
  const total = probabilities.filter((value) => value <= observed * (1 + 1e-9)).reduce((sum, value) => sum + value, 0);
  return Math.min(1, total);
}

export interface CountWindow {
  avg: number;
  days: number;
  firstYear: number;
  lastYear: number;
}

/** Years left out of before/after volume comparisons: traffic collapsed during the pandemic. */
export const PANDEMIC_YEARS: readonly number[] = [2020, 2021];

/**
 * Bikes a day at one counter before and after an install year: every full count day pooled
 * (a day-weighted average of the yearly averages). The install year and the pandemic years are
 * left out. Null if either side has no days.
 */
export function countsAround(
  years: BikeCountYear[],
  locationId: string,
  installYear: number,
): { before: CountWindow; after: CountWindow } | null {
  const mine = years.filter((year) => year.location_id === locationId && !PANDEMIC_YEARS.includes(year.year));
  const pool = (rows: BikeCountYear[]): CountWindow | null => {
    const days = rows.reduce((sum, row) => sum + row.days_counted, 0);
    if (days === 0) return null;
    const bikes = rows.reduce((sum, row) => sum + row.avg_daily_bikes * row.days_counted, 0);
    return {
      avg: Math.round(bikes / days),
      days,
      firstYear: Math.min(...rows.map((row) => row.year)),
      lastYear: Math.max(...rows.map((row) => row.year)),
    };
  };
  const before = pool(mine.filter((year) => year.year < installYear));
  const after = pool(mine.filter((year) => year.year > installYear));
  return before && after ? { before, after } : null;
}

/** The counter nearest to any lane in the set, within `limitM`. */
export function counterOnLanes(
  locations: BikeCountLocation[],
  facilities: BikeFacility[],
  facilityIds: Set<string>,
  limitM = 50,
): BikeCountLocation | null {
  let best: { location: BikeCountLocation; distance: number } | null = null;
  for (const location of locations) {
    for (const facility of facilities) {
      if (!facilityIds.has(facility.source_record_id)) continue;
      const distance = routeDistanceM(location.latitude, location.longitude, facility.route.coordinates);
      if (distance <= limitM && (best === null || distance < best.distance)) best = { location, distance };
    }
  }
  return best?.location ?? null;
}
