// The database side of athlete_plan_update_digest: DigestStore (digest.ts) backed by
// a service-role supabase-js client. The NotifyStore half is shared with the other
// senders (_shared/notify_store.ts). athlete_plan_update_queue (M6a,
// 20261127100000_coach_workout_locks.sql) grants select, update and delete to
// service_role only. No SQL function is needed: the compare-and-set is a plain
// filtered update / delete, which Postgres runs atomically per row.

import { supabaseNotifyStore } from "../_shared/notify_store.ts";
import type { DigestStore, PlanUpdateRow } from "./digest.ts";

// deno-lint-ignore no-explicit-any
type Client = any;

const QUEUE = "athlete_plan_update_queue";
const COLUMNS = "athlete_id, coach_id, first_change_at, last_change_at, change_count, sent_at";

export function supabaseDigestStore(admin: Client): DigestStore {
  return {
    ...supabaseNotifyStore(admin),

    async pendingPlanUpdates(before: string, limit: number): Promise<PlanUpdateRow[]> {
      const { data, error } = await admin.from(QUEUE).select(COLUMNS)
        .is("sent_at", null)
        .lt("last_change_at", before)
        .order("last_change_at", { ascending: true })
        .limit(limit);
      if (error) throw new Error(`queue_read_failed: ${error.message}`);
      return (data ?? []) as PlanUpdateRow[];
    },

    async claimPlanUpdate(row: PlanUpdateRow, sentAt: string): Promise<PlanUpdateRow | null> {
      // last_change_at is passed back exactly as PostgREST returned it (microseconds
      // and offset included), so the equality is exact.
      const { data, error } = await admin.from(QUEUE).update({ sent_at: sentAt })
        .eq("athlete_id", row.athlete_id)
        .is("sent_at", null)
        .eq("last_change_at", row.last_change_at)
        .eq("change_count", row.change_count)
        .select(COLUMNS);
      if (error) throw new Error(`queue_claim_failed: ${error.message}`);
      const rows = (data ?? []) as PlanUpdateRow[];
      return rows[0] ?? null;
    },

    async dropPlanUpdate(row: PlanUpdateRow): Promise<boolean> {
      const { data, error } = await admin.from(QUEUE).delete()
        .eq("athlete_id", row.athlete_id)
        .is("sent_at", null)
        .eq("last_change_at", row.last_change_at)
        .eq("change_count", row.change_count)
        .select("athlete_id");
      if (error) throw new Error(`queue_drop_failed: ${error.message}`);
      return ((data ?? []) as unknown[]).length > 0;
    },
  };
}
