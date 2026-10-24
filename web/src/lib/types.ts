/** GeoJSON LineString. Coordinates are [longitude, latitude]. */
export interface RouteLineString {
  type: "LineString";
  coordinates: [number, number][];
}

/** One row of the `public_rides` view. SI units: meters, seconds, meters/second. */
export interface Ride {
  id: string;
  /** ISO 8601 timestamp (UTC). */
  started_at: string;
  distance_m: number;
  active_duration_s: number;
  avg_speed_mps: number;
  route: RouteLineString;
}

export type PositionHint = "left" | "center" | "right";

/** An experimental vehicle detection. Not readable by the anon role; sample data only. */
export interface NearMiss {
  id: string;
  occurred_at: string;
  latitude: number;
  longitude: number;
  kind: string;
  /** 0 to 1. */
  confidence: number;
  position_hint: PositionHint | null;
}

export interface RideWithNearMisses extends Ride {
  near_misses?: NearMiss[];
}

export type DataSource = "fixtures" | "supabase";
