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

/**
 * One row of the `public_incident_cells` view: a grid cell (about 100 m) that passed the
 * privacy thresholds. The point is the snapped cell, never an original incident location.
 */
export interface IncidentCell {
  latitude: number;
  longitude: number;
  incident_count: number;
  rider_reported_count: number;
  detected_count: number;
  vehicle_kinds: string[];
  /** ISO date of the first day of the month (YYYY-MM-DD). */
  first_month: string;
  last_month: string;
}

/** The single row of the `public_stats` view. SI units. */
export interface PublicStats {
  shared_rides: number;
  total_distance_m: number;
  total_active_duration_s: number;
  /** Null when fewer than 3 riders have shared rides (the view hides small counts). */
  riders: number | null;
  mapped_incidents: number;
  incident_cells: number;
}

/**
 * One row of the `public_crash_points` view: a crash record published by a city. Real public
 * data, not rider data. For Boston, the time is when responders were dispatched.
 */
export interface CityCrashPoint {
  source: string;
  source_record_id: string;
  /** ISO 8601 timestamp. */
  occurred_at: string;
  /** The most vulnerable person involved. */
  mode: "bike" | "ped" | "mv";
  street: string | null;
  cross_street_1: string | null;
  cross_street_2: string | null;
  latitude: number;
  longitude: number;
}

/** One row of the `public_data_sources` view, shown as attribution. */
export interface CityDataSource {
  key: string;
  name: string;
  publisher: string;
  url: string;
  license: string;
  /** ISO date. */
  retrieved_on: string;
  /** ISO date: the last day the source covers, if it says. */
  data_through: string | null;
}

export type LaneProtection = "separated" | "partly_separated" | "painted" | "shared" | "path";

/** One row of the `public_bike_facilities` view: a published bike lane segment. */
export interface BikeFacility {
  source_record_id: string;
  street: string | null;
  facility_code: string;
  facility_label: string;
  protection: LaneProtection;
  install_year: number | null;
  route: RouteLineString;
}

/** One row of the `public_bike_count_years` view. Averages over full count days only. */
export interface BikeCountYear {
  location_id: string;
  year: number;
  days_counted: number;
  avg_daily_bikes: number;
  min_daily_bikes: number;
  max_daily_bikes: number;
  avg_daily_motor_vehicles: number | null;
}

/** One row of the `public_bike_count_locations` view: a city counter and its latest year. */
export interface BikeCountLocation {
  location_id: string;
  name: string;
  latitude: number;
  longitude: number;
  days_counted: number;
  first_year: number;
  last_year: number;
  latest_year_days: number;
  latest_avg_daily_bikes: number;
  latest_avg_daily_motor_vehicles: number | null;
  /** 0 to 1, or null if nothing was counted. */
  latest_bike_share: number | null;
}

export type FacilityStatus = "in_place" | "before_install" | "install_year";

/** One row of the `public_crash_facility_context` view: a city bike crash and its nearest lane. */
export interface CrashFacilityContext {
  source_record_id: string;
  occurred_at: string;
  facility_source_record_id: string | null;
  facility_code: string | null;
  protection: LaneProtection | null;
  install_year: number | null;
  distance_m: number | null;
  facility_status: FacilityStatus | null;
}
