// coach_notify (story C7.5): coach and athlete pushes for Coach Experience v2.
//
// Called two ways, both with the header x-coach-notify-secret = COACH_NOTIFY_SECRET
// (docs/coach-v2-batch-b-runbook.md has the exact settings):
//   1. Database Webhooks on INSERT into runs, athlete_run_flags, coach_feedback and
//      coach_feedback_replies. Body: { type: "INSERT", table, schema, record }.
//   2. The flush cron, every minute. Body: { action: "flush" }. It sends the held
//      quiet-hours and burst pushes (_shared/notify.ts flushDeferred).
//
// The webhook record is used only for its id: the row is read again with the
// service role, so a forged body can name a row but never invent one, and every
// decision uses the stored values.
//
// Every request checks the kill switch first (coach_v2 and coach_v2_push, C7.12):
// with either off it sends nothing, holds nothing and deletes nothing (AC10).
//
// What each insert sends (plan C7.5, UX spec §A.6):
//   runs                    coach: "{Athlete} finished a {x} km run" (AC1). No push
//                           for a run whose completed_at is more than 24 h old.
//   athlete_run_flags       coach: "{Athlete} flagged something after a run" (AC4).
//   coach_feedback_replies  coach: "{Athlete} replied to your note" (AC5).
//   coach_feedback          athlete: "{Coach} left you a note" (AC6). kind 'note'
//                           only: the welcome note (kind 'welcome', written by
//                           claim_welcome_note when the athlete joins, or by the
//                           coach's per-athlete override) is never pushed.
// Each needs the athlete's active link, still v2 at send time (AC9); flags and
// replies also need the athlete's v2 consent ack, like the coach reads of them.

import { exitIfFlagsOff, type FlagsRpcClient } from "../_shared/flags.ts";
import {
  copy,
  EVENT_RULES,
  flushDeferred,
  gatePasses,
  IMPORT_MAX_AGE_MS,
  type LinkState,
  type NotifyDeps,
  type NotifyEvent,
  notifyOne,
  utcDay,
} from "../_shared/notify.ts";

export const WEBHOOK_TABLES = ["runs", "athlete_run_flags", "coach_feedback", "coach_feedback_replies"] as const;
export type WebhookTable = typeof WEBHOOK_TABLES[number];

export interface RunRow {
  id: number | string;
  auth_user_id: string | null;
  distance: number | null;
  completed_at: string | null;
}

export interface FlagRow {
  id: string;
  athlete_id: string;
  link_id: string | null;
  run_id: number | string | null;
  created_at: string;
}

export interface FeedbackRow {
  id: string;
  coach_id: string;
  athlete_id: string;
  kind: string;
  run_id: number | string | null;
  week_start: string | null;
}

export interface ReplyRow {
  id: string;
  feedback_id: string;
  author_id: string;
  link_id: string | null;
  /** The note the reply is on. */
  feedback: { coach_id: string; athlete_id: string } | null;
}

/** Reads a source row again by id. Null when it is gone. */
export interface SourceReader {
  run(id: string): Promise<RunRow | null>;
  flag(id: string): Promise<FlagRow | null>;
  feedback(id: string): Promise<FeedbackRow | null>;
  reply(id: string): Promise<ReplyRow | null>;
}

export interface HandlerDeps {
  /** COACH_NOTIFY_SECRET. Null when unset: every call is refused. */
  secret: string | null;
  flags: FlagsRpcClient;
  /** Null when the APNs secrets are missing: every call is refused, nothing is touched. */
  notify: NotifyDeps | null;
  source: SourceReader;
  log?: (line: Record<string, unknown>) => void;
}

export async function handleCoachNotify(req: Request, deps: HandlerDeps): Promise<Response> {
  const log = deps.log ?? ((line: Record<string, unknown>) => console.log(JSON.stringify(line)));
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!deps.secret) return json(500, { error: "server_configuration_missing" });
  if (!(await sameSecret(req.headers.get("x-coach-notify-secret") ?? "", deps.secret))) {
    return json(401, { error: "unauthorized" });
  }

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not_object");
    body = parsed as Record<string, unknown>;
  } catch {
    return json(400, { error: "bad_body" });
  }

  const skip = await exitIfFlagsOff(deps.flags, ["coach_v2", "coach_v2_push"], "coach_notify", { log });
  if (skip) return skip;
  if (!deps.notify) {
    log({ event: "apns_not_configured", function: "coach_notify" });
    return json(503, { error: "apns_not_configured" });
  }

  try {
    if (body.action === "flush") {
      const summary = await flushDeferred({ ...deps.notify, log });
      return json(200, { action: "flush", ...summary });
    }

    const table = body.table;
    const record = body.record as Record<string, unknown> | undefined;
    if (body.type !== "INSERT" || typeof table !== "string" || !isWebhookTable(table) || !record) {
      return json(400, { error: "unsupported_event" });
    }
    const id = record.id;
    if ((typeof id !== "string" || !id) && typeof id !== "number") return json(400, { error: "missing_id" });

    const result = await handleInsert(table, String(id), deps.source, { ...deps.notify, log });
    return json(200, { table, result });
  } catch (error) {
    log({ event: "coach_notify_error", detail: error instanceof Error ? error.message : String(error) });
    return json(500, { error: "internal_error" });
  }
}

