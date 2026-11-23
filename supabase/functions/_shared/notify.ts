// Shared push pipeline for Coach Experience v2 (story C7.5). Every sender uses it:
// coach_notify now, coach_evening_summary (C7.6), the plan digest (C8.16) and the
// broadcast (C8.12) later. v1.3 §1.1 Push AC: every send goes through here, which
// applies prefs, quiet hours, dedupe, collapse, the link re-check and the log.
// The kill switch is checked once per request by the caller (_shared/flags.ts,
// exitIfFlagsOff with coach_v2 and coach_v2_push) before anything here runs.
//
// One event, one recipient (notifyOne):
//   1. The recipient's notification_prefs row. No row: nothing is sent or held
//      (the app creates the row when push is turned on, so no row means no device).
//   2. The pref for this kind is off: nothing is sent and nothing is held (AC8).
//   3. Quiet hours in the recipient's own time_zone: a 'quiet' deferred_pushes row
//      (AC7). Nothing breaks quiet hours, pain flags included (D6).
//   4. Otherwise coach_notify_claim (M2b): a retried event is a duplicate, a second
//      run of one athlete within 30 minutes is deduped (D6, AC2), the 4th and later
//      run-finished push to one coach within 10 minutes goes to a 'burst' row (AC3).
//      A claim writes the coach_notification_log row (AC12), then the push goes to
//      every live device and the outcome is recorded.
//
// The flush (flushDeferred), run by the scheduled call: for each recipient out of
// quiet hours in their CURRENT zone (a zone change or DST is read at flush time),
// the held rows are re-checked (link still the same and still v2, pref still on;
// AC9 drops the rest) and go out as ONE collapsed push.
//
// Push text: no health words, no note, flag or reply text, names isolated with
// FSI ... PDI (C7.15, _shared/text.ts). Custom data carries ids only (apns.ts
// refuses anything else). Logs carry ids, kinds and decisions, never names or text.

import {
  type ApnsConfig,
  type ApnsMessage,
  type ApnsOutcome,
  type ApnsTarget,
  type RemotePushKind,
  type RemotePushTargetKey,
  sendApnsToAll,
  summarizeOutcomes,
} from "./apns.ts";
import { fill, truncateGraphemes } from "./text.ts";

// Types -----------------------------------------------------------------------------

/** The kinds this pipeline sends one event at a time. */
export type EventKind = "coachRunFinished" | "coachPainFlag" | "athleteCoachReply" | "athleteCoachNote";
/** The kinds a flush sends. A single held note goes out as a plain athleteCoachNote. */
export type DigestKind = "coachDigest" | "athleteNotesDigest" | "athleteCoachNote";

export type PrefKey =
  | "coach_run_finished"
  | "coach_evening_summary"
  | "coach_pain_flag"
  | "athlete_coach_note"
  | "athlete_plan_updates"
  | "athlete_broadcasts";

export interface NotificationPrefs extends Record<PrefKey, boolean> {
  user_id: string;
  /** "HH:MM" or "HH:MM:SS", as Postgres returns a time. */
  quiet_start: string;
  quiet_end: string;
  time_zone: string;
}

/** coach_notify_link_state (M2b): the athlete's active link, read at send time. */
export interface LinkState {
  link_id: string;
  coach_id: string;
  link_v2: boolean;
  sharing_allowed: boolean;
  coach_name: string;
  athlete_name: string;
}

/** Which v2 gate an event needs. 'sharing' adds the athlete's consent ack (C7.8). */
export type Gate = "link_v2" | "sharing";

export type ClaimDecision = "claimed" | "duplicate" | "deduped" | "deferred_burst";
export type DeferDecision = "deferred" | "duplicate" | "deduped";
export type LogOutcome = "sent" | "failed" | "no_device";

export interface ClaimInput {
  recipientId: string;
  athleteId: string;
  linkId: string;
  kind: EventKind;
  refId: string;
  dedupeSeconds: number;
  burstLimit: number | null;
  burstSeconds: number | null;
}

export interface DeferInput {
  recipientId: string;
  athleteId: string;
  linkId: string;
  kind: EventKind;
  refId: string;
  dedupeSeconds: number;
  payload: Record<string, string>;
}

