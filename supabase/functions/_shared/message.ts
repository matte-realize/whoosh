// message.ts — fixed-template SMS renderer for crash alerts.
//
// Single source of truth for the templates and formatting is
// .kiro/team/crash-alert-contract.md, Appendix A. The golden cases G1-G9 and the A.3
// sub-rule cases are reproduced verbatim in ../tests/message_test.ts; this file must keep
// producing them byte-for-byte. Lines are joined with a single LF. Output is ASCII/GSM-7 only.
//
// No PII leaves this module except inside the returned message body, which is handed straight
// to the provider and never logged.

export type Kind = "crash_alert" | "drill" | "test" | "intro" | "all_clear";
export type LocationStatus = "current" | "last_known" | "unavailable";

export interface RenderLocation {
  status: LocationStatus;
  latitude?: number;
  longitude?: number;
  accuracyMeters?: number;
  ageSeconds?: number;
}

export interface RenderInput {
  kind: Kind;
  riderLabel: string;
  detectedAt: string; // ISO-8601 UTC with Z
  utcOffsetMinutes: number;
  delayedSeconds: number;
  location?: RenderLocation;
}

export interface RenderResult {
  body: string;
  segments: number;
}

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

// --- GSM-7 handling ---------------------------------------------------------

// GSM-7 default alphabet plus the common extension characters. Anything outside is mapped or
// stripped so the message stays single-charset (segment math below assumes GSM-7).
const GSM7_BASIC =
  "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ ÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?" +
  "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà";
const GSM7_EXT = "^{}\\[~]|€";

function isGsm7(ch: string): boolean {
  return GSM7_BASIC.includes(ch) || GSM7_EXT.includes(ch);
}

// Best-effort transliteration of common non-GSM-7 characters to a GSM-7-safe equivalent.
const TRANSLIT: Record<string, string> = {
  "Á": "A", "À": "A", "Â": "A", "Ã": "A", "á": "a", "â": "a", "ã": "a",
  "É": "E", "È": "E", "Ê": "E", "é": "e", "ê": "e", "ë": "e",
  "Í": "I", "Ì": "I", "Î": "I", "í": "i", "î": "i", "ï": "i",
  "Ó": "O", "Ò": "O", "Ô": "O", "Õ": "O", "ó": "o", "ô": "o", "õ": "o",
  "Ú": "U", "Ù": "U", "Û": "U", "ú": "u", "û": "u",
  "Ñ": "N", "ñ": "n", "Ç": "C", "ç": "c",
  "\u201C": '"', "\u201D": '"', "\u2018": "'", "\u2019": "'", // smart quotes
  "\u2013": "-", "\u2014": "-", // en/em dash
};

// Sanitize the rider label: transliterate or strip non-GSM-7, collapse whitespace, trim,
// clamp to 20 chars. Matches contract A.1 "Rider label" + A.3 "Label sanitization".
export function sanitizeLabel(raw: string): string {
  let out = "";
  for (const ch of raw) {
    if (ch === "\n" || ch === "\r" || ch === "\t") {
      out += " ";
    } else if (TRANSLIT[ch] !== undefined) {
      out += TRANSLIT[ch];
    } else if (isGsm7(ch)) {
      out += ch;
    }
    // else: drop silently
  }
  out = out.replace(/\s+/g, " ").trim();
  return out.slice(0, 20);
}

// Segment count per contract A: <= 160 GSM-7 chars => 1 segment, else ceil(n / 153).
// Extension characters count as 2 toward the length.
export function segmentCount(body: string): number {
  let units = 0;
  for (const ch of body) {
    units += GSM7_EXT.includes(ch) ? 2 : 1;
  }
  if (units <= 160) return 1;
  return Math.ceil(units / 153);
}

// --- Formatting helpers (A.1) ----------------------------------------------

// Local time: detection time shifted by utcOffsetMinutes, e.g. "Sat Oct 24, 1:41 PM".
export function formatLocalTime(detectedAtIso: string, utcOffsetMinutes: number): string {
  const base = new Date(detectedAtIso);
  const shifted = new Date(base.getTime() + utcOffsetMinutes * 60_000);
  const day = DAYS[shifted.getUTCDay()];
  const month = MONTHS[shifted.getUTCMonth()];
  const date = shifted.getUTCDate();
  let hours = shifted.getUTCHours();
  const minutes = shifted.getUTCMinutes();
  const ampm = hours >= 12 ? "PM" : "AM";
  hours = hours % 12;
  if (hours === 0) hours = 12;
  const mm = minutes.toString().padStart(2, "0");
  return `${day} ${month} ${date}, ${hours}:${mm} ${ampm}`;
}

// Offset: "UTC" + sign + hours, plus ":mm" only when minutes != 0. e.g. UTC-4, UTC+5:30, UTC+0.
export function formatOffset(utcOffsetMinutes: number): string {
  const sign = utcOffsetMinutes < 0 ? "-" : "+";
  const abs = Math.abs(utcOffsetMinutes);
  const h = Math.floor(abs / 60);
  const m = abs % 60;
  if (m === 0) return `UTC${sign}${h}`;
  return `UTC${sign}${h}:${m.toString().padStart(2, "0")}`;
}

