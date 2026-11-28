// The bundled athlete plan-update push (story C8.16, plan D3). Pure logic over a
// DigestStore; handler.ts calls it, store.ts backs it with supabase-js.
//
// Every coach write RPC (M6a, coach_enqueue_plan_update) upserts one
// athlete_plan_update_queue row per athlete: change_count and last_change_at grow
// while the batch is unsent, and a change that finds sent_at set starts a new batch.
// Each cron run (every 2 minutes) reads the unsent rows whose last change is more
// than 10 minutes old (AC1) and, for each one:
//
//   1. The athlete's active link (coach_notify_link_state, read now):
//      no active link, a different coach, or link_is_v2 false (kill switch, an old
//      build, the allowlist) -> the row is deleted and nothing is sent (AC3).
//   2. The athlete's notification_prefs: no row, or "Plan updates"
//      (athlete_plan_updates) off -> the batch is marked sent and nothing is sent or
//      logged, the way coach_notify drops an event whose pref is off (C7.5 AC8).
//   3. Quiet hours in the athlete's own zone -> the row is left as it is. It is the
//      hold: changes made during the night join the same batch, and the first run
//      after quiet end sends ONE push for all of them. A deferred_pushes row is not
//      used on purpose: the publish RPC (C8.7) deletes the queue row so a publish
//      notifies once (D6, AC2), and a copy in deferred_pushes would escape that.
//   4. Otherwise the batch is claimed and one push goes out:
//      "{Coach} updated your plan · {n} changes", logged as athletePlanUpdated.
//
// Claim and drop are compare-and-set on (sent_at is null, last_change_at,
// change_count) as read. Two overlapping runs: only one update matches, so the push
// goes out once (AC4). A change that lands between the read and the claim moves
// last_change_at, the claim matches nothing, and the row waits for its own 10 quiet
// minutes, so that change is never lost. A change after the claim finds sent_at set
// and starts a new batch (M6a's upsert).
//
// AC2 (publish removes the pending row): C8.7 must delete the athlete's queue row in
// the publish RPC. This function then has nothing to read and sends nothing.
//
// The kill switch (coach_v2, coach_v2_push) is checked by handler.ts before this
// runs: off, nothing is read, sent or deleted, so every row is kept (AC3).
//
// The push names only the coach (coach_profiles.display_name, isolated with FSI ...
// PDI) and carries only coach_id. The tap opens Today, where the change-list card
// lives (RemotePushRouter, athletePlanUpdated).

import {
  copy,
  deliverPush,
  gatePasses,
  isQuietTime,
  type NotifyDeps,
  type NotifyStore,
  type PlanUpdateKind,
} from "../_shared/notify.ts";

export const PLAN_UPDATE_KIND: PlanUpdateKind = "athletePlanUpdated";
/** D3: the push goes out once the coach has made no change for 10 minutes. */
export const QUIET_PERIOD_MS = 10 * 60 * 1000;
/** Rows read per run, oldest last change first. The rest wait for the next run. */
export const DIGEST_BATCH = 500;
/** coach_notification_log_shape: item_count between 1 and 10000. */
const MAX_ITEM_COUNT = 10000;

/** One athlete_plan_update_queue row, as read. Timestamps are kept as the exact strings read. */
export interface PlanUpdateRow {
  athlete_id: string;
  coach_id: string | null;
  first_change_at: string;
  last_change_at: string;
  change_count: number;
  sent_at: string | null;
}

/** What the digest needs on top of NotifyStore. */
export interface DigestStore extends NotifyStore {
  /** Rows with sent_at null and last_change_at < `before`, oldest last change first, at most `limit`. */
  pendingPlanUpdates(before: string, limit: number): Promise<PlanUpdateRow[]>;
  /**
   * Sets sent_at = `sentAt` where athlete_id, sent_at is null, last_change_at and
   * change_count all still match `row`. Returns the claimed row, or null when the row
   * changed, was claimed by another run, or is gone.
   */
  claimPlanUpdate(row: PlanUpdateRow, sentAt: string): Promise<PlanUpdateRow | null>;
  /** Deletes the row under the same compare-and-set. True when this call deleted it. */
  dropPlanUpdate(row: PlanUpdateRow): Promise<boolean>;
}