export interface DeferredRow {
  id: string;
  recipient_id: string;
  kind: EventKind;
  payload: Record<string, unknown>;
  created_at: string;
  athlete_id: string;
  coach_id: string;
  link_id: string;
  ref_id: string | null;
  reason: "quiet" | "burst";
  deliver_after: string | null;
}

export interface LogInput {
  recipientId: string;
  athleteId: string | null;
  kind: EventKind | DigestKind;
  refId: string | null;
  itemCount: number;
}

/** What the pipeline needs from the database. coach_notify/store.ts backs it with supabase-js. */
export interface NotifyStore {
  linkState(athleteId: string): Promise<LinkState | null>;
  prefs(userId: string): Promise<NotificationPrefs | null>;
  claim(input: ClaimInput): Promise<{ decision: ClaimDecision; logId: string | null }>;
  defer(input: DeferInput): Promise<DeferDecision>;
  setOutcome(logId: string, outcome: LogOutcome): Promise<void>;
  /** A flush's log row. Null when that event was already logged (unique key). */
  insertLog(input: LogInput): Promise<string | null>;
  /**
   * Held rows of these kinds, oldest first, at most `limit`. A sender reads only its
   * own kinds, so it never drops rows a later sender (C7.6, C8.16) holds.
   */
  pendingDeferred(kinds: readonly string[], limit: number): Promise<DeferredRow[]>;
  /** Deletes these rows and returns the ids it deleted (a concurrent flush gets none). */
  deleteDeferred(ids: readonly string[]): Promise<string[]>;
  liveTokens(userId: string): Promise<ApnsTarget[]>;
}

export type NotifyLogger = (line: Record<string, unknown>) => void;

export interface NotifyDeps {
  store: NotifyStore;
  apns: ApnsConfig;
  disableToken: (token: string) => Promise<void>;
  now?: () => Date;
  log?: NotifyLogger;
  /** Tests pass a mock. Default: sendApnsToAll. */
  send?: (targets: readonly ApnsTarget[], message: ApnsMessage) => Promise<ApnsOutcome[]>;
}

// Rules (D6, C7.5) -------------------------------------------------------------------

export const RUN_DEDUPE_SECONDS = 30 * 60;
export const RUN_BURST_LIMIT = 3;
export const RUN_BURST_SECONDS = 10 * 60;
/** Imports with completed_at older than this send no push (AC1). */
export const IMPORT_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const NAME_MAX = 40;
const FLUSH_BATCH = 1000;

export interface EventRule {
  pref: PrefKey | null;
  gate: Gate;
  dedupeSeconds: number;
  burst: boolean;
  side: "coach" | "athlete";
}

export const EVENT_RULES: Record<EventKind, EventRule> = {
  // Runs were shared before v2 (Story 2.x coach reads), so the pair only needs to be v2.
  coachRunFinished: {
    pref: "coach_run_finished",
    gate: "link_v2",
    dedupeSeconds: RUN_DEDUPE_SECONDS,
    burst: true,
    side: "coach",
  },
  // Flags and replies are v2 sharing: the coach reads them only after the ack (C7.4, C7.7).
  coachPainFlag: { pref: "coach_pain_flag", gate: "sharing", dedupeSeconds: 0, burst: false, side: "coach" },
  // T5 has no reply toggle, so replies always notify (quiet hours still apply).
  athleteCoachReply: { pref: null, gate: "sharing", dedupeSeconds: 0, burst: false, side: "coach" },
  athleteCoachNote: { pref: "athlete_coach_note", gate: "link_v2", dedupeSeconds: 0, burst: false, side: "athlete" },
};

export function gatePasses(state: LinkState, gate: Gate): boolean {
  return gate === "sharing" ? state.link_v2 && state.sharing_allowed : state.link_v2;
}

export function prefAllows(prefs: NotificationPrefs, kind: EventKind): boolean {
  const key = EVENT_RULES[kind].pref;
  return key === null || prefs[key] !== false;
}

// Quiet hours -------------------------------------------------------------------------