// Age: < 60s => "N s old"; 60-3599 => "N min old" (floor); >= 3600 => "N h old" (floor).
export function formatAge(ageSeconds: number): string {
  if (ageSeconds < 60) return `${ageSeconds} s old`;
  if (ageSeconds < 3600) return `${Math.floor(ageSeconds / 60)} min old`;
  return `${Math.floor(ageSeconds / 3600)} h old`;
}

// Coordinates: exactly 5 decimal places. Accuracy: round to nearest whole meter, minimum 1.
function formatCoord(n: number): string {
  return n.toFixed(5);
}
function formatAccuracy(accuracyMeters: number): number {
  return Math.max(1, Math.round(accuracyMeters));
}

function appleMapsLink(lat: number, lon: number): string {
  return `https://maps.apple.com/?ll=${formatCoord(lat)},${formatCoord(lon)}&q=Rider`;
}
function googleMapsLink(lat: number, lon: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${formatCoord(lat)},${formatCoord(lon)}`;
}

// The Time line, including the delay clause when delayedSeconds >= 60.
function timeLine(input: RenderInput): string {
  const t = formatLocalTime(input.detectedAt, input.utcOffsetMinutes);
  const off = formatOffset(input.utcOffsetMinutes);
  let line = `Time: ${t} (${off})`;
  if (input.delayedSeconds >= 60) {
    const n = Math.floor(input.delayedSeconds / 60);
    line += `. Message delayed by ${n} min.`;
  }
  return line;
}

// The location block lines (header + two link lines, or a single "unavailable" line).
// Returns an array of lines (0..3). includeLinks is false only when we drop the Google line
// for the length cap.
function locationLines(loc: RenderLocation, includeGoogle: boolean): string[] {
  if (loc.status === "unavailable") {
    return ["Location unavailable."];
  }
  const lat = loc.latitude!;
  const lon = loc.longitude!;
  const acc = formatAccuracy(loc.accuracyMeters ?? 0);
  let header: string;
  if (loc.status === "last_known") {
    header = `Last known location (${formatAge(loc.ageSeconds ?? 0)}, +/-${acc} m):`;
  } else {
    header = `Location (+/-${acc} m):`;
  }
  const lines = [header, `Apple Maps: ${appleMapsLink(lat, lon)}`];
  if (includeGoogle) lines.push(`Google Maps: ${googleMapsLink(lat, lon)}`);
  return lines;
}

// --- Templates (Appendix A.2) ----------------------------------------------

const CAP_CHARS = 612; // crash_alert / drill max length before dropping the Google line

function renderCrashLike(input: RenderInput, demo: boolean): RenderResult {
  const label = sanitizeLabel(input.riderLabel);
  const loc = input.location!;

  const build = (includeGoogle: boolean): string => {
    const lines: string[] = [];
    if (demo) {
      lines.push(
        `WHOOSH DEMO - NOT REAL: ${label} is demonstrating Whoosh crash alerts. No crash happened.`,
      );
    } else {
      lines.push(
        `WHOOSH ALERT: ${label} may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.`,
      );
    }
    lines.push(timeLine(input));
    lines.push(...locationLines(loc, includeGoogle));
    if (!demo) {
      lines.push(
        "Please try to reach them. If you can't, consider calling emergency services.",
      );
    }
    const closing = demo
      ? "Sent by Whoosh, not an emergency service. Reply STOP to opt out."
      : "Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.";
    lines.push(closing);
    return lines.join("\n");
  };

  let body = build(true);
  // Length cap: drop the Google Maps line first if over 612 chars (only possible with links).
  if (body.length > CAP_CHARS) {
    body = build(false);
  }
  return { body, segments: segmentCount(body) };
}

function renderTest(input: RenderInput): RenderResult {
  const label = sanitizeLabel(input.riderLabel);
  const body =
    `WHOOSH TEST: This is a test message from ${label}. No crash happened. ` +
    `A real alert would include the time and location. ` +
    `Sent by Whoosh, not an emergency service. Reply STOP to opt out.`;
  return { body, segments: segmentCount(body) };
}

function renderIntro(input: RenderInput): RenderResult {
  const label = sanitizeLabel(input.riderLabel);
  const body =
    `WHOOSH: ${label} added you as an emergency contact in the Whoosh cycling app. ` +
    `If their phone detects a possible crash, you may get a text like this. ` +
    `Nothing to do now. Reply STOP to opt out.`;
  return { body, segments: segmentCount(body) };
}

function renderAllClear(input: RenderInput): RenderResult {
  const label = sanitizeLabel(input.riderLabel);
  const t = formatLocalTime(input.detectedAt, input.utcOffsetMinutes);
  const off = formatOffset(input.utcOffsetMinutes);
  const body =
    `WHOOSH UPDATE: ${label} says they are OK. ` +
    `Please ignore the crash alert sent at ${t} (${off}). ` +
    `Sent by Whoosh, not an emergency service. Reply STOP to opt out.`;
  return { body, segments: segmentCount(body) };
}

export function renderMessage(input: RenderInput): RenderResult {
  switch (input.kind) {
    case "crash_alert":
      return renderCrashLike(input, false);
    case "drill":
      return renderCrashLike(input, true);
    case "test":
      return renderTest(input);
    case "intro":
      return renderIntro(input);
    case "all_clear":
      return renderAllClear(input);
  }
}
