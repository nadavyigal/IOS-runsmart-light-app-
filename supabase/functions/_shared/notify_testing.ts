// Test double for NotifyStore (tests only; nothing deployed imports it).
//
// claim() and defer() follow the same contract as M2b's coach_notify_claim and
// coach_notify_defer (supabase/migrations/20261122110000_notification_log_and_deferred.sql),
// which supabase/tests/notification_log_and_deferred.sql proves on Postgres:
// duplicate by (recipient, kind, ref_id) in the log or the deferred rows; dedupe by
// (recipient, athlete, kind) within the window in either table; burst when the
// recipient got `limit` pushes of the kind within the window or a burst is open,
// due at the first of those sends plus the window.

import type { ApnsTarget } from "./apns.ts";
import type {
  ClaimInput,
  DeferInput,
  DeferredRow,
  LinkState,
  LogInput,
  LogOutcome,
  NotificationPrefs,
  NotifyStore,
} from "./notify.ts";

export interface FakeLogRow {
  id: string;
  recipient_id: string;
  athlete_id: string | null;
  kind: string;
  ref_id: string | null;
  sent_at: number;
  item_count: number;
  outcome: "pending" | LogOutcome;
}

export class FakeNotifyStore implements NotifyStore {
  links = new Map<string, LinkState>();
  prefsRows = new Map<string, NotificationPrefs>();
  tokens = new Map<string, ApnsTarget[]>();
  log: FakeLogRow[] = [];
  deferred: DeferredRow[] = [];
  private seq = 0;

  constructor(private readonly clock: () => Date) {}

  private id(): string {
    this.seq += 1;
    return `00000000-0000-4000-8000-${String(this.seq).padStart(12, "0")}`;
  }

  linkState(athleteId: string): Promise<LinkState | null> {
    return Promise.resolve(this.links.get(athleteId) ?? null);
  }

  prefs(userId: string): Promise<NotificationPrefs | null> {
    return Promise.resolve(this.prefsRows.get(userId) ?? null);
  }

  private duplicate(recipient: string, kind: string, ref: string | null): boolean {
    if (ref === null) return false;
    return this.log.some((g) => g.recipient_id === recipient && g.kind === kind && g.ref_id === ref) ||
      this.deferred.some((d) => d.recipient_id === recipient && d.kind === kind && d.ref_id === ref);
  }

  private deduped(recipient: string, athlete: string, kind: string, seconds: number): boolean {
    if (seconds <= 0) return false;
    const start = this.clock().getTime() - seconds * 1000;
    return this.log.some((g) =>
      g.recipient_id === recipient && g.athlete_id === athlete && g.kind === kind && g.sent_at > start
    ) ||
      this.deferred.some((d) =>
        d.recipient_id === recipient && d.athlete_id === athlete && d.kind === kind && Date.parse(d.created_at) > start
      );
  }

  claim(input: ClaimInput) {
    const now = this.clock().getTime();
    if (this.duplicate(input.recipientId, input.kind, input.refId)) {
      return Promise.resolve({ decision: "duplicate" as const, logId: null });
    }
    if (this.deduped(input.recipientId, input.athleteId, input.kind, input.dedupeSeconds)) {
      return Promise.resolve({ decision: "deduped" as const, logId: null });
    }
    if (input.burstLimit !== null && input.burstSeconds) {
      const open = this.deferred
        .filter((d) =>
          d.recipient_id === input.recipientId && d.kind === input.kind && d.reason === "burst" &&
          d.deliver_after !== null && Date.parse(d.deliver_after) > now
        )
        .map((d) => Date.parse(d.deliver_after!));
      let due: number | null = open.length ? Math.min(...open) : null;
      if (due === null) {
        const recent = this.log.filter((g) =>
          g.recipient_id === input.recipientId && g.kind === input.kind && g.sent_at > now - input.burstSeconds! * 1000
        );
        if (recent.length >= input.burstLimit) {
          due = Math.min(...recent.map((g) => g.sent_at)) + input.burstSeconds * 1000;
        }
      }
      if (due !== null) {
        const link = [...this.links.values()].find((l) => l.link_id === input.linkId);
        this.deferred.push({
          id: this.id(),
          recipient_id: input.recipientId,
          kind: input.kind,
          payload: {},
          created_at: new Date(now).toISOString(),
          athlete_id: input.athleteId,
          coach_id: link?.coach_id ?? input.recipientId,
          link_id: input.linkId,
          ref_id: input.refId,
          reason: "burst",
          deliver_after: new Date(due).toISOString(),
        });
        return Promise.resolve({ decision: "deferred_burst" as const, logId: null });
      }
    }
    const row: FakeLogRow = {
      id: this.id(),
      recipient_id: input.recipientId,
      athlete_id: input.athleteId,
      kind: input.kind,
      ref_id: input.refId,
      sent_at: now,
      item_count: 1,
      outcome: "pending",
    };
    this.log.push(row);
    return Promise.resolve({ decision: "claimed" as const, logId: row.id });
  }

