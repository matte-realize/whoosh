/**
 * Crash-alert message templates, version 1. The single source of truth is Appendix A of
 * `.kiro/team/crash-alert-contract.md`; the golden cases there are checked by `check.ts`.
 *
 * Plain TypeScript with no runtime dependencies, so it runs unchanged in Supabase Edge Functions
 * (Deno) and in Node (for the checks).
 */

export type Kind = "crash_alert" | "drill" | "test" | "intro" | "all_clear";

export type LocationInput =
  | { status: "current" | "last_known"; latitude: number; longitude: number; accuracyMeters: number; ageSeconds: number }
  | { status: "unavailable" };

export interface RenderInput {
  kind: Kind;
  riderLabel: string;
  /** ISO-8601 UTC. For all_clear, the original crash time. */
  detectedAt: string;
  utcOffsetMinutes: number;
  delayedSeconds?: number;
  location?: LocationInput;
}

export const MAX_CHARS_ALERT = 612;

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** `UTC-4`, `UTC+5:30`, `UTC+0`. */
export function formatOffset(minutes: number): string {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const h = Math.floor(abs / 60);
  const m = abs % 60;
  return `UTC${sign}${h}${m === 0 ? "" : `:${String(m).padStart(2, "0")}`}`;
}

/** `Sat Oct 24, 1:41 PM (UTC-4)`: the instant shifted by the offset, in fixed English. */
export function formatLocalTime(isoUtc: string, utcOffsetMinutes: number): string {
  const ms = Date.parse(isoUtc);
  if (Number.isNaN(ms)) throw new Error("invalid time");
  const d = new Date(ms + utcOffsetMinutes * 60_000);
  const hour24 = d.getUTCHours();
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const minute = String(d.getUTCMinutes()).padStart(2, "0");
  const ampm = hour24 < 12 ? "AM" : "PM";
  return `${DAYS[d.getUTCDay()]} ${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}, ${hour12}:${minute} ${ampm} (${formatOffset(utcOffsetMinutes)})`;
}

/** `N s old` under a minute, `N min old` under an hour, `N h old` above. */
export function formatAge(seconds: number): string {
  if (seconds < 60) return `${Math.floor(seconds)} s old`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min old`;
  return `${Math.floor(seconds / 3600)} h old`;
}

/** Empty below one minute, otherwise `. Message delayed by N min.` */
export function delayClause(delayedSeconds: number | undefined): string {
  const s = delayedSeconds ?? 0;
  return s >= 60 ? `. Message delayed by ${Math.floor(s / 60)} min.` : "";
}

const coord = (n: number) => n.toFixed(5);

function locationLines(location: LocationInput | undefined): string[] {
  if (location === undefined || location.status === "unavailable") return ["Location unavailable."];
  const accuracy = Math.max(1, Math.round(location.accuracyMeters));
  const ll = `${coord(location.latitude)},${coord(location.longitude)}`;
  // A "current" fix older than 10 s is described as last known, per the contract.
  const header =
    location.status === "current" && location.ageSeconds <= 10
      ? `Location (+/-${accuracy} m):`
      : `Last known location (${formatAge(location.ageSeconds)}, +/-${accuracy} m):`;
  return [
    header,
    `Apple Maps: https://maps.apple.com/?ll=${ll}&q=Rider`,
    `Google Maps: https://www.google.com/maps/search/?api=1&query=${ll}`,
  ];
}

/** Renders one message. Throws if the label is not already sanitized (see validate.ts). */
export function render(input: RenderInput): string {
  const label = input.riderLabel;
  const time = formatLocalTime(input.detectedAt, input.utcOffsetMinutes);
  switch (input.kind) {
    case "crash_alert": {
      const lines = [
        `WHOOSH ALERT: ${label} may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.`,
        `Time: ${time}${delayClause(input.delayedSeconds)}`,
        ...locationLines(input.location),
        "Please try to reach them. If you can't, consider calling emergency services.",
        "Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.",
      ];
      return capLength(lines);
    }
    case "drill": {
      const lines = [
        `WHOOSH DEMO - NOT REAL: ${label} is demonstrating Whoosh crash alerts. No crash happened.`,
        `Time: ${time}${delayClause(input.delayedSeconds)}`,
        ...locationLines(input.location),
        "Sent by Whoosh, not an emergency service. Reply STOP to opt out.",
      ];
      return capLength(lines);
    }
    case "test":
      return `WHOOSH TEST: This is a test message from ${label}. No crash happened. A real alert would include the time and location. Sent by Whoosh, not an emergency service. Reply STOP to opt out.`;
    case "intro":
      return `WHOOSH: ${label} added you as an emergency contact in the Whoosh cycling app. If their phone detects a possible crash, you may get a text like this. Nothing to do now. Reply STOP to opt out.`;
    case "all_clear":
      return `WHOOSH UPDATE: ${label} says they are OK. Please ignore the crash alert sent at ${time}. Sent by Whoosh, not an emergency service. Reply STOP to opt out.`;
  }
}

/** Over the cap, the Google Maps line goes first. */
function capLength(lines: string[]): string {
  const full = lines.join("\n");
  if (full.length <= MAX_CHARS_ALERT) return full;
  const shorter = lines.filter((line) => !line.startsWith("Google Maps:")).join("\n");
  if (shorter.length <= MAX_CHARS_ALERT) return shorter;
  throw new Error("message_too_long");
}

// ---------- GSM-7 and segments ----------

/** GSM 03.38 basic character set (the extension table is not used by these templates). */
const GSM7_BASIC =
  "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà";
const GSM7_SET = new Set(Array.from(GSM7_BASIC));

export function isGsm7(text: string): boolean {
  return Array.from(text).every((ch) => GSM7_SET.has(ch));
}

/** Segments for a GSM-7 message: 1 if at most 160 characters, else ceil(n / 153). */
export function segmentCount(text: string): number {
  const n = Array.from(text).length;
  return n <= 160 ? 1 : Math.ceil(n / 153);
}
