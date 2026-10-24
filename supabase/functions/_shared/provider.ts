/**
 * Text-message provider helpers (Twilio is the reference provider; contract section 7).
 * Uses only Web Crypto and fetch, which exist in both Deno and Node.
 *
 * Items the contract marks "Verify" (signature algorithm, status names, error codes) follow
 * Twilio's documented behavior as best known; confirm against Twilio's current docs before launch.
 */

export type DeliveryStatus = "queued" | "sent" | "delivered" | "undelivered" | "failed" | "rejected";

const encoder = new TextEncoder();

function toHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes), (b) => b.toString(16).padStart(2, "0")).join("");
}

function toBase64(bytes: ArrayBuffer): string {
  let binary = "";
  for (const b of new Uint8Array(bytes)) binary += String.fromCharCode(b);
  return btoa(binary);
}

async function hmac(algorithm: "SHA-1" | "SHA-256", key: string, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey("raw", encoder.encode(key), { name: "HMAC", hash: algorithm }, false, [
    "sign",
  ]);
  return crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(message));
}

/**
 * Keyed hash of a phone number (HMAC-SHA-256 with a server-side pepper), lowercase hex.
 * A keyed hash, not a per-row salt, so rate limits can count across rows (contract section 9).
 */
export async function recipientHash(pepper: string, e164: string): Promise<string> {
  if (pepper.length < 32) throw new Error("pepper too short");
  return toHex(await hmac("SHA-256", pepper, e164));
}

export const lastTwo = (e164: string) => e164.slice(-2);

/** Constant-time string comparison. */
export function timingSafeEqual(a: string, b: string): boolean {
  const ab = encoder.encode(a);
  const bb = encoder.encode(b);
  let diff = ab.length ^ bb.length;
  const n = Math.max(ab.length, bb.length);
  for (let i = 0; i < n; i += 1) diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

/**
 * Twilio request signature: base64(HMAC-SHA1(authToken, url + concat(sorted key + value))).
 * `url` must be the exact public URL Twilio called, including any query string.
 */
export async function twilioSignature(authToken: string, url: string, params: Record<string, string>): Promise<string> {
  const data = Object.keys(params)
    .sort()
    .reduce((acc, key) => acc + key + params[key], url);
  return toBase64(await hmac("SHA-1", authToken, data));
}

export async function verifyTwilioSignature(
  authToken: string,
  url: string,
  params: Record<string, string>,
  header: string | null,
): Promise<boolean> {
  if (!header) return false;
  return timingSafeEqual(await twilioSignature(authToken, url, params), header);
}

/** Provider status -> Whoosh status. Unknown statuses return null (logged, ignored). */
export function mapProviderStatus(status: string): DeliveryStatus | null {
  switch (status) {
    case "accepted":
    case "queued":
    case "sending":
    case "scheduled":
      return "queued";
    case "sent":
      return "sent";
    case "delivered":
      return "delivered";
    case "undelivered":
      return "undelivered";
    case "failed":
      return "failed";
    default:
      return null;
  }
}

/** Provider error code -> Whoosh error code (contract section 7 table). */
export function mapProviderError(code: number | null | undefined): string | null {
  if (code === null || code === undefined || !Number.isFinite(code)) return null;
  switch (code) {
    case 21610:
      return "recipient_opted_out";
    case 21211:
    case 21614:
      return "recipient_invalid";
    case 30003:
    case 30005:
      return "recipient_unreachable";
    case 30006:
      return "recipient_landline";
    case 30007:
      return "carrier_filtered";
    case 21608:
      return "trial_recipient_unverified";
    case 21408:
      return "region_not_enabled";
    default:
      return "provider_error";
  }
}

export interface SendResult {
  ok: boolean;
  sid: string | null;
  status: DeliveryStatus;
  providerErrorCode: number | null;
}

export interface TwilioConfig {
  accountSid: string;
  authToken: string;
  /** Messaging Service SID (MG...) or a sender number in E.164. */
  from: string;
  statusCallbackUrl: string;
  /** Seconds the provider may hold the message before giving up (contract: avoid late delivery). */
  validityPeriodSeconds: number;
}

/** Sends one message. Never throws for provider errors; network failures surface as `ok: false`. */
export async function sendTwilioMessage(config: TwilioConfig, to: string, body: string): Promise<SendResult> {
  const form = new URLSearchParams({
    To: to,
    Body: body,
    StatusCallback: config.statusCallbackUrl,
    ValidityPeriod: String(config.validityPeriodSeconds),
  });
  form.set(config.from.startsWith("MG") ? "MessagingServiceSid" : "From", config.from);
  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${config.accountSid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${config.accountSid}:${config.authToken}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
    signal: AbortSignal.timeout(6000),
  });
  const json = (await response.json().catch(() => ({}))) as { sid?: string; status?: string; code?: number };
  if (!response.ok) {
    return { ok: false, sid: null, status: "rejected", providerErrorCode: typeof json.code === "number" ? json.code : null };
  }
  return {
    ok: true,
    sid: typeof json.sid === "string" ? json.sid : null,
    status: mapProviderStatus(json.status ?? "queued") ?? "queued",
    providerErrorCode: null,
  };
}
