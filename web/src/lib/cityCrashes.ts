import { getSupabaseClient } from "./supabase";
import type { CityCrashPoint, CityDataSource, DataSource } from "./types";

export type LoadCityCrashesResult =
  | { ok: true; points: CityCrashPoint[]; sources: CityDataSource[]; source: DataSource }
  | { ok: false; message: string };

/** Upper bound on points fetched. Mass Ave is 65; a citywide bike import is a few thousand. */
const MAX_POINTS = 5000;

const POINT_COLUMNS =
  "source,source_record_id,occurred_at,mode,street,cross_street_1,cross_street_2,latitude,longitude";
const SOURCE_COLUMNS = "key,name,publisher,url,license,retrieved_on,data_through";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function optionalText(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim().slice(0, 120) : null;
}

function isDate(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}/.test(value) && !Number.isNaN(Date.parse(value));
}

/** All data is untrusted: anything malformed is dropped, never rendered. */
function parsePoint(value: unknown, fallbackSource: string): CityCrashPoint | null {
  if (!isRecord(value)) return null;
  const { source_record_id, occurred_at, mode, latitude, longitude } = value;
  if (
    typeof source_record_id !== "string" ||
    !isDate(occurred_at) ||
    (mode !== "bike" && mode !== "ped" && mode !== "mv") ||
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }
  return {
    source: optionalText(value.source) ?? fallbackSource,
    source_record_id,
    occurred_at,
    mode,
    street: optionalText(value.street),
    cross_street_1: optionalText(value.cross_street_1),
    cross_street_2: optionalText(value.cross_street_2),
    latitude,
    longitude,
  };
}

function parseSource(value: unknown): CityDataSource | null {
  if (!isRecord(value)) return null;
  const { key, name, publisher, url, license, retrieved_on } = value;
  if (
    typeof key !== "string" ||
    typeof name !== "string" ||
    typeof publisher !== "string" ||
    typeof license !== "string" ||
    typeof url !== "string" ||
    !url.startsWith("https://") ||
    !isDate(retrieved_on)
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
    data_through: isDate(value.data_through) ? value.data_through : null,
  };
}

function parsePoints(raw: unknown, fallbackSource: string): CityCrashPoint[] {
  if (!Array.isArray(raw)) return [];
  const points: CityCrashPoint[] = [];
  for (const item of raw) {
    const point = parsePoint(item, fallbackSource);
    if (point !== null) points.push(point);
    if (points.length >= MAX_POINTS) break;
  }
  return points;
}

let cached: Promise<LoadCityCrashesResult> | null = null;

/** Loads city crash records once per page load and shares the result. Failures are not cached. */
export function loadCityCrashes(): Promise<LoadCityCrashesResult> {
  if (cached === null) {
    cached = fetchCityCrashes().then((result) => {
      if (!result.ok) cached = null;
      return result;
    });
  }
  return cached;
}

/**
 * Real, published city crash records (bike only), from the source chosen by
 * NEXT_PUBLIC_DATA_SOURCE. In "fixtures" mode this is a snapshot of the same public data, not
 * sample data. Never throws; failures come back as `{ ok: false, message }`.
 */
async function fetchCityCrashes(): Promise<LoadCityCrashesResult> {
  const mode = process.env.NEXT_PUBLIC_DATA_SOURCE || "fixtures";
  const failure: LoadCityCrashesResult = {
    ok: false,
    message: "Could not load city crash records. Check your connection, then reload.",
  };

  try {
    if (mode === "fixtures") {
      const fixture: unknown = (await import("../../fixtures/city_crashes.json")).default;
      if (!isRecord(fixture)) return failure;
      const source = parseSource(fixture.source);
      if (source === null) return failure;
      const points = parsePoints(fixture.points, source.key).filter((point) => point.mode === "bike");
      return { ok: true, points, sources: [source], source: "fixtures" };
    }
    if (mode === "supabase") {
      const client = getSupabaseClient();
      if (client === null) {
        return {
          ok: false,
          message: "Supabase mode is selected, but the Supabase URL or publishable key is missing in web/.env.local.",
        };
      }
      const [pointsResult, sourcesResult] = await Promise.all([
        client
          .from("public_crash_points")
          .select(POINT_COLUMNS)
          .eq("mode", "bike")
          .order("occurred_at", { ascending: false })
          .limit(MAX_POINTS),
        client.from("public_data_sources").select(SOURCE_COLUMNS),
      ]);
      if (pointsResult.error || sourcesResult.error) return failure;
      const sources = (Array.isArray(sourcesResult.data) ? sourcesResult.data : [])
        .map(parseSource)
        .filter((source): source is CityDataSource => source !== null);
      return { ok: true, points: parsePoints(pointsResult.data, ""), sources, source: "supabase" };
    }
  } catch {
    return failure;
  }
  return { ok: false, message: 'NEXT_PUBLIC_DATA_SOURCE must be "fixtures" or "supabase".' };
}

