/**
 * Request validation for `send-crash-alert` (contract section 5.3). Pure; no runtime dependencies.
 * Returns either the parsed request or a contract error code with its HTTP status.
 */

import type { Kind, LocationInput } from "./template.ts";

export const SCHEMA_VERSION = 1;
export const MAX_BODY_BYTES = 4096;

export interface Recipient {
  recipientRef: string;
  e164: string;
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
  location?: LocationInput;
  recipients: Recipient[];
  consent: { version: number; acceptedAt: string };
  appVersion: string;
}

export interface ValidationLimits {
  supportedTemplateVersions: number[];
  minConsentVersion: number;
  minSchemaVersion: number;
  maxRecipients: number;
}

export type ValidationError = { ok: false; status: number; code: string };
export type ValidationResult = { ok: true; request: SendRequest } | ValidationError;

const KINDS: Kind[] = ["crash_alert", "drill", "test", "intro", "all_clear"];
const TOP_LEVEL = new Set([
  "schemaVersion", "templateVersion", "crashEventId", "kind", "riderLabel", "detectedAt",
  "utcOffsetMinutes", "delayedSeconds", "location", "recipients", "consent", "appVersion",
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;
const LABEL = /^[A-Za-z0-9 .'-]{1,20}$/;

const fail = (status: number, code: string): ValidationError => ({ ok: false, status, code });
const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);
const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const decimals = (n: number) => {
  const s = String(n);
  const dot = s.indexOf(".");
  return dot === -1 || s.includes("e") ? 0 : s.length - dot - 1;
};
const onlyKeys = (o: Record<string, unknown>, allowed: string[]) => Object.keys(o).every((k) => allowed.includes(k));

/**
 * NANP check for `+1` numbers: area code and exchange each start with 2-9, and neither is an
 * N11 service code. US/Canada only in v1.
 */
export function isNanpE164(e164: string): boolean {
  const m = /^\+1([2-9]\d{2})([2-9]\d{2})(\d{4})$/.exec(e164);
  if (m === null) return false;
  const [, area, exchange] = m;
  return !/^[2-9]11$/.test(area) && !/^[2-9]11$/.test(exchange);
}

/** Collapses whitespace and trims; the result must still match the label rule. */
export function normalizeLabel(label: string): string {
  return label.replace(/\s+/g, " ").trim();
}

export function validateSendRequest(raw: unknown, limits: ValidationLimits, now: Date = new Date()): ValidationResult {
  if (!isObject(raw)) return fail(400, "invalid_request");
  if (!onlyKeys(raw, [...TOP_LEVEL])) return fail(400, "invalid_request");

  // Version gates come first so an old app gets "please update" rather than a field error.
  if (!isInt(raw.schemaVersion)) return fail(400, "invalid_request");
  if (raw.schemaVersion < limits.minSchemaVersion || raw.schemaVersion > SCHEMA_VERSION) {
    return fail(403, "client_upgrade_required");
  }
  if (!isInt(raw.templateVersion) || !limits.supportedTemplateVersions.includes(raw.templateVersion)) {
    return fail(422, "unsupported_template_version");
  }
  if (!isObject(raw.consent) || !onlyKeys(raw.consent, ["version", "acceptedAt"])) return fail(400, "invalid_request");
  const consent = raw.consent;
  if (!isInt(consent.version) || typeof consent.acceptedAt !== "string" || !ISO_UTC.test(consent.acceptedAt)) {
    return fail(400, "invalid_request");
  }
  if (consent.version < limits.minConsentVersion) return fail(403, "client_upgrade_required");

  if (typeof raw.crashEventId !== "string" || !UUID.test(raw.crashEventId)) return fail(400, "invalid_request");
  if (typeof raw.kind !== "string" || !KINDS.includes(raw.kind as Kind)) return fail(400, "invalid_request");
  const kind = raw.kind as Kind;

  if (typeof raw.riderLabel !== "string") return fail(400, "invalid_label");
  const riderLabel = normalizeLabel(raw.riderLabel);
  if (!LABEL.test(riderLabel)) return fail(400, "invalid_label");

  if (typeof raw.detectedAt !== "string" || !ISO_UTC.test(raw.detectedAt)) return fail(400, "invalid_request");
  const detected = Date.parse(raw.detectedAt);
  if (Number.isNaN(detected) || detected > now.getTime() + 5 * 60_000) return fail(400, "invalid_request");
  if ((kind === "crash_alert" || kind === "drill") && detected < now.getTime() - 60 * 60_000) {
    return fail(422, "event_too_old");
  }

  if (!isInt(raw.utcOffsetMinutes) || raw.utcOffsetMinutes < -720 || raw.utcOffsetMinutes > 840) {
    return fail(400, "invalid_request");
  }
  const delayedSeconds = raw.delayedSeconds ?? 0;
  if (!isInt(delayedSeconds) || delayedSeconds < 0 || delayedSeconds > 86_400) return fail(400, "invalid_request");

  // Location: required for crash_alert and drill, absent for the others.
  const needsLocation = kind === "crash_alert" || kind === "drill";
  let location: LocationInput | undefined;
  if (needsLocation) {
    if (!isObject(raw.location)) return fail(400, "invalid_location");
    const loc = raw.location;
    if (loc.status === "unavailable") {
      if (!onlyKeys(loc, ["status"])) return fail(400, "invalid_location");
      location = { status: "unavailable" };
    } else if (loc.status === "current" || loc.status === "last_known") {
      if (!onlyKeys(loc, ["status", "latitude", "longitude", "accuracyMeters", "ageSeconds"])) {
        return fail(400, "invalid_location");
      }
      const { latitude, longitude, accuracyMeters, ageSeconds } = loc;
      if (
        !isNum(latitude) || latitude < -90 || latitude > 90 || decimals(latitude) > 5 ||
        !isNum(longitude) || longitude < -180 || longitude > 180 || decimals(longitude) > 5 ||
        !isNum(accuracyMeters) || accuracyMeters < 0 || accuracyMeters > 9999 ||
        !isNum(ageSeconds) || ageSeconds < 0 || ageSeconds > 86_400
      ) {
        return fail(400, "invalid_location");
      }
      location = { status: loc.status, latitude, longitude, accuracyMeters, ageSeconds };
    } else {
      return fail(400, "invalid_location");
    }
  } else if (raw.location !== undefined) {
    return fail(400, "invalid_location");
  }

  if (!Array.isArray(raw.recipients) || raw.recipients.length === 0) return fail(400, "invalid_recipient");
  if (raw.recipients.length > limits.maxRecipients) return fail(422, "too_many_recipients");
  const recipients: Recipient[] = [];
  const refs = new Set<string>();
  const numbers = new Set<string>();
  for (const r of raw.recipients) {
    if (!isObject(r) || !onlyKeys(r, ["recipientRef", "e164"])) return fail(400, "invalid_recipient");
    if (typeof r.recipientRef !== "string" || !UUID.test(r.recipientRef)) return fail(400, "invalid_recipient");
    if (typeof r.e164 !== "string" || !isNanpE164(r.e164)) return fail(400, "invalid_recipient");
    if (refs.has(r.recipientRef) || numbers.has(r.e164)) return fail(400, "invalid_recipient");
    refs.add(r.recipientRef);
    numbers.add(r.e164);
    recipients.push({ recipientRef: r.recipientRef, e164: r.e164 });
  }

  if (typeof raw.appVersion !== "string" || raw.appVersion.length === 0 || raw.appVersion.length > 32) {
    return fail(400, "invalid_request");
  }

  return {
    ok: true,
    request: {
      schemaVersion: raw.schemaVersion,
      templateVersion: raw.templateVersion,
      crashEventId: raw.crashEventId,
      kind,
      riderLabel,
      detectedAt: raw.detectedAt,
      utcOffsetMinutes: raw.utcOffsetMinutes,
      delayedSeconds,
      location,
      recipients,
      consent: { version: consent.version, acceptedAt: consent.acceptedAt },
      appVersion: raw.appVersion,
    },
  };
}
