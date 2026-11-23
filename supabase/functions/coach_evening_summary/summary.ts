// The 20:00 coach push with counts (story C7.6, plan D6). Pure logic over a
// SummaryStore; handler.ts calls it, store.ts backs it with supabase-js.
//
// Each hourly run does two things, flush first:
//
// 1. flushEveningSummaries: summaries held through quiet hours (AC3). For each held
//    row whose coach is now out of quiet hours (their CURRENT zone and quiet hours):
//      - pref off or prefs gone: dropped, nothing sent (AC4);
//      - the coach's local date is still the summary's day: "Today: …";
//      - it is the next day, before 20:00: "Yesterday: …";
//      - later than that: dropped as stale (that evening's own summary is due).
//    The row is deleted before sending, so two runs at once send it once.
//
// 2. sendEveningSummaries: every coach with an active link and the summary pref on
//    whose local time (notification_prefs.time_zone) is in the 20:00 hour today.
//    The cron runs once an hour, so exactly one run falls in that hour in every
//    zone, half-hour zones and DST days included.
//      - in quiet hours: one held row for that day (kind coachEveningSummary,
//        ref_id = the day), nothing sent now;
//      - otherwise: the counts (coach_evening_summary_counts, AC1, AC7) and, unless
//        all three are 0 (AC2), one push.
//
// At most one summary per coach per local day (AC4): the log row is written before
// the push with ref_id = the coach's local day, and coach_notification_log's unique
// key (recipient_id, kind, ref_id) refuses a second one. A second cron run, a
// deferred row and a same-day send, or a time-zone change that lands on the same
// local date all find that row and send nothing.
//
// The push names nobody (names are in the app) and carries only the day:
// rs { kind: "coachEveningSummary", day }. The tap opens Coach Today filtered to
// "Missed today" (AC5, RemotePushRouter).

import {
  addDays,
  copy,
  deliverPush,
  isQuietTime,
  localDay,
  localMinutes,
  type NotificationPrefs,
  type NotifyDeps,
  type NotifyStore,
  type SummaryKind,
} from "../_shared/notify.ts";

export const SUMMARY_KIND: SummaryKind = "coachEveningSummary";
/** 20:00 local, in minutes after midnight. */
export const SUMMARY_MINUTE = 20 * 60;
/** The run that falls in [20:00, 21:00) local sends it. */
export const SUMMARY_WINDOW_MINUTES = 60;
/** deferred_pushes.link_id is not null, but one summary covers every link. */
export const NO_LINK = "00000000-0000-0000-0000-000000000000";
const FLUSH_BATCH = 1000;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

export interface SummaryCounts {
  missed: number;
  open_flags: number;
  plan_changes: number;
}

export type DeferSummaryDecision = "deferred" | "duplicate";

/** What the summary needs on top of NotifyStore. */
export interface SummaryStore extends NotifyStore {
  /** Prefs rows of coaches with at least one active link and coach_evening_summary on. */
  summaryRecipients(): Promise<NotificationPrefs[]>;
  /** coach_evening_summary_counts (migration 20261122120000). */
  summaryCounts(coachId: string, day: string, timeZone: string): Promise<SummaryCounts>;
  /** True when this coach already has a summary log row for this day. */
  summaryLogged(coachId: string, day: string): Promise<boolean>;
  /** A 'quiet' deferred_pushes row for this coach and day. 'duplicate' when one exists. */
  deferSummary(coachId: string, day: string): Promise<DeferSummaryDecision>;
}

export interface SummaryDeps extends NotifyDeps {
  store: SummaryStore;
}

export type SummaryResult =
  | "sent"
  | "no_device"
  | "send_failed"
  | "all_zero"
  | "duplicate"
  | "deferred_quiet"
  | "pref_off"
  | "not_due";

export interface RunSummary {
  coaches: number;
  due: number;
  sent: number;
  deferred: number;
  all_zero: number;
  duplicate: number;
}

export interface FlushSummary {
  held: number;
  sent: number;
  kept: number;
  dropped: number;
}

/** True when `at` is in the 20:00 hour in `timeZone`. */
export function isSummaryHour(at: Date, timeZone: string): boolean {
  const minutes = localMinutes(at, timeZone);
  return minutes >= SUMMARY_MINUTE && minutes < SUMMARY_MINUTE + SUMMARY_WINDOW_MINUTES;
}

