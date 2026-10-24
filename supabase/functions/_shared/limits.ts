// limits.ts — rate limits and caps (contract §10), backed by crash_alert_counters.
//
// Counting model: each successful send inserts counter rows (one per applicable bucket). Before
// sending we count rows in the rolling window and compare to the configured cap. This is a
// best-effort limiter (there is a small race under concurrency); the hard send-once guarantee is
// the unique constraint on crash_alert_deliveries, not these counts.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { Config } from "./env.ts";
import type { Kind } from "./message.ts";

const TEST_KINDS: Kind[] = ["drill", "test", "intro", "all_clear"];
export function isTestKind(kind: Kind): boolean {
  return TEST_KINDS.includes(kind);
}

async function countSince(
  svc: SupabaseClient,
  filters: Record<string, string>,
  sinceIso: string,
): Promise<number> {
  let q = svc
    .from("crash_alert_counters")
    .select("id", { count: "exact", head: true })
    .gte("created_at", sinceIso);
  for (const [k, v] of Object.entries(filters)) {
    q = q.eq(k, v);
  }
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

function isoAgo(ms: number): string {
  return new Date(Date.now() - ms).toISOString();
}

const DAY = 24 * 60 * 60_000;
const HOUR = 60 * 60_000;
const MINUTE = 60_000;

// A per-user cap hit rejects the whole request (429). Returns a scope string or null (ok).
export interface UserLimitResult {
  scope: string | null;
  retryAfterSeconds?: number;
}

export async function checkUserLimits(
  svc: SupabaseClient,
  userId: string,
  kind: Kind,
  cfg: Config,
): Promise<UserLimitResult> {
  // Burst: requests per user per minute.
  const burst = await countSince(svc, { user_id: userId, bucket: "burst" }, isoAgo(MINUTE));
  if (burst >= cfg.burst_per_user_per_min) {
    return { scope: "burst", retryAfterSeconds: 60 };
  }

  // Global spend guard: messages per hour across all users.
  const global = await countSince(svc, { bucket: "global" }, isoAgo(HOUR));
  if (global >= cfg.global_per_hour) {
    return { scope: "global", retryAfterSeconds: 3600 };
  }

  if (kind === "crash_alert") {
    const n = await countSince(svc, { user_id: userId, bucket: "real_alert" }, isoAgo(DAY));
    if (n >= cfg.real_alerts_per_user_24h) return { scope: "real_alerts_24h" };
  } else {
    const n = await countSince(svc, { user_id: userId, bucket: "test_message" }, isoAgo(DAY));
    if (n >= cfg.test_messages_per_user_24h) return { scope: "test_messages_24h" };
  }
  return { scope: null };
}

// Per-recipient caps. Rejecting a recipient does not reject the whole request. Returns a Whoosh
// error code or null (ok).
export async function checkRecipientLimits(
  svc: SupabaseClient,
  userId: string,
  recipientHash: string,
  kind: Kind,
  cfg: Config,
): Promise<string | null> {
  if (kind === "crash_alert") {
    // Per-recipient real across all users.
    const all = await countSince(
      svc,
      { recipient_hash: recipientHash, bucket: "recipient_real" },
      isoAgo(DAY),
    );
    if (all >= cfg.real_per_recipient_all_24h) return "rate_limited_recipient";
  } else {
    // Per-recipient test across all users.
    const all = await countSince(
      svc,
      { recipient_hash: recipientHash, bucket: "recipient_test" },
      isoAgo(DAY),
    );
    if (all >= cfg.test_per_recipient_all_24h) return "rate_limited_recipient";
    // Test-type per recipient per user.
    const perUser = await countSince(
      svc,
      { user_id: userId, recipient_hash: recipientHash, bucket: "recipient_test" },
      isoAgo(DAY),
    );
    if (perUser >= cfg.test_per_recipient_user_24h) return "rate_limited_recipient";
  }
  return null;
}

// Record a successful send by inserting the relevant counter rows.
export async function recordSend(
  svc: SupabaseClient,
  userId: string,
  recipientHash: string,
  kind: Kind,
): Promise<void> {
  const rows: Record<string, unknown>[] = [
    { user_id: userId, bucket: "burst" },
    { bucket: "global" },
  ];
  if (kind === "crash_alert") {
    rows.push({ user_id: userId, bucket: "real_alert" });
    rows.push({ user_id: userId, recipient_hash: recipientHash, bucket: "recipient_real" });
  } else {
    rows.push({ user_id: userId, bucket: "test_message" });
    rows.push({ user_id: userId, recipient_hash: recipientHash, bucket: "recipient_test" });
  }
  await svc.from("crash_alert_counters").insert(rows);
}

// Record a burst event for a request even when nothing was sent (so repeated rejected requests
// still count toward the per-minute burst cap).
export async function recordBurst(svc: SupabaseClient, userId: string): Promise<void> {
  await svc.from("crash_alert_counters").insert([{ user_id: userId, bucket: "burst" }]);
}
