/**
 * CrashStore backed by Supabase, using the service role (Edge Functions only). Maps the camelCase
 * rows in handlers.ts to the snake_case tables in migration 20261024150000_crash_alerts.sql.
 *
 * Deno-only (npm: import). Not exercised by the Node checks; the handlers it serves are.
 */

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { Bucket, Config, CrashStore, DeliveryRow, EventRow } from "./handlers.ts";
import type { DeliveryStatus } from "./provider.ts";
import type { Kind } from "./template.ts";

const TERMINAL = new Set(["delivered", "undelivered", "failed", "rejected"]);

type Row = Record<string, unknown>;

function toEvent(r: Row): EventRow {
  return {
    id: r.id as string,
    userId: r.user_id as string,
    crashEventId: r.crash_event_id as string,
    kind: r.kind as Kind,
    templateVersion: r.template_version as number,
    consentVersion: r.consent_version as number,
    detectedAt: r.detected_at as string,
    delayedSeconds: r.delayed_seconds as number,
    locationStatus: r.location_status as EventRow["locationStatus"],
    appVersion: (r.app_version as string) ?? "",
    createdAt: r.created_at as string,
  };
}

function toDelivery(r: Row): DeliveryRow {
  return {
    id: r.id as string,
    eventId: r.event_id as string,
    userId: r.user_id as string,
    recipientRef: r.recipient_ref as string,
    recipientHash: r.recipient_hash as string,
    recipientLast2: r.recipient_last2 as string,
    provider: r.provider as string,
    providerMessageSid: (r.provider_message_sid as string) ?? null,
    status: r.status as DeliveryStatus,
    whooshErrorCode: (r.whoosh_error_code as string) ?? null,
    providerErrorCode: (r.provider_error_code as number) ?? null,
    segments: r.segments as number,
    attemptCount: r.attempt_count as number,
    updatedAt: r.updated_at as string,
  };
}

function deliveryColumns(patch: Partial<DeliveryRow>): Row {
  const map: [keyof DeliveryRow, string][] = [
    ["eventId", "event_id"], ["userId", "user_id"], ["recipientRef", "recipient_ref"],
    ["recipientHash", "recipient_hash"], ["recipientLast2", "recipient_last2"], ["provider", "provider"],
    ["providerMessageSid", "provider_message_sid"], ["status", "status"], ["whooshErrorCode", "whoosh_error_code"],
    ["providerErrorCode", "provider_error_code"], ["segments", "segments"], ["attemptCount", "attempt_count"],
  ];
  const out: Row = {};
  for (const [key, column] of map) if (key in patch) out[column] = patch[key];
  if (typeof patch.status === "string" && TERMINAL.has(patch.status)) out.terminal_at = new Date().toISOString();
  return out;
}

function sinceIso(windowSeconds: number): string {
  return new Date(Date.now() - windowSeconds * 1000).toISOString();
}

function must<T>(result: { data: T; error: unknown }): T {
  if (result.error) throw new Error("database_error");
  return result.data;
}

export class SupabaseCrashStore implements CrashStore {
  db: SupabaseClient;

  constructor(url: string, serviceRoleKey: string) {
    this.db = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  }

  async getConfig(): Promise<Config> {
    const r = must(await this.db.from("crash_alert_config").select("*").eq("id", true).single()) as Row;
    return {
      enabled: r.enabled as boolean,
      trialMode: r.trial_mode as boolean,
      minSchemaVersion: r.min_schema_version as number,
      minConsentVersion: r.min_consent_version as number,
      supportedTemplateVersions: r.supported_template_versions as number[],
      maxRecipientsPerRequest: r.max_recipients_per_request as number,
      realAlertsPerUser24h: r.real_alerts_per_user_24h as number,
      testMessagesPerUser24h: r.test_messages_per_user_24h as number,
      testMessagesPerRecipient24h: r.test_messages_per_recipient_24h as number,
      newRecipientsPerUser24h: r.new_recipients_per_user_24h as number,
      realPerRecipientAllUsers24h: r.real_per_recipient_all_users_24h as number,
      testPerRecipientAllUsers24h: r.test_per_recipient_all_users_24h as number,
      burstRequestsPerMinute: r.burst_requests_per_minute as number,
      globalMessagesPerHour: r.global_messages_per_hour as number,
      maxSegments: r.max_segments as number,
    };
  }

  async findEvent(userId: string, crashEventId: string, kind: Kind) {
    const r = must(
      await this.db.from("crash_alert_events").select("*").eq("user_id", userId).eq("crash_event_id", crashEventId).eq("kind", kind).maybeSingle(),
    ) as Row | null;
    return r ? toEvent(r) : null;
  }

