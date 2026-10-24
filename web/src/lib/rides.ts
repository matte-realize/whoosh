import { getSupabaseClient } from "./supabase";
import type {
  DataSource,
  NearMiss,
  PositionHint,
  RideWithNearMisses,
  Ride,
  RouteLineString,
} from "./types";

export type LoadRidesResult =
  | { ok: true; rides: RideWithNearMisses[]; source: DataSource }
  | { ok: false; message: string };

// ---- Validation. All data is untrusted: anything malformed is dropped, never rendered. ----

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isValidTimestamp(value: unknown): value is string {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function isLonLat(lon: number, lat: number): boolean {
  return lon >= -180 && lon <= 180 && lat >= -90 && lat <= 90;
}

/** Returns a LineString with at least 2 valid [lon, lat] points, or null. Extra axes (altitude) are dropped. */
function parseRoute(value: unknown): RouteLineString | null {
  if (!isRecord(value) || value.type !== "LineString") return null;
  const raw = value.coordinates;
  if (!Array.isArray(raw) || raw.length < 2) return null;

  const coordinates: [number, number][] = [];
  for (const point of raw) {
    if (!Array.isArray(point) || point.length < 2) return null;
    const lon: unknown = point[0];
    const lat: unknown = point[1];
    if (!isFiniteNumber(lon) || !isFiniteNumber(lat) || !isLonLat(lon, lat)) return null;
    coordinates.push([lon, lat]);
  }
  return { type: "LineString", coordinates };
}

/** Keeps only the public_rides columns. Returns null if any of them is invalid. */
function parseRide(value: unknown): Ride | null {
  if (!isRecord(value)) return null;
  const { id, started_at, distance_m, active_duration_s, avg_speed_mps } = value;
  const route = parseRoute(value.route);

  if (
    typeof id !== "string" ||
    id === "" ||
    !isValidTimestamp(started_at) ||
    !isFiniteNumber(distance_m) ||
    !isFiniteNumber(active_duration_s) ||
    !isFiniteNumber(avg_speed_mps) ||
    route === null
  ) {
    return null;
  }
  return { id, started_at, distance_m, active_duration_s, avg_speed_mps, route };
}

function parsePositionHint(value: unknown): PositionHint | null {
  return value === "left" || value === "center" || value === "right" ? value : null;
}

function parseNearMisses(value: unknown): NearMiss[] {
  if (!Array.isArray(value)) return [];
  const result: NearMiss[] = [];
  for (const item of value) {
    if (!isRecord(item)) continue;
    const { id, occurred_at, latitude, longitude, kind, confidence } = item;
    if (
      typeof id !== "string" ||
      !isValidTimestamp(occurred_at) ||
      !isFiniteNumber(latitude) ||
      !isFiniteNumber(longitude) ||
      !isLonLat(longitude, latitude) ||
      typeof kind !== "string" ||
      !isFiniteNumber(confidence) ||
      confidence < 0 ||
      confidence > 1
    ) {
      continue;
    }
    result.push({
      id,
      occurred_at,
      latitude,
      longitude,
      kind,
      confidence,
      position_hint: parsePositionHint(item.position_hint),
    });
  }
  return result;
}

function newestFirst(a: Ride, b: Ride): number {
  return Date.parse(b.started_at) - Date.parse(a.started_at);
}

// ---- Sources ----

async function loadFromFixtures(): Promise<LoadRidesResult> {
  // Loaded on demand so the sample data stays out of the main bundle in supabase mode.
  const fixtureModule = await import("../../fixtures/rides.json");
  const raw: unknown = fixtureModule.default;
  if (!Array.isArray(raw)) {
    return { ok: false, message: "The sample ride data is not in the expected format." };
  }

  const rides: RideWithNearMisses[] = [];
  for (const item of raw) {
    // Mirror the public view: only rides the rider chose to share, and only its columns.
    if (!isRecord(item) || item.share_publicly !== true) continue;
    const ride = parseRide(item);
    if (ride === null) continue;
    const nearMisses = parseNearMisses(item.near_misses);
    rides.push(nearMisses.length > 0 ? { ...ride, near_misses: nearMisses } : ride);
  }
  rides.sort(newestFirst);
  return { ok: true, rides, source: "fixtures" };
}

async function loadFromSupabase(): Promise<LoadRidesResult> {
  try {
    const client = getSupabaseClient();
    if (client === null) {
      return {
        ok: false,
        message:
          "Supabase mode is selected, but NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is missing. " +
          "Set both in web/.env.local, or switch NEXT_PUBLIC_DATA_SOURCE to fixtures.",
      };
    }

    const { data, error } = await client
      .from("public_rides")
      .select("id,started_at,distance_m,active_duration_s,avg_speed_mps,route")
      .order("started_at", { ascending: false })
      .limit(50);

    if (error) {
      return {
        ok: false,
        message: "Could not load rides. Check your connection and the Supabase settings, then reload.",
      };
    }

    const raw: unknown = data;
    const rows = Array.isArray(raw) ? raw : [];
    const rides = rows.map(parseRide).filter((ride): ride is Ride => ride !== null);
    // No near misses here: the anon role cannot read that table, by design.
    return { ok: true, rides, source: "supabase" };
  } catch {
    return {
      ok: false,
      message: "Could not load rides. Check your connection and the Supabase settings, then reload.",
    };
  }
}

/**
 * Loads rides from the source chosen by NEXT_PUBLIC_DATA_SOURCE ("fixtures" by default).
 * Never throws; failures come back as `{ ok: false, message }` with a user-friendly message.
 */
export async function loadRides(): Promise<LoadRidesResult> {
  const source = process.env.NEXT_PUBLIC_DATA_SOURCE || "fixtures";

  try {
    if (source === "fixtures") return await loadFromFixtures();
    if (source === "supabase") return await loadFromSupabase();
  } catch {
    return { ok: false, message: "Could not load rides. Reload the page to try again." };
  }
  return {
    ok: false,
    message: 'NEXT_PUBLIC_DATA_SOURCE must be "fixtures" or "supabase".',
  };
}
