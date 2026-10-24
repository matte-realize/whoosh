/** Meters in one statute mile. */
export const METERS_PER_MILE = 1609.344;
/** Feet in one meter. */
export const FEET_PER_METER = 3.28084;
/** Miles per hour in one meter per second. */
export const MPH_PER_MPS = 2.2369362921;

/** Returns n when it is a finite number above zero, otherwise 0. */
function positiveOrZero(n: number): number {
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function pad2(n: number): string {
  return n.toString().padStart(2, "0");
}

/**
 * Formats a distance in meters for display.
 * Under 0.1 mi: whole feet. Under 10 mi: miles with 2 decimals. At or above 10 mi: 1 decimal.
 * Zero, negative, or NaN input shows "0 mi".
 */
export function formatDistance(meters: number): string {
  const m = positiveOrZero(meters);
  if (m === 0) return "0 mi";

  const miles = m / METERS_PER_MILE;
  if (miles < 0.1) return `${Math.round(m * FEET_PER_METER)} ft`;
  if (Number(miles.toFixed(2)) < 10) return `${miles.toFixed(2)} mi`;
  return `${miles.toFixed(1)} mi`;
}

/**
 * Formats a speed in meters/second as miles per hour with 1 decimal.
 * Zero, negative, or NaN input shows "0.0 mph".
 */
export function formatSpeed(metersPerSecond: number): string {
  return `${(positiveOrZero(metersPerSecond) * MPH_PER_MPS).toFixed(1)} mph`;
}

/**
 * Formats a duration in seconds as m:ss under one hour, or h:mm:ss at or above one hour.
 * Zero, negative, or NaN input shows "0:00".
 */
export function formatDuration(seconds: number): string {
  const total = Math.round(positiveOrZero(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0 ? `${h}:${pad2(m)}:${pad2(s)}` : `${m}:${pad2(s)}`;
}

/** Formats an ISO timestamp as a short local date and time. Returns "Unknown date" if invalid. */
export function formatDateTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "Unknown date";
  return d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/** Formats an ISO timestamp as a local time of day. Returns "Unknown time" if invalid. */
export function formatTimeOfDay(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "Unknown time";
  return d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
}
