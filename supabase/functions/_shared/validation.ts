// validation.ts — request validation for send-crash-alert (contract §5.2, §5.3).
//
// Pure functions, no I/O, so they are unit-tested directly. Validation never reflects input
// values back in error messages (contract §12).

import type { Kind, LocationStatus } from "./message.ts";

export interface Recipient {
  recipientRef: string;
  e164: string;
}

export interface RequestLocation {
  status: LocationStatus;
  latitude?: number;
  longitude?: number;
  accuracyMeters?: number;
  ageSeconds?: number;
}

export interface SendRequest {
  schemaVersion: number;
  templateVersion: number;
  crashEventId: string;
  kind: Kind;
  riderLabel: string;
  detectedAt: string;
  utcOffsetMinutes: number;
  delayedSeconds: number;
  location?: RequestLocation;
  recipients: Recipient[];
  consent: { version: number; acceptedAt: string };
  appVersion?: string;
}

// A validation failure carries a stable code and HTTP status (contract §5.3 / §13).
export interface ValidationError {
  code: string;
  status: number;
}

export function err(code: string, status: number): ValidationError {
  return { code, status };
}

const KINDS: Kind[] = ["crash_alert", "drill", "test", "intro", "all_clear"];
const LOCATION_KINDS: Kind[] = ["crash_alert", "drill"]; // require a location block
const NO_LOCATION_KINDS: Kind[] = ["test", "intro", "all_clear"]; // location must be absent

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const LABEL_RE = /^[A-Za-z0-9 .'\-]{1,20}$/;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;

const ALLOWED_TOP = new Set([
  "schemaVersion", "templateVersion", "crashEventId", "kind", "riderLabel",
  "detectedAt", "utcOffsetMinutes", "delayedSeconds", "location", "recipients",
  "consent", "appVersion",
]);
const ALLOWED_LOCATION = new Set([
  "status", "latitude", "longitude", "accuracyMeters", "ageSeconds",
]);
const ALLOWED_RECIPIENT = new Set(["recipientRef", "e164"]);
const ALLOWED_CONSENT = new Set(["version", "acceptedAt"]);

function isInt(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n);
}

function decimalPlaces(n: number): number {
  const s = n.toString();
  const dot = s.indexOf(".");
  return dot < 0 ? 0 : s.length - dot - 1;
}

// E.164 US/Canada: +1 followed by a NANP-valid 10-digit number.
// NANP: area code N(2-9)XX, exchange N(2-9)XX, then 4 digits. N = 2-9.
const NANP_RE = /^\+1[2-9]\d{2}[2-9]\d{6}$/;
export function isValidNanp(e164: string): boolean {
  return NANP_RE.test(e164);
}

export interface Limits {
  minSchemaVersion: number;
  supportedTemplateVersions: number[];
  minConsentVersion: number;
  recipientsPerRequest: number;
}

// Validate the parsed body. Returns a ValidationError or null (valid). `now` is injected so
// the future/age checks are testable.
export function validateRequest(
  body: unknown,
  limits: Limits,
  now: Date,
): ValidationError | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return err("invalid_request", 400);
  }
  const b = body as Record<string, unknown>;

  // Unknown fields rejected.
  for (const k of Object.keys(b)) {
    if (!ALLOWED_TOP.has(k)) return err("invalid_request", 400);
  }

  // schemaVersion
  if (!isInt(b.schemaVersion)) return err("invalid_request", 400);
  if ((b.schemaVersion as number) < limits.minSchemaVersion) {
    return err("client_upgrade_required", 403);
  }

  // templateVersion
  if (!isInt(b.templateVersion)) return err("invalid_request", 400);
  if (!limits.supportedTemplateVersions.includes(b.templateVersion as number)) {
    return err("unsupported_template_version", 422);
  }

  // crashEventId
  if (typeof b.crashEventId !== "string" || !UUID_RE.test(b.crashEventId)) {
    return err("invalid_request", 400);
  }

  // kind
  if (typeof b.kind !== "string" || !KINDS.includes(b.kind as Kind)) {
    return err("invalid_request", 400);
  }
  const kind = b.kind as Kind;

  // riderLabel
  if (typeof b.riderLabel !== "string" || !LABEL_RE.test(b.riderLabel)) {
    return err("invalid_label", 422);
  }

  // detectedAt
  if (typeof b.detectedAt !== "string" || !ISO_RE.test(b.detectedAt)) {
    return err("invalid_request", 400);
  }
  const detected = new Date(b.detectedAt);
  if (Number.isNaN(detected.getTime())) return err("invalid_request", 400);
  const skewMs = detected.getTime() - now.getTime();
  if (skewMs > 5 * 60_000) return err("invalid_request", 400); // > 5 min in the future
  if (kind === "crash_alert" || kind === "drill") {
    if (now.getTime() - detected.getTime() > 60 * 60_000) {
      return err("event_too_old", 422); // older than 60 min
    }
  }

  // utcOffsetMinutes
  if (!isInt(b.utcOffsetMinutes)) return err("invalid_request", 400);
  const off = b.utcOffsetMinutes as number;
  if (off < -720 || off > 840) return err("invalid_request", 400);

  // delayedSeconds
  if (!isInt(b.delayedSeconds)) return err("invalid_request", 400);
  const delayed = b.delayedSeconds as number;
  if (delayed < 0 || delayed > 86400) return err("invalid_request", 400);

  // location
  const locErr = validateLocation(b.location, kind);
  if (locErr) return locErr;

  // recipients
  const recErr = validateRecipients(b.recipients, limits.recipientsPerRequest);
  if (recErr) return recErr;

  // consent
  if (
    typeof b.consent !== "object" || b.consent === null || Array.isArray(b.consent)
  ) {
    return err("invalid_request", 400);
  }
  const consent = b.consent as Record<string, unknown>;
  for (const k of Object.keys(consent)) {
    if (!ALLOWED_CONSENT.has(k)) return err("invalid_request", 400);
  }
  if (!isInt(consent.version)) return err("invalid_request", 400);
  if ((consent.version as number) < limits.minConsentVersion) {
    return err("client_upgrade_required", 403);
  }
  if (typeof consent.acceptedAt !== "string" || !ISO_RE.test(consent.acceptedAt)) {
    return err("invalid_request", 400);
  }

  // appVersion (optional)
  if (b.appVersion !== undefined) {
    if (typeof b.appVersion !== "string" || b.appVersion.length > 32) {
      return err("invalid_request", 400);
    }
  }

  return null;
}