// ---------------------------------------------------------------------------
// Grouping for the map and the insights
// ---------------------------------------------------------------------------

/** "MASSACHUSETTS AVE" -> "Massachusetts Ave"; "SAINT BOTOLPH ST" -> "St. Botolph St". */
export function streetName(raw: string): string {
  return raw
    .toLowerCase()
    .split(/\s+/)
    .map((word, index) => {
      if (index === 0 && word === "saint") return "St.";
      if (/^\d+(st|nd|rd|th)?$/.test(word)) return word;
      return word.charAt(0).toUpperCase() + word.slice(1);
    })
    .join(" ")
    .replace(/^Massachusetts Ave$/, "Mass Ave");
}

/**
 * The block a record is on: "Mass Ave, Columbus Ave to St. Botolph St". Cross streets are sorted,
 * so the city's two orderings of the same block count as one.
 */
export function blockLabel(point: CityCrashPoint): string {
  const street = point.street ? streetName(point.street) : "Unnamed street";
  const cross = [point.cross_street_1, point.cross_street_2]
    .filter((name): name is string => name !== null)
    .map(streetName)
    .sort();
  if (cross.length === 0) return street;
  if (cross.length === 1) return `${street} at ${cross[0]}`;
  return `${street}, ${cross[0]} to ${cross[1]}`;
}

export interface CrashSpot {
  latitude: number;
  longitude: number;
  label: string;
  count: number;
  firstYear: number;
  lastYear: number;
  lastMonth: string;
}

/**
 * Groups records that share a published location. The city places a record at an intersection
 * or a segment point, so many records share one point; one circle per point reads better than a
 * stack of identical dots.
 */
export function groupBySpot(points: CityCrashPoint[]): CrashSpot[] {
  const spots = new Map<string, { point: CityCrashPoint; times: number[] }>();
  for (const point of points) {
    const key = `${point.latitude.toFixed(5)},${point.longitude.toFixed(5)}`;
    const time = Date.parse(point.occurred_at);
    const spot = spots.get(key);
    if (spot) spot.times.push(time);
    else spots.set(key, { point, times: [time] });
  }
  return [...spots.values()]
    .map(({ point, times }) => {
      const first = new Date(Math.min(...times));
      const last = new Date(Math.max(...times));
      return {
        latitude: point.latitude,
        longitude: point.longitude,
        label: blockLabel(point),
        count: times.length,
        firstYear: first.getUTCFullYear(),
        lastYear: last.getUTCFullYear(),
        lastMonth: `${String(last.getUTCMonth() + 1).padStart(2, "0")}/${last.getUTCFullYear()}`,
      };
    })
    .sort((a, b) => b.count - a.count);
}

/** Counts per block label, busiest first. */
export function countByBlock(points: CityCrashPoint[]): { label: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const point of points) {
    const label = blockLabel(point);
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

/** Counts per calendar year (Boston time), oldest first, with empty years filled in. */
export function countByYear(points: CityCrashPoint[]): { year: number; count: number }[] {
  const yearFormat = new Intl.DateTimeFormat("en-US", { year: "numeric", timeZone: "America/New_York" });
  const counts = new Map<number, number>();
  for (const point of points) {
    const year = Number(yearFormat.format(new Date(point.occurred_at)));
    if (Number.isFinite(year)) counts.set(year, (counts.get(year) ?? 0) + 1);
  }
  if (counts.size === 0) return [];
  const years = [...counts.keys()];
  const result: { year: number; count: number }[] = [];
  for (let year = Math.min(...years); year <= Math.max(...years); year += 1) {
    result.push({ year, count: counts.get(year) ?? 0 });
  }
  return result;
}

/** "Aug 2026" from "2026-08-31". */
export function monthYear(isoDate: string): string {
  const [year, month] = isoDate.split("-").map(Number);
  const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${names[(month ?? 1) - 1] ?? ""} ${year}`.trim();
}
