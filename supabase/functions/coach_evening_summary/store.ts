// The database side of coach_evening_summary: SummaryStore (summary.ts) backed by a
// service-role supabase-js client. The NotifyStore half is shared with coach_notify
// (_shared/notify_store.ts). coach_evening_summary_counts and both M2b tables are
// granted to service_role only.

import type { NotificationPrefs } from "../_shared/notify.ts";
import { PREF_COLUMNS, supabaseNotifyStore } from "../_shared/notify_store.ts";
import { NO_LINK, SUMMARY_KIND, type SummaryCounts, type SummaryStore } from "./summary.ts";

// deno-lint-ignore no-explicit-any
type Client = any;

const COACH_PAGE = 1000;
const PREFS_CHUNK = 100;

export function supabaseSummaryStore(admin: Client): SummaryStore {
  return {
    ...supabaseNotifyStore(admin),

    async summaryRecipients(): Promise<NotificationPrefs[]> {
      const coaches = new Set<string>();
      for (let from = 0;; from += COACH_PAGE) {
        const { data, error } = await admin.from("coach_athlete_links").select("coach_id")
          .eq("status", "active").order("coach_id").range(from, from + COACH_PAGE - 1);
        if (error) throw new Error(`links_read_failed: ${error.message}`);
        const rows = (data ?? []) as { coach_id: string }[];
        for (const row of rows) coaches.add(row.coach_id);
        if (rows.length < COACH_PAGE) break;
      }

      const ids = [...coaches];
      const out: NotificationPrefs[] = [];
      for (let i = 0; i < ids.length; i += PREFS_CHUNK) {
        const { data, error } = await admin.from("notification_prefs").select(PREF_COLUMNS)
          .in("user_id", ids.slice(i, i + PREFS_CHUNK)).eq("coach_evening_summary", true);
        if (error) throw new Error(`prefs_failed: ${error.message}`);
        out.push(...((data ?? []) as NotificationPrefs[]));
      }
      return out;
    },

    async summaryCounts(coachId: string, day: string, timeZone: string): Promise<SummaryCounts> {
      const { data, error } = await admin.rpc("coach_evening_summary_counts", {
        p_coach: coachId,
        p_day: day,
        p_time_zone: timeZone,
      });
      if (error) throw new Error(`counts_failed: ${error.message}`);
      const row = (Array.isArray(data) ? data[0] : data) as SummaryCounts | null;
      return row ?? { missed: 0, open_flags: 0, plan_changes: 0 };
    },

    async summaryLogged(coachId: string, day: string): Promise<boolean> {
      const { data, error } = await admin.from("coach_notification_log").select("id")
        .eq("recipient_id", coachId).eq("kind", SUMMARY_KIND).eq("ref_id", day).limit(1);
      if (error) throw new Error(`log_read_failed: ${error.message}`);
      return ((data ?? []) as unknown[]).length > 0;
    },

    async deferSummary(coachId: string, day: string) {
      // One summary is about every link, so athlete_id and coach_id are the coach and
      // link_id is the nil id. The summary flush recounts every link at send time and
      // never reads link_id; coach_notify's flush never reads this kind.
      const { error } = await admin.from("deferred_pushes").insert({
        recipient_id: coachId,
        kind: SUMMARY_KIND,
        payload: { day },
        athlete_id: coachId,
        coach_id: coachId,
        link_id: NO_LINK,
        ref_id: day,
        reason: "quiet",
        deliver_after: null,
      });
      if (error) {
        if (error.code === "23505") return "duplicate";
        throw new Error(`defer_failed: ${error.message}`);
      }
      return "deferred";
    },
  };
}