export interface DigestDeps extends NotifyDeps {
  store: DigestStore;
}

export type DigestResult =
  | "sent"
  | "no_device"
  | "send_failed"
  | "link_ended"
  | "no_prefs"
  | "pref_off"
  | "deferred_quiet"
  | "raced"
  | "error";

export interface DigestSummary {
  pending: number;
  sent: number;
  dropped: number;
  suppressed: number;
  kept: number;
  raced: number;
  errors: number;
}

export async function sendPlanUpdates(deps: DigestDeps): Promise<DigestSummary> {
  const log = deps.log ?? (() => {});
  const now = (deps.now ?? (() => new Date()))();
  const summary: DigestSummary = { pending: 0, sent: 0, dropped: 0, suppressed: 0, kept: 0, raced: 0, errors: 0 };

  const before = new Date(now.getTime() - QUIET_PERIOD_MS).toISOString();
  const rows = await deps.store.pendingPlanUpdates(before, DIGEST_BATCH);
  for (const row of rows) {
    summary.pending += 1;
    let result: DigestResult;
    try {
      result = await handleRow(row, now, deps);
    } catch (error) {
      // One athlete's failure must not stop the others. An unclaimed row is retried
      // by the next run.
      result = "error";
      log({
        event: "plan_update_digest_error",
        athlete_id: row.athlete_id,
        detail: error instanceof Error ? error.message : String(error),
      });
    }

    switch (result) {
      case "sent":
      case "no_device":
      case "send_failed":
        summary.sent += 1;
        break;
      case "link_ended":
        summary.dropped += 1;
        break;
      case "no_prefs":
      case "pref_off":
        summary.suppressed += 1;
        break;
      case "deferred_quiet":
        summary.kept += 1;
        break;
      case "raced":
        summary.raced += 1;
        break;
      case "error":
        summary.errors += 1;
        break;
    }
    if (result !== "error") {
      log({ event: "plan_update_digest", athlete_id: row.athlete_id, items: row.change_count, decision: result });
    }
  }

  log({ event: "plan_update_digest_done", ...summary });
  return summary;
}

async function handleRow(row: PlanUpdateRow, now: Date, deps: DigestDeps): Promise<DigestResult> {
  const state = await deps.store.linkState(row.athlete_id);
  if (!state || row.coach_id === null || state.coach_id !== row.coach_id || !gatePasses(state, "link_v2")) {
    return (await deps.store.dropPlanUpdate(row)) ? "link_ended" : "raced";
  }

  const prefs = await deps.store.prefs(row.athlete_id);
  if (!prefs || prefs.athlete_plan_updates === false) {
    const claimed = await deps.store.claimPlanUpdate(row, now.toISOString());
    if (!claimed) return "raced";
    return prefs ? "pref_off" : "no_prefs";
  }

  if (isQuietTime(prefs, now)) return "deferred_quiet";

  const claimed = await deps.store.claimPlanUpdate(row, now.toISOString());
  if (!claimed) return "raced";

  const changes = clampCount(claimed.change_count);
  const logId = await deps.store.insertLog({
    recipientId: row.athlete_id,
    athleteId: row.athlete_id,
    kind: PLAN_UPDATE_KIND,
    refId: null,
    itemCount: Math.min(changes, MAX_ITEM_COUNT),
  });
  // ref_id is null, so the log's unique key never refuses it; the claim is the guard.
  if (!logId) return "raced";

  return await deliverPush(
    row.athlete_id,
    {
      kind: PLAN_UPDATE_KIND,
      body: copy.planUpdated(state.coach_name, changes),
      target: { coach_id: state.coach_id },
    },
    logId,
    deps,
  );
}

function clampCount(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n >= 1 ? Math.floor(n) : 1;
}
