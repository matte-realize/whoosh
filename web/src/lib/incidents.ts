import { getSupabaseClient } from "./supabase";
import type { DataSource, IncidentCell } from "./types";

export type LoadIncidentsResult =
  | { ok: true; cells: IncidentCell[]; source: DataSource }
  | { ok: false; message: string };

/** Upper bound on cells fetched. The map stays responsive, and a busy area cannot flood it. */
const MAX_CELLS = 500;

const COLUMNS =
  "latitude,longitude,incident_count,rider_reported_count,detected_count,vehicle_kinds,first_month,last_month";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isCount(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0;
}

function isMonth(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

/** All data is untrusted: anything malformed is dropped, never rendered. */
function parseCell(value: unknown): IncidentCell | null {
  if (!isRecord(value)) return null;
  const { latitude, longitude, incident_count, rider_reported_count, detected_count, first_month, last_month } =
    value;
  const kinds = value.vehicle_kinds;
  if (
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180 ||
    !isCount(incident_count) ||
    !isCount(rider_reported_count) ||
    !isCount(detected_count) ||
    !isMonth(first_month) ||
    !isMonth(last_month) ||
    !Array.isArray(kinds)
  ) {
    return null;
  }
  return {
    latitude,
    longitude,
    incident_count,
    rider_reported_count,
    detected_count,
    vehicle_kinds: kinds.filter((kind): kind is string => typeof kind === "string"),
    first_month,
    last_month,
  };
}

function parseCells(raw: unknown): IncidentCell[] {
  if (!Array.isArray(raw)) return [];
  const cells: IncidentCell[] = [];
  for (const item of raw) {
    const cell = parseCell(item);
    if (cell !== null) cells.push(cell);
    if (cells.length >= MAX_CELLS) break;
  }
  return cells;
}

let cachedCells: Promise<LoadIncidentsResult> | null = null;

/** Loads incident cells once per page load and shares the result. Failures are not cached. */
export function loadIncidentCells(): Promise<LoadIncidentsResult> {
  if (cachedCells === null) {
    cachedCells = fetchIncidentCells().then((result) => {
      if (!result.ok) cachedCells = null;
      return result;
    });
  }
  return cachedCells;
}

/**
 * Fetches incident cells from the source chosen by NEXT_PUBLIC_DATA_SOURCE ("fixtures" by default).
 * Never throws; failures come back as `{ ok: false, message }`.
 */
async function fetchIncidentCells(): Promise<LoadIncidentsResult> {
  const source = process.env.NEXT_PUBLIC_DATA_SOURCE || "fixtures";
  const failure: LoadIncidentsResult = {
    ok: false,
    message: "Could not load the incident map. Check your connection, then reload.",
  };

  try {
    if (source === "fixtures") {
      const fixtureModule = await import("../../fixtures/incident_cells.json");
      return { ok: true, cells: parseCells(fixtureModule.default), source: "fixtures" };
    }
    if (source === "supabase") {
      const client = getSupabaseClient();
      if (client === null) {
        return {
          ok: false,
          message: "Supabase mode is selected, but the Supabase URL or publishable key is missing in web/.env.local.",
        };
      }
      // Largest cells first, so the limit keeps the most informative ones.
      const { data, error } = await client
        .from("public_incident_cells")
        .select(COLUMNS)
        .order("incident_count", { ascending: false })
        .limit(MAX_CELLS);
      if (error) return failure;
      return { ok: true, cells: parseCells(data), source: "supabase" };
    }
  } catch {
    return failure;
  }
  return { ok: false, message: 'NEXT_PUBLIC_DATA_SOURCE must be "fixtures" or "supabase".' };
}