/** Minutes since local midnight in `timeZone`. An unknown zone falls back to UTC. */
export function localMinutes(at: Date, timeZone: string): number {
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat("en-US", { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .formatToParts(at);
  } catch {
    return at.getUTCHours() * 60 + at.getUTCMinutes();
  }
  const hour = Number(parts.find((p) => p.type === "hour")?.value ?? "0") % 24;
  const minute = Number(parts.find((p) => p.type === "minute")?.value ?? "0");
  return hour * 60 + minute;
}

function timeToMinutes(value: string): number {
  const [h, m] = value.split(":");
  return (Number(h) % 24) * 60 + Number(m ?? 0);
}

/**
 * True when `at` falls in the recipient's quiet hours, in their own zone. The start
 * is inside, the end is outside. A window whose start is after its end runs across
 * midnight (the default 21:30 to 07:00).
 */
export function isQuietTime(
  prefs: Pick<NotificationPrefs, "quiet_start" | "quiet_end" | "time_zone">,
  at: Date,
): boolean {
  const start = timeToMinutes(prefs.quiet_start);
  const end = timeToMinutes(prefs.quiet_end);
  if (start === end) return false;
  const now = localMinutes(at, prefs.time_zone);
  return start < end ? now >= start && now < end : now >= start || now < end;
}

// Copy (plan C7.5 AC1 to AC7, UX spec §A.6) -----------------------------------------------

function name(value: string, fallback: string): string {
  const trimmed = value.trim();
  return truncateGraphemes(trimmed || fallback, NAME_MAX);
}

/** "5", "5.2", "21.1": one decimal, no trailing ".0". Null when there is no distance. */
export function formatKm(distanceKm: number | null | undefined): string | null {
  if (typeof distanceKm !== "number" || !Number.isFinite(distanceKm) || distanceKm < 0.05) return null;
  const rounded = Math.round(distanceKm * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

export const copy = {
  runFinished(athlete: string, distanceKm: number | null | undefined): string {
    const km = formatKm(distanceKm);
    return km
      ? fill("{Athlete} finished a {x} km run", { Athlete: name(athlete, "Athlete") }).replace("{x}", km)
      : fill("{Athlete} finished a run", { Athlete: name(athlete, "Athlete") });
  },
  flagged(athlete: string): string {
    return fill("{Athlete} flagged something after a run", { Athlete: name(athlete, "Athlete") });
  },
  replied(athlete: string): string {
    return fill("{Athlete} replied to your note", { Athlete: name(athlete, "Athlete") });
  },
  note(coach: string): string {
    return fill("{Coach} left you a note", { Coach: name(coach, "Your coach") });
  },
  notes(coach: string, n: number): string {
    if (n <= 1) return copy.note(coach);
    return fill("{Coach} left you {n} notes", { Coach: name(coach, "Your coach") }).replace("{n}", String(n));
  },
  /** AC7. Zero parts are left out [ASSUMPTION; UX spec C7.5 example "4 runs, 1 flag"]. */
  whileAway(runs: number, flags: number, replies: number): string {
    const parts = [
      plural(runs, "run", "runs"),
      plural(flags, "flag", "flags"),
      plural(replies, "reply", "replies"),
    ].filter((part): part is string => part !== null);
    return `While you were away: ${parts.join(" · ")}`;
  },
  /** AC3. */
  moreFinished(n: number): string {
    return n === 1 ? "1 more athlete finished a run" : `${n} more athletes finished runs`;
  },
};

function plural(n: number, one: string, many: string): string | null {
  if (n <= 0) return null;
  return `${n} ${n === 1 ? one : many}`;
}

// One event ---------------------------------------------------------------------------

export interface NotifyEvent {
  kind: EventKind;
  recipientId: string;
  athleteId: string;
  /** The link the event happened on; the active link at event time. */
  linkId: string;
  /** The source row id. */
  refId: string;
  body: string;
  target: Partial<Record<RemotePushTargetKey, string>>;
}

export type NotifyResult =
  | "sent"
  | "no_device"
  | "send_failed"
  | "no_prefs"
  | "pref_off"
  | "deferred_quiet"
  | ClaimDecision
  | DeferDecision;

export async function notifyOne(event: NotifyEvent, deps: NotifyDeps): Promise<NotifyResult> {
  const log = deps.log ?? defaultLogger;
  const now = (deps.now ?? (() => new Date()))();
  const rule = EVENT_RULES[event.kind];
  const base = { event: "notify", kind: event.kind, ref_id: event.refId };

  const prefs = await deps.store.prefs(event.recipientId);
  if (!prefs) {
    log({ ...base, decision: "no_prefs" });
    return "no_prefs";
  }
  if (!prefAllows(prefs, event.kind)) {
    log({ ...base, decision: "pref_off" });
    return "pref_off";
  }

  if (isQuietTime(prefs, now)) {
    const decision = await deps.store.defer({
      recipientId: event.recipientId,
      athleteId: event.athleteId,
      linkId: event.linkId,
      kind: event.kind,
      refId: event.refId,
      dedupeSeconds: rule.dedupeSeconds,
      payload: compactTarget(event.target),
    });
    const result: NotifyResult = decision === "deferred" ? "deferred_quiet" : decision;
    log({ ...base, decision: result });
    return result;
  }

  const claim = await deps.store.claim({
    recipientId: event.recipientId,
    athleteId: event.athleteId,
    linkId: event.linkId,
    kind: event.kind,
    refId: event.refId,
    dedupeSeconds: rule.dedupeSeconds,
    burstLimit: rule.burst ? RUN_BURST_LIMIT : null,
    burstSeconds: rule.burst ? RUN_BURST_SECONDS : null,
  });
  if (claim.decision !== "claimed" || !claim.logId) {
    log({ ...base, decision: claim.decision });
    return claim.decision;
  }

  const outcome = await deliver(
    event.recipientId,
    { kind: event.kind, body: event.body, target: event.target },
    claim.logId,
    deps,
  );
  log({ ...base, decision: outcome });
  return outcome;
}

// Flush -------------------------------------------------------------------------------

export interface FlushSummary {
  recipients: number;
  pushes: number;
  dropped: number;
  kept: number;
}

/**
 * Sends one collapsed push per recipient for the rows that are due, drops the rows
 * whose link or pref is gone (AC9, AC8), keeps the rest. A recipient in quiet hours
 * keeps everything. A 'quiet' row is due once the recipient is out of quiet hours;
 * a 'burst' row at its deliver_after. When any quiet row is due, the recipient's
 * burst rows go in the same push.
 */
export async function flushDeferred(deps: NotifyDeps): Promise<FlushSummary> {
  const log = deps.log ?? defaultLogger;
  const now = (deps.now ?? (() => new Date()))();
  const summary: FlushSummary = { recipients: 0, pushes: 0, dropped: 0, kept: 0 };

  const rows = await deps.store.pendingDeferred(Object.keys(EVENT_RULES), FLUSH_BATCH);
  const byRecipient = new Map<string, DeferredRow[]>();
  for (const row of rows) {
    const list = byRecipient.get(row.recipient_id) ?? [];
    list.push(row);
    byRecipient.set(row.recipient_id, list);
  }

  const linkCache = new Map<string, LinkState | null>();
  const linkStateFor = async (athleteId: string): Promise<LinkState | null> => {
    if (!linkCache.has(athleteId)) linkCache.set(athleteId, await deps.store.linkState(athleteId));
    return linkCache.get(athleteId) ?? null;
  };

  for (const [recipientId, held] of byRecipient) {
    summary.recipients += 1;
    const prefs = await deps.store.prefs(recipientId);

    let due: DeferredRow[];
    if (!prefs) {
      // The row went with the account or was never created: nothing can be sent.
      due = held;
    } else if (isQuietTime(prefs, now)) {
      summary.kept += held.length;
      continue;
    } else if (held.some((row) => row.reason === "quiet")) {
      due = held;
    } else {
      due = held.filter((row) => row.deliver_after !== null && Date.parse(row.deliver_after) <= now.getTime());
    }
    summary.kept += held.length - due.length;
    if (due.length === 0) continue;

    const valid: DeferredRow[] = [];
    for (const row of due) {
      const state = await linkStateFor(row.athlete_id);
      const rule = EVENT_RULES[row.kind];
      const ok = prefs !== null && rule !== undefined && state !== null && state.link_id === row.link_id &&
        state.coach_id === row.coach_id && gatePasses(state, rule.gate) && prefAllows(prefs, row.kind);
      if (ok) valid.push(row);
    }

    const deleted = new Set(await deps.store.deleteDeferred(due.map((row) => row.id)));
    const claimed = valid.filter((row) => deleted.has(row.id));
    summary.dropped += due.filter((row) => deleted.has(row.id)).length - claimed.length;
    if (claimed.length === 0) continue;

    const coachRows = claimed.filter((row) => EVENT_RULES[row.kind].side === "coach");
    const athleteRows = claimed.filter((row) => EVENT_RULES[row.kind].side === "athlete");

    if (coachRows.length > 0) {
      const anyQuiet = coachRows.some((row) => row.reason === "quiet");
      const body = anyQuiet
        ? copy.whileAway(
          coachRows.filter((row) => row.kind === "coachRunFinished").length,
          coachRows.filter((row) => row.kind === "coachPainFlag").length,
          coachRows.filter((row) => row.kind === "athleteCoachReply").length,
        )
        : copy.moreFinished(new Set(coachRows.map((row) => row.athlete_id)).size);
      const logId = await deps.store.insertLog({
        recipientId,
        athleteId: null,
        kind: "coachDigest",
        refId: null,
        itemCount: coachRows.length,
      });
      if (logId) {
        const outcome = await deliver(recipientId, { kind: "coachDigest", body }, logId, deps);
        summary.pushes += 1;
        log({ event: "flush", kind: "coachDigest", items: coachRows.length, decision: outcome });
      }
    }

    if (athleteRows.length > 0) {
      const state = await linkStateFor(athleteRows[0].athlete_id);
      const coachName = state?.coach_name ?? "Your coach";
      const single = athleteRows.length === 1 ? athleteRows[0] : null;
      const kind: DigestKind = single ? "athleteCoachNote" : "athleteNotesDigest";
      const target = single ? stringTarget(single.payload) : { coach_id: athleteRows[0].coach_id };
      const logId = await deps.store.insertLog({
        recipientId,
        athleteId: recipientId,
        kind,
        refId: single?.ref_id ?? null,
        itemCount: athleteRows.length,
      });
      if (logId) {
        const outcome = await deliver(
          recipientId,
          { kind, body: copy.notes(coachName, athleteRows.length), target },
          logId,
          deps,
        );
        summary.pushes += 1;
        log({ event: "flush", kind, items: athleteRows.length, decision: outcome });
      }
    }
  }

  log({ event: "flush_done", ...summary });
  return summary;
}

// Delivery ------------------------------------------------------------------------------

async function deliver(
  recipientId: string,
  message: { kind: RemotePushKind; body: string; target?: Partial<Record<RemotePushTargetKey, string>> },
  logId: string,
  deps: NotifyDeps,
): Promise<"sent" | "no_device" | "send_failed"> {
  const targets = await deps.store.liveTokens(recipientId);
  if (targets.length === 0) {
    await deps.store.setOutcome(logId, "no_device");
    return "no_device";
  }
  const apnsMessage: ApnsMessage = { kind: message.kind, body: message.body, target: message.target };
  const outcomes = deps.send
    ? await deps.send(targets, apnsMessage)
    : await sendApnsToAll(targets, apnsMessage, { config: deps.apns, disableToken: deps.disableToken });
  const counts = summarizeOutcomes(outcomes);
  const sent = counts.sent > 0;
  await deps.store.setOutcome(logId, sent ? "sent" : "failed");
  return sent ? "sent" : "send_failed";
}

const TARGET_KEYS: readonly RemotePushTargetKey[] = [
  "athlete_id",
  "coach_id",
  "day",
  "run_id",
  "flag_id",
  "feedback_id",
  "workout_id",
  "plan_id",
];

function compactTarget(target: Partial<Record<RemotePushTargetKey, string>>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const key of TARGET_KEYS) {
    const value = target[key];
    if (typeof value === "string" && value) out[key] = value;
  }
  return out;
}

function stringTarget(payload: Record<string, unknown>): Partial<Record<RemotePushTargetKey, string>> {
  const out: Partial<Record<RemotePushTargetKey, string>> = {};
  for (const key of TARGET_KEYS) {
    const value = payload[key];
    if (typeof value === "string" && value) out[key] = value;
  }
  return out;
}

/** yyyy-MM-dd of a timestamp in UTC, the day key coach reads use (coach_read_rpcs). */
export function utcDay(value: string | null | undefined): string | undefined {
  if (!value) return undefined;
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) return undefined;
  return new Date(ms).toISOString().slice(0, 10);
}

const defaultLogger: NotifyLogger = (line) => console.log(JSON.stringify(line));