export async function sendEveningSummaries(deps: SummaryDeps): Promise<RunSummary> {
  const log = deps.log ?? (() => {});
  const now = (deps.now ?? (() => new Date()))();
  const summary: RunSummary = { coaches: 0, due: 0, sent: 0, deferred: 0, all_zero: 0, duplicate: 0 };

  for (const prefs of await deps.store.summaryRecipients()) {
    summary.coaches += 1;
    if (!prefs.coach_evening_summary) continue; // AC4
    if (!isSummaryHour(now, prefs.time_zone)) continue;
    summary.due += 1;
    const day = localDay(now, prefs.time_zone);

    if (isQuietTime(prefs, now)) {
      // AC3: hold it. A summary already sent for this day (a time-zone change back
      // into the 20:00 hour) is not held again.
      const decision = (await deps.store.summaryLogged(prefs.user_id, day))
        ? "duplicate"
        : await deps.store.deferSummary(prefs.user_id, day);
      if (decision === "deferred") summary.deferred += 1;
      else summary.duplicate += 1;
      log({ event: "evening_summary", day, decision: decision === "deferred" ? "deferred_quiet" : decision });
      continue;
    }

    const result = await sendSummary(prefs, day, "today", deps);
    if (result === "all_zero") summary.all_zero += 1;
    else if (result === "duplicate") summary.duplicate += 1;
    else if (result === "sent") summary.sent += 1;
  }

  log({ event: "evening_summary_done", ...summary });
  return summary;
}

export async function flushEveningSummaries(deps: SummaryDeps): Promise<FlushSummary> {
  const log = deps.log ?? (() => {});
  const now = (deps.now ?? (() => new Date()))();
  const summary: FlushSummary = { held: 0, sent: 0, kept: 0, dropped: 0 };

  const rows = await deps.store.pendingDeferred([SUMMARY_KIND], FLUSH_BATCH);
  for (const row of rows) {
    summary.held += 1;
    const prefs = await deps.store.prefs(row.recipient_id);
    const payloadDay = typeof row.payload?.day === "string" ? row.payload.day : row.ref_id;
    const day = payloadDay && DAY.test(payloadDay) ? payloadDay : null;

    let send: "today" | "yesterday" | null = null;
    let reason = "";
    if (!prefs || !prefs.coach_evening_summary) {
      reason = "pref_off";
    } else if (!day) {
      reason = "bad_row";
    } else if (isQuietTime(prefs, now)) {
      summary.kept += 1;
      continue;
    } else {
      const today = localDay(now, prefs.time_zone);
      if (today <= day) {
        send = "today";
      } else if (today === addDays(day, 1) && localMinutes(now, prefs.time_zone) < SUMMARY_MINUTE) {
        send = "yesterday";
      } else {
        reason = "stale";
      }
    }

    const deleted = await deps.store.deleteDeferred([row.id]);
    if (!deleted.includes(row.id)) continue; // another run took it
    if (!send || !prefs || !day) {
      summary.dropped += 1;
      log({ event: "evening_summary_flush", decision: reason });
      continue;
    }
    const result = await sendSummary(prefs, day, send, deps);
    if (result === "sent") summary.sent += 1;
    else if (result === "all_zero" || result === "duplicate") summary.dropped += 1;
  }

  log({ event: "evening_summary_flush_done", ...summary });
  return summary;
}

/** Counts, the one-per-day log row, then the push. */
async function sendSummary(
  prefs: NotificationPrefs,
  day: string,
  when: "today" | "yesterday",
  deps: SummaryDeps,
): Promise<SummaryResult> {
  const log = deps.log ?? (() => {});
  const base = { event: "evening_summary", day, when };
  const counts = await deps.store.summaryCounts(prefs.user_id, day, prefs.time_zone);
  const missed = clampCount(counts.missed);
  const openFlags = clampCount(counts.open_flags);
  const planChanges = clampCount(counts.plan_changes);
  if (missed + openFlags + planChanges === 0) {
    log({ ...base, decision: "all_zero" }); // AC2
    return "all_zero";
  }

  const logId = await deps.store.insertLog({
    recipientId: prefs.user_id,
    athleteId: null,
    kind: SUMMARY_KIND,
    refId: day,
    itemCount: 1,
  });
  if (!logId) {
    log({ ...base, decision: "duplicate" }); // AC4
    return "duplicate";
  }

  const outcome = await deliverPush(
    prefs.user_id,
    { kind: SUMMARY_KIND, body: copy.eveningSummary(missed, openFlags, planChanges, when), target: { day } },
    logId,
    deps,
  );
  log({ ...base, decision: outcome, missed, open_flags: openFlags, plan_changes: planChanges });
  return outcome;
}

function clampCount(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}
