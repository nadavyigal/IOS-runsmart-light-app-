// NotifyStore (_shared/notify.ts) backed by a service-role supabase-js client.
// Moved here from coach_notify/store.ts in C7.6 so every sender (coach_notify,
// coach_evening_summary) uses the same database code. M2b's functions
// (coach_notify_link_state, coach_notify_claim, coach_notify_defer) and both M2b
// tables are granted to service_role only.

import { type ApnsTarget, liveTokensFor, type PushTokenStore } from "./apns.ts";
import type { ClaimDecision, DeferDecision, DeferredRow, LinkState, NotificationPrefs, NotifyStore } from "./notify.ts";

// The supabase-js surface used here, kept loose so the module needs no type import.
// deno-lint-ignore no-explicit-any
type Client = any;

export const PREF_COLUMNS =
  "user_id, coach_run_finished, coach_evening_summary, coach_pain_flag, athlete_coach_note, athlete_plan_updates, athlete_broadcasts, quiet_start, quiet_end, time_zone";

export function supabaseNotifyStore(admin: Client): NotifyStore {
  return {
    async linkState(athleteId: string): Promise<LinkState | null> {
      const { data, error } = await admin.rpc("coach_notify_link_state", { p_athlete: athleteId });
      if (error) throw new Error(`link_state_failed: ${error.message}`);
      const row = Array.isArray(data) ? data[0] : null;
      return row ? (row as LinkState) : null;
    },

    async prefs(userId: string): Promise<NotificationPrefs | null> {
      const { data, error } = await admin.from("notification_prefs").select(PREF_COLUMNS).eq("user_id", userId)
        .maybeSingle();
      if (error) throw new Error(`prefs_failed: ${error.message}`);
      return (data as NotificationPrefs | null) ?? null;
    },

    async claim(input) {
      const { data, error } = await admin.rpc("coach_notify_claim", {
        p_recipient: input.recipientId,
        p_athlete: input.athleteId,
        p_link_id: input.linkId,
        p_kind: input.kind,
        p_ref_id: input.refId,
        p_dedupe_seconds: input.dedupeSeconds,
        p_burst_limit: input.burstLimit,
        p_burst_seconds: input.burstSeconds,
      });
      if (error) throw new Error(`claim_failed: ${error.message}`);
      const row = (Array.isArray(data) ? data[0] : data) as { decision: ClaimDecision; log_id: string | null };
      return { decision: row.decision, logId: row.log_id ?? null };
    },

    async defer(input) {
      const { data, error } = await admin.rpc("coach_notify_defer", {
        p_recipient: input.recipientId,
        p_athlete: input.athleteId,
        p_link_id: input.linkId,
        p_kind: input.kind,
        p_ref_id: input.refId,
        p_dedupe_seconds: input.dedupeSeconds,
        p_payload: input.payload,
      });
      if (error) throw new Error(`defer_failed: ${error.message}`);
      return data as DeferDecision;
    },

    async setOutcome(logId, outcome) {
      const { error } = await admin.from("coach_notification_log").update({ outcome }).eq("id", logId);
      if (error) throw new Error(`outcome_failed: ${error.message}`);
    },

    async insertLog(input) {
      const { data, error } = await admin.from("coach_notification_log").insert({
        recipient_id: input.recipientId,
        athlete_id: input.athleteId,
        kind: input.kind,
        ref_id: input.refId,
        item_count: input.itemCount,
      }).select("id").single();
      if (error) {
        if (error.code === "23505") return null; // already logged
        throw new Error(`log_failed: ${error.message}`);
      }
      return (data as { id: string }).id;
    },

    async pendingDeferred(kinds, limit) {
      const { data, error } = await admin.from("deferred_pushes")
        .select(
          "id, recipient_id, kind, payload, created_at, athlete_id, coach_id, link_id, ref_id, reason, deliver_after",
        )
        .in("kind", kinds)
        .order("created_at", { ascending: true })
        .limit(limit);
      if (error) throw new Error(`deferred_read_failed: ${error.message}`);
      return (data ?? []) as DeferredRow[];
    },

    async deleteDeferred(ids) {
      if (ids.length === 0) return [];
      const { data, error } = await admin.from("deferred_pushes").delete().in("id", ids).select("id");
      if (error) throw new Error(`deferred_delete_failed: ${error.message}`);
      return ((data ?? []) as { id: string }[]).map((row) => row.id);
    },

    liveTokens(userId: string): Promise<ApnsTarget[]> {
      return liveTokensFor(admin as PushTokenStore, userId);
    },
  };
}
