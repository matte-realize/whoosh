// env.ts — secret loading, the service-role Supabase client, the user client (JWT), and the
// tunable config row. Secret VALUES live only in Edge Function secrets (Deno.env); only NAMES
// appear here and in .env.example.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { TwilioCreds } from "./twilio.ts";

export function getEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing required secret: ${name}`);
  return v;
}

export function optionalEnv(name: string): string | undefined {
  return Deno.env.get(name) || undefined;
}

// Service-role client: bypasses RLS. Used for all function writes.
export function serviceClient(): SupabaseClient {
  return createClient(
    getEnv("SUPABASE_URL"),
    getEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

// User-scoped client: validates the caller JWT and respects RLS. Used for status reads.
export function userClient(authHeader: string): SupabaseClient {
  return createClient(
    getEnv("SUPABASE_URL"),
    getEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}

export function twilioCreds(): TwilioCreds {
  const fromNumber = optionalEnv("TWILIO_FROM_NUMBER");
  const messagingServiceSid = optionalEnv("TWILIO_MESSAGING_SERVICE_SID");
  if (!fromNumber && !messagingServiceSid) {
    throw new Error(
      "missing sender: set TWILIO_FROM_NUMBER or TWILIO_MESSAGING_SERVICE_SID",
    );
  }
  return {
    accountSid: getEnv("TWILIO_ACCOUNT_SID"),
    authToken: getEnv("TWILIO_AUTH_TOKEN"),
    fromNumber,
    messagingServiceSid,
  };
}

// The status-callback URL Twilio posts delivery updates to (contract §7).
export function statusCallbackUrl(): string {
  // CALLBACK_BASE_URL is e.g. https://<project-ref>.functions.supabase.co, no trailing slash.
  const base = getEnv("CALLBACK_BASE_URL").replace(/\/$/, "");
  return `${base}/sms-status-callback`;
}

// Validity period cap so a queued message does not deliver hours late (contract §10).
export function validityPeriodSeconds(): number {
  const v = optionalEnv("TWILIO_VALIDITY_PERIOD_SECONDS");
  const n = v ? Number(v) : 900; // default 15 minutes
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 900;
}

// The tunable config row (contract §11). Shaped to match crash_alert_config columns.
export interface Config {
  enabled: boolean;
  trial_mode: boolean;
  min_schema_version: number;
  min_consent_version: number;
  supported_template_versions: number[];
  recipients_per_request: number;
  real_alerts_per_user_24h: number;
  test_messages_per_user_24h: number;
  test_per_recipient_user_24h: number;
  new_recipients_per_user_24h: number;
  real_per_recipient_all_24h: number;
  test_per_recipient_all_24h: number;
  burst_per_user_per_min: number;
  global_per_hour: number;
  max_segments: number;
}

export async function loadConfig(svc: SupabaseClient): Promise<Config> {
  const { data, error } = await svc
    .from("crash_alert_config")
    .select("*")
    .eq("id", 1)
    .single();
  if (error || !data) {
    throw new Error("crash_alert_config row missing");
  }
  return data as Config;
}

// An environment kill switch overrides the config flag (contract §11): CRASH_ALERTS_DISABLED=1.
export function envKillSwitchOn(): boolean {
  const v = Deno.env.get("CRASH_ALERTS_DISABLED");
  return v === "1" || v === "true";
}
