// twilio.ts — Twilio REST send, status-callback signature validation, and the provider
// status/error-code mapping from contract §7. Credentials are read from Deno.env by the caller
// and passed in; this module never reads or logs them.
//
// Verify notes (contract): the Twilio Messages API, StatusCallback behavior, the
// X-Twilio-Signature algorithm, and the error-code table were written from established knowledge
// and should be re-checked against current Twilio docs before the contract is marked Agreed.

export interface TwilioCreds {
  accountSid: string;
  authToken: string;
  // Either a From number or a Messaging Service SID (one is required).
  fromNumber?: string;
  messagingServiceSid?: string;
}

export interface TwilioSendResult {
  ok: boolean;
  sid?: string;
  // On failure, Twilio returns a numeric error code we surface for mapping.
  providerErrorCode?: number;
  // Which Whoosh status to store immediately (queued on success, rejected/failed on error).
  httpStatus: number;
}

// Send one SMS via Twilio's REST API. `to` is E.164. statusCallback is the public callback URL.
// validityPeriod caps how long Twilio keeps trying (so a queued message does not deliver hours
// late). The provider is called exactly once per delivery row (contract §5.4).
export async function sendSms(
  creds: TwilioCreds,
  to: string,
  body: string,
  statusCallback: string,
  validityPeriodSeconds: number,
): Promise<TwilioSendResult> {
  const url =
    `https://api.twilio.com/2010-04-01/Accounts/${creds.accountSid}/Messages.json`;
  const form = new URLSearchParams();
  form.set("To", to);
  form.set("Body", body);
  if (creds.messagingServiceSid) {
    form.set("MessagingServiceSid", creds.messagingServiceSid);
  } else if (creds.fromNumber) {
    form.set("From", creds.fromNumber);
  }
  form.set("StatusCallback", statusCallback);
  form.set("ValidityPeriod", String(validityPeriodSeconds));

  const auth = btoa(`${creds.accountSid}:${creds.authToken}`);
  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: {
        "authorization": `Basic ${auth}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
    });
  } catch {
    // Network error reaching the provider: treat as retryable upstream (no sid stored).
    return { ok: false, httpStatus: 502 };
  }

  let data: Record<string, unknown> = {};
  try {
    data = await resp.json();
  } catch {
    data = {};
  }

  if (resp.ok && typeof data.sid === "string") {
    return { ok: true, sid: data.sid, httpStatus: resp.status };
  }
  const code = typeof data.code === "number" ? data.code : undefined;
  return { ok: false, providerErrorCode: code, httpStatus: resp.status };
}

// --- Signature validation (contract §7) ------------------------------------

// Twilio signs the request: base string = full URL + each POST param name and value sorted by
// name and concatenated; HMAC-SHA-1 with the auth token; base64. Compare in constant time.
export async function isValidTwilioSignature(
  authToken: string,
  url: string,
  params: Record<string, string>,
  signatureHeader: string,
): Promise<boolean> {
  const sorted = Object.keys(params).sort();
  let data = url;
  for (const k of sorted) {
    data += k + params[k];
  }
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(authToken),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(data));
  const expected = btoa(String.fromCharCode(...new Uint8Array(sig)));
  return constantTimeEquals(expected, signatureHeader);
}

export function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

// --- Status and error mapping (contract §7) --------------------------------

export type WhooshStatus =
  | "queued" | "sent" | "delivered" | "undelivered" | "failed" | "rejected";

// Returns null for statuses we ignore (logged only).
export function mapProviderStatus(messageStatus: string): WhooshStatus | null {
  switch (messageStatus) {
    case "accepted":
    case "queued":
    case "sending":
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

export function mapProviderErrorCode(code: number | undefined): string | null {
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
    case undefined:
      return null;
    default:
      return "provider_error";
  }
}

// Monotonic/sticky ordering (contract §5.6): queued < sent < terminal{delivered, undelivered,
// failed, rejected}. Returns true when `next` may be applied over `current`.
const RANK: Record<WhooshStatus, number> = {
  queued: 0,
  sent: 1,
  delivered: 2,
  undelivered: 2,
  failed: 2,
  rejected: 2,
};
const TERMINAL = new Set<WhooshStatus>(["delivered", "undelivered", "failed", "rejected"]);

export function canApplyStatus(current: WhooshStatus, next: WhooshStatus): boolean {
  // Terminal statuses are sticky: a later conflicting terminal status is not applied.
  if (TERMINAL.has(current)) return false;
  return RANK[next] > RANK[current];
}