export async function handleInsert(
  table: WebhookTable,
  id: string,
  source: SourceReader,
  deps: NotifyDeps,
): Promise<string> {
  const log = deps.log ?? (() => {});
  const now = (deps.now ?? (() => new Date()))();
  const skip = (reason: string) => {
    log({ event: "notify", table, decision: reason });
    return reason;
  };

  switch (table) {
    case "runs": {
      const run = await source.run(id);
      if (!run || !run.auth_user_id) return skip("source_missing");
      const completed = run.completed_at ? Date.parse(run.completed_at) : NaN;
      // AC1: an old import still counts as "new" in the app, but is not pushed.
      if (!Number.isNaN(completed) && now.getTime() - completed > IMPORT_MAX_AGE_MS) return skip("old_import");
      const state = await activeState(run.auth_user_id, "coachRunFinished", deps);
      if (typeof state === "string") return skip(state);
      return await notifyOne(
        event({
          kind: "coachRunFinished",
          recipientId: state.coach_id,
          athleteId: run.auth_user_id,
          linkId: state.link_id,
          refId: String(run.id),
          body: copy.runFinished(state.athlete_name, run.distance === null ? null : Number(run.distance)),
          target: { athlete_id: run.auth_user_id, run_id: String(run.id), day: utcDay(run.completed_at) },
        }),
        deps,
      );
    }

    case "athlete_run_flags": {
      const flag = await source.flag(id);
      if (!flag) return skip("source_missing");
      const state = await activeState(flag.athlete_id, "coachPainFlag", deps);
      if (typeof state === "string") return skip(state);
      if (flag.link_id !== state.link_id) return skip("link_changed");
      return await notifyOne(
        event({
          kind: "coachPainFlag",
          recipientId: state.coach_id,
          athleteId: flag.athlete_id,
          linkId: state.link_id,
          refId: flag.id,
          body: copy.flagged(state.athlete_name),
          target: {
            athlete_id: flag.athlete_id,
            flag_id: flag.id,
            run_id: flag.run_id === null ? undefined : String(flag.run_id),
            day: utcDay(flag.created_at),
          },
        }),
        deps,
      );
    }

    case "coach_feedback_replies": {
      const reply = await source.reply(id);
      if (!reply || !reply.feedback) return skip("source_missing");
      // One level: the author is the note's athlete (M4 enforces it; checked again here).
      if (reply.author_id !== reply.feedback.athlete_id) return skip("not_the_athlete");
      const state = await activeState(reply.author_id, "athleteCoachReply", deps);
      if (typeof state === "string") return skip(state);
      if (reply.link_id !== state.link_id || reply.feedback.coach_id !== state.coach_id) return skip("link_changed");
      return await notifyOne(
        event({
          kind: "athleteCoachReply",
          recipientId: state.coach_id,
          athleteId: reply.author_id,
          linkId: state.link_id,
          refId: reply.id,
          body: copy.replied(state.athlete_name),
          target: { athlete_id: reply.author_id, feedback_id: reply.feedback_id },
        }),
        deps,
      );
    }

    case "coach_feedback": {
      const note = await source.feedback(id);
      if (!note) return skip("source_missing");
      // AC6: welcome notes (and any later kind) are not pushed.
      if (note.kind !== "note") return skip("not_a_note");
      const state = await activeState(note.athlete_id, "athleteCoachNote", deps);
      if (typeof state === "string") return skip(state);
      if (note.coach_id !== state.coach_id) return skip("link_changed");
      return await notifyOne(
        event({
          kind: "athleteCoachNote",
          recipientId: note.athlete_id,
          athleteId: note.athlete_id,
          linkId: state.link_id,
          refId: note.id,
          body: copy.note(state.coach_name),
          target: {
            coach_id: note.coach_id,
            feedback_id: note.id,
            run_id: note.run_id === null ? undefined : String(note.run_id),
          },
        }),
        deps,
      );
    }
  }
}

/** The athlete's active link, if it passes this kind's gate now. Otherwise the reason. */
async function activeState(
  athleteId: string,
  kind: keyof typeof EVENT_RULES,
  deps: NotifyDeps,
): Promise<LinkState | "no_link" | "not_v2"> {
  const state = await deps.store.linkState(athleteId);
  if (!state) return "no_link";
  if (!gatePasses(state, EVENT_RULES[kind].gate)) return "not_v2";
  return state;
}

function event(input: NotifyEvent): NotifyEvent {
  const target: NotifyEvent["target"] = {};
  for (const [key, value] of Object.entries(input.target)) {
    if (typeof value === "string" && value) target[key as keyof NotifyEvent["target"]] = value;
  }
  return { ...input, target };
}

function isWebhookTable(table: string): table is WebhookTable {
  return (WEBHOOK_TABLES as readonly string[]).includes(table);
}

/** Compares SHA-256 digests in constant time, so the length and content of the secret do not leak. */
async function sameSecret(given: string, expected: string): Promise<boolean> {
  if (!given) return false;
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(given)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