function validateLocation(loc: unknown, kind: Kind): ValidationError | null {
  if (NO_LOCATION_KINDS.includes(kind)) {
    if (loc !== undefined) return err("invalid_location", 422);
    return null;
  }
  // crash_alert / drill: location required.
  if (LOCATION_KINDS.includes(kind)) {
    if (typeof loc !== "object" || loc === null || Array.isArray(loc)) {
      return err("invalid_location", 422);
    }
    const l = loc as Record<string, unknown>;
    for (const k of Object.keys(l)) {
      if (!ALLOWED_LOCATION.has(k)) return err("invalid_location", 422);
    }
    const status = l.status;
    if (status !== "current" && status !== "last_known" && status !== "unavailable") {
      return err("invalid_location", 422);
    }
    if (status === "unavailable") {
      // lat/lon/accuracy/age must be absent
      if (
        l.latitude !== undefined || l.longitude !== undefined ||
        l.accuracyMeters !== undefined || l.ageSeconds !== undefined
      ) {
        return err("invalid_location", 422);
      }
      return null;
    }
    // current / last_known: coordinates required and bounded.
    if (typeof l.latitude !== "number" || l.latitude < -90 || l.latitude > 90) {
      return err("invalid_location", 422);
    }
    if (typeof l.longitude !== "number" || l.longitude < -180 || l.longitude > 180) {
      return err("invalid_location", 422);
    }
    if (decimalPlaces(l.latitude) > 5 || decimalPlaces(l.longitude) > 5) {
      return err("invalid_location", 422);
    }
    if (
      typeof l.accuracyMeters !== "number" || l.accuracyMeters < 0 ||
      l.accuracyMeters > 9999
    ) {
      return err("invalid_location", 422);
    }
    if (
      typeof l.ageSeconds !== "number" || !Number.isInteger(l.ageSeconds) ||
      l.ageSeconds < 0 || l.ageSeconds > 86400
    ) {
      return err("invalid_location", 422);
    }
    return null;
  }
  return null;
}

function validateRecipients(
  recipients: unknown,
  maxPerRequest: number,
): ValidationError | null {
  if (!Array.isArray(recipients) || recipients.length < 1) {
    return err("invalid_recipient", 422);
  }
  if (recipients.length > maxPerRequest) {
    return err("too_many_recipients", 422);
  }
  const seenE164 = new Set<string>();
  const seenRef = new Set<string>();
  for (const r of recipients) {
    if (typeof r !== "object" || r === null || Array.isArray(r)) {
      return err("invalid_recipient", 422);
    }
    const rec = r as Record<string, unknown>;
    for (const k of Object.keys(rec)) {
      if (!ALLOWED_RECIPIENT.has(k)) return err("invalid_recipient", 422);
    }
    if (typeof rec.recipientRef !== "string" || !UUID_RE.test(rec.recipientRef)) {
      return err("invalid_recipient", 422);
    }
    if (typeof rec.e164 !== "string" || !isValidNanp(rec.e164)) {
      return err("invalid_recipient", 422);
    }
    if (seenE164.has(rec.e164) || seenRef.has(rec.recipientRef)) {
      return err("invalid_recipient", 422);
    }
    seenE164.add(rec.e164);
    seenRef.add(rec.recipientRef);
  }
  return null;
}