  async insertEvent(row: Omit<EventRow, "id" | "createdAt">) {
    const inserted = must(
      await this.db
        .from("crash_alert_events")
        .upsert(
          {
            user_id: row.userId,
            crash_event_id: row.crashEventId,
            kind: row.kind,
            template_version: row.templateVersion,
            consent_version: row.consentVersion,
            detected_at: row.detectedAt,
            delayed_seconds: row.delayedSeconds,
            location_status: row.locationStatus,
            app_version: row.appVersion,
          },
          { onConflict: "user_id,crash_event_id,kind", ignoreDuplicates: true },
        )
        .select("*"),
    ) as Row[];
    if (inserted.length > 0) return { row: toEvent(inserted[0]), created: true };
    const existing = await this.findEvent(row.userId, row.crashEventId, row.kind);
    if (!existing) throw new Error("database_error");
    return { row: existing, created: false };
  }

  async deleteEvent(id: string) {
    must(await this.db.from("crash_alert_events").delete().eq("id", id));
  }

  async findDelivery(eventId: string, recipientHash: string) {
    const r = must(
      await this.db.from("crash_alert_deliveries").select("*").eq("event_id", eventId).eq("recipient_hash", recipientHash).maybeSingle(),
    ) as Row | null;
    return r ? toDelivery(r) : null;
  }

  async insertDelivery(row: Omit<DeliveryRow, "id" | "updatedAt">) {
    const inserted = must(
      await this.db
        .from("crash_alert_deliveries")
        .upsert(deliveryColumns(row), { onConflict: "event_id,recipient_hash", ignoreDuplicates: true })
        .select("*"),
    ) as Row[];
    if (inserted.length > 0) return { row: toDelivery(inserted[0]), created: true };
    const existing = await this.findDelivery(row.eventId, row.recipientHash);
    if (!existing) throw new Error("database_error");
    return { row: existing, created: false };
  }

  async updateDelivery(id: string, patch: Partial<DeliveryRow>) {
    const columns = { ...deliveryColumns(patch), updated_at: new Date().toISOString() };
    const r = must(await this.db.from("crash_alert_deliveries").update(columns).eq("id", id).select("*").single()) as Row;
    return toDelivery(r);
  }

  async listDeliveries(eventId: string) {
    const rows = must(await this.db.from("crash_alert_deliveries").select("*").eq("event_id", eventId).order("created_at")) as Row[];
    return rows.map(toDelivery);
  }

  async take(userId: string, bucket: Bucket, recipientHash: string | null, limit: number, windowSeconds: number, acrossUsers: boolean) {
    return must(
      await this.db.rpc("crash_alert_take", {
        p_user: userId,
        p_bucket: bucket,
        p_recipient_hash: recipientHash,
        p_limit: limit,
        p_window_seconds: windowSeconds,
        p_across_users: acrossUsers,
      }),
    ) as boolean;
  }

  async countUserBucket(userId: string, bucket: Bucket, windowSeconds: number) {
    const result = await this.db
      .from("crash_alert_counters")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("bucket", bucket)
      .gt("created_at", sinceIso(windowSeconds));
    if (result.error) throw new Error("database_error");
    return result.count ?? 0;
  }

  async hasRecentRecipient(userId: string, recipientHash: string, windowSeconds: number) {
    const rows = must(
      await this.db
        .from("crash_alert_deliveries")
        .select("id")
        .eq("user_id", userId)
        .eq("recipient_hash", recipientHash)
        .gt("created_at", sinceIso(windowSeconds))
        .limit(1),
    ) as Row[];
    return rows.length > 0;
  }

  async applyStatus(sid: string, status: DeliveryStatus, providerErrorCode: number | null, whooshErrorCode: string | null) {
    return must(
      await this.db.rpc("crash_alert_apply_status", {
        p_sid: sid,
        p_status: status,
        p_provider_error_code: providerErrorCode,
        p_whoosh_error_code: whooshErrorCode,
      }),
    ) as string;
  }

  async listUserEvents(userId: string, crashEventId: string | null) {
    let query = this.db.from("crash_alert_events").select("*").eq("user_id", userId);
    if (crashEventId !== null) query = query.eq("crash_event_id", crashEventId);
    return (must(await query) as Row[]).map(toEvent);
  }

  async deleteEvents(ids: string[]) {
    if (ids.length === 0) return 0;
    const rows = must(await this.db.from("crash_alert_events").delete().in("id", ids).select("id")) as Row[];
    return rows.length;
  }
}
