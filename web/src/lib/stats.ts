import { loadIncidentCells } from "./incidents";
import { loadRides } from "./rides";
import { getSupabaseClient } from "./supabase";
import type { DataSource, PublicStats } from "./types";

export type LoadStatsResult =
  | { ok: true; stats: PublicStats; source: DataSource }
  | { ok: false; message: string };

function isCount(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

/** All data is untrusted: anything malformed is rejected, never rendered. */
function parseStats(value: unknown): PublicStats | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const { shared_rides, total_distance_m, total_active_duration_s, riders, mapped_incidents, incident_cells } =
    value as Record<string, unknown>;
  if (
    !isCount(shared_rides) ||
    !isCount(total_distance_m) ||
    !isCount(total_active_duration_s) ||
    !isCount(mapped_incidents) ||
    !isCount(incident_cells)
  ) {
    return null;
  }
  let riderCount: number | null = null;
  if (riders !== null) {
    if (!isCount(riders)) return null;
    riderCount = riders;
  }
  return {
    shared_rides,
    total_distance_m,
    total_active_duration_s,
    riders: riderCount,
    mapped_incidents,
    incident_cells,
  };
}

/**
 * Fixtures mode computes the same totals from the sample rides and cells the page already
 * loaded. The fixtures carry no rider ids, so the rider count is unknown (null), which the panel
 * shows the same way as the view's hidden small counts.
 */
async function statsFromFixtures(): Promise<LoadStatsResult> {
  const [rides, cells] = await Promise.all([loadRides(), loadIncidentCells()]);
  if (!rides.ok) return { ok: false, message: rides.message };
  const cellList = cells.ok ? cells.cells : [];
  return {
    ok: true,
    source: "fixtures",
    stats: {
      shared_rides: rides.rides.length,
      total_distance_m: rides.rides.reduce((sum, ride) => sum + ride.distance_m, 0),
      total_active_duration_s: rides.rides.reduce((sum, ride) => sum + ride.active_duration_s, 0),
      riders: null,
      mapped_incidents: cellList.reduce((sum, cell) => sum + cell.incident_count, 0),
      incident_cells: cellList.length,
    },
  };
}

/** Loads the totals for the stats panel. Never throws. */
export async function loadStats(): Promise<LoadStatsResult> {
  const source = process.env.NEXT_PUBLIC_DATA_SOURCE || "fixtures";
  const failure: LoadStatsResult = { ok: false, message: "Could not load totals. Reload to try again." };

  try {
    if (source === "fixtures") return await statsFromFixtures();
    if (source === "supabase") {
      const client = getSupabaseClient();
      if (client === null) {
        return { ok: false, message: "Supabase mode is selected, but the Supabase settings are missing." };
      }
      const { data, error } = await client
        .from("public_stats")
        .select("shared_rides,total_distance_m,total_active_duration_s,riders,mapped_incidents,incident_cells")
        .single();
      if (error) return failure;
      const stats = parseStats(data);
      return stats === null ? failure : { ok: true, stats, source: "supabase" };
    }
  } catch {
    return failure;
  }
  return { ok: false, message: 'NEXT_PUBLIC_DATA_SOURCE must be "fixtures" or "supabase".' };
}
