// The database side of coach_notify: the source row reads, backed by a
// service-role supabase-js client. The NotifyStore half lives in
// _shared/notify_store.ts (shared with coach_evening_summary, C7.6).

import type { FeedbackRow, FlagRow, ReplyRow, RunRow, SourceReader } from "./handler.ts";

export { supabaseNotifyStore } from "../_shared/notify_store.ts";

// deno-lint-ignore no-explicit-any
type Client = any;

export function supabaseSourceReader(admin: Client): SourceReader {
  return {
    async run(id) {
      if (!/^\d{1,19}$/.test(id)) return null;
      const { data, error } = await admin.from("runs").select("id, auth_user_id, distance, completed_at").eq("id", id)
        .maybeSingle();
      if (error) throw new Error(`run_read_failed: ${error.message}`);
      return (data as RunRow | null) ?? null;
    },
    async flag(id) {
      if (!isUuid(id)) return null;
      const { data, error } = await admin.from("athlete_run_flags").select(
        "id, athlete_id, link_id, run_id, created_at",
      )
        .eq("id", id).maybeSingle();
      if (error) throw new Error(`flag_read_failed: ${error.message}`);
      return (data as FlagRow | null) ?? null;
    },
    async feedback(id) {
      if (!isUuid(id)) return null;
      const { data, error } = await admin.from("coach_feedback").select(
        "id, coach_id, athlete_id, kind, run_id, week_start",
      )
        .eq("id", id).maybeSingle();
      if (error) throw new Error(`feedback_read_failed: ${error.message}`);
      return (data as FeedbackRow | null) ?? null;
    },
    async reply(id) {
      if (!isUuid(id)) return null;
      const { data, error } = await admin.from("coach_feedback_replies")
        .select("id, feedback_id, author_id, link_id, feedback:coach_feedback(coach_id, athlete_id)")
        .eq("id", id).maybeSingle();
      if (error) throw new Error(`reply_read_failed: ${error.message}`);
      return (data as ReplyRow | null) ?? null;
    },
  };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