  defer(input: DeferInput) {
    if (this.duplicate(input.recipientId, input.kind, input.refId)) return Promise.resolve("duplicate" as const);
    if (this.deduped(input.recipientId, input.athleteId, input.kind, input.dedupeSeconds)) {
      return Promise.resolve("deduped" as const);
    }
    const link = [...this.links.values()].find((l) => l.link_id === input.linkId);
    if (!link) throw new Error("link_missing");
    this.deferred.push({
      id: this.id(),
      recipient_id: input.recipientId,
      kind: input.kind,
      payload: { ...input.payload },
      created_at: this.clock().toISOString(),
      athlete_id: input.athleteId,
      coach_id: link.coach_id,
      link_id: input.linkId,
      ref_id: input.refId,
      reason: "quiet",
      deliver_after: null,
    });
    return Promise.resolve("deferred" as const);
  }

  setOutcome(logId: string, outcome: LogOutcome): Promise<void> {
    const row = this.log.find((g) => g.id === logId);
    if (row) row.outcome = outcome;
    return Promise.resolve();
  }

  insertLog(input: LogInput): Promise<string | null> {
    if (
      input.refId !== null &&
      this.log.some((g) => g.recipient_id === input.recipientId && g.kind === input.kind && g.ref_id === input.refId)
    ) {
      return Promise.resolve(null);
    }
    const row: FakeLogRow = {
      id: this.id(),
      recipient_id: input.recipientId,
      athlete_id: input.athleteId,
      kind: input.kind,
      ref_id: input.refId,
      sent_at: this.clock().getTime(),
      item_count: input.itemCount,
      outcome: "pending",
    };
    this.log.push(row);
    return Promise.resolve(row.id);
  }

  pendingDeferred(kinds: readonly string[], limit: number): Promise<DeferredRow[]> {
    return Promise.resolve(
      [...this.deferred].filter((d) => kinds.includes(d.kind)).sort((a, b) => a.created_at.localeCompare(b.created_at)).slice(0, limit).map((d) => ({
        ...d,
      })),
    );
  }

  deleteDeferred(ids: readonly string[]): Promise<string[]> {
    const wanted = new Set(ids);
    const gone = this.deferred.filter((d) => wanted.has(d.id)).map((d) => d.id);
    this.deferred = this.deferred.filter((d) => !wanted.has(d.id));
    return Promise.resolve(gone);
  }

  liveTokens(userId: string): Promise<ApnsTarget[]> {
    return Promise.resolve(this.tokens.get(userId) ?? []);
  }
}

/** D6 defaults, in a zone. */
export function defaultPrefs(
  userId: string,
  timeZone: string,
  overrides: Partial<NotificationPrefs> = {},
): NotificationPrefs {
  return {
    user_id: userId,
    coach_run_finished: true,
    coach_evening_summary: true,
    coach_pain_flag: true,
    athlete_coach_note: true,
    athlete_plan_updates: true,
    athlete_broadcasts: true,
    quiet_start: "21:30:00",
    quiet_end: "07:00:00",
    time_zone: timeZone,
    ...overrides,
  };
}
