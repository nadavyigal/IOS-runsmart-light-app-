import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ApnsMessage, type ApnsTarget, buildApnsPayload } from "../_shared/apns.ts";
import type { FlagsRpcClient } from "../_shared/flags.ts";
import { copy, type LinkState, type NotificationPrefs } from "../_shared/notify.ts";
import { defaultPrefs, FakeNotifyStore } from "../_shared/notify_testing.ts";
import { type DigestDeps, type DigestStore, PLAN_UPDATE_KIND, type PlanUpdateRow, sendPlanUpdates } from "./digest.ts";
import { handlePlanUpdateDigest, type HandlerDeps } from "./handler.ts";

// C8.16 AC1 to AC5 through the cron entry point. The queue is an in-memory copy of
// athlete_plan_update_queue whose enqueue() follows M6a's coach_enqueue_plan_update
// upsert and whose claim / drop follow the compare-and-set in store.ts. The rest of
// the database is FakeNotifyStore (M2b's contract). APNs is mocked: no request
// leaves the test.

const SECRET = "test-secret-value";
const ATHLETE = "aaaaaaaa-0000-4000-8000-00000000000a";
const ATHLETE_2 = "bbbbbbbb-0000-4000-8000-00000000000b";
const COACH = "cccccccc-0000-4000-8000-00000000000c";
const OTHER_COACH = "dddddddd-0000-4000-8000-00000000000d";
const LINK = "11111111-0000-4000-8000-000000000001";
const TOKEN: ApnsTarget = { token: "ab".repeat(32), environment: "production" };
const FSI = "⁨";
const PDI = "⁩";

class FakeDigestStore extends FakeNotifyStore implements DigestStore {
  queue = new Map<string, PlanUpdateRow>();
  /** Awaited inside pendingPlanUpdates after the read, before it returns. */
  afterRead: (() => Promise<void>) | null = null;
  /** Awaited inside claimPlanUpdate before the compare-and-set. */
  beforeClaim: ((row: PlanUpdateRow) => Promise<void>) | null = null;
  failLinkStateFor = new Set<string>();

  constructor(private readonly now: () => Date) {
    super(now);
  }

  /** M6a coach_enqueue_plan_update: one row per athlete, a sent batch restarts. */
  enqueue(athleteId: string, coachId: string) {
    const at = this.now().toISOString();
    const row = this.queue.get(athleteId);
    if (!row) {
      this.queue.set(athleteId, {
        athlete_id: athleteId,
        coach_id: coachId,
        first_change_at: at,
        last_change_at: at,
        change_count: 1,
        sent_at: null,
      });
      return;
    }
    const restart = row.sent_at !== null;
    this.queue.set(athleteId, {
      athlete_id: athleteId,
      coach_id: coachId,
      first_change_at: restart ? at : row.first_change_at,
      last_change_at: at,
      change_count: restart ? 1 : row.change_count + 1,
      sent_at: null,
    });
  }

  override linkState(athleteId: string): Promise<LinkState | null> {
    if (this.failLinkStateFor.has(athleteId)) return Promise.reject(new Error("link_state_failed: boom"));
    return super.linkState(athleteId);
  }

  async pendingPlanUpdates(before: string, limit: number): Promise<PlanUpdateRow[]> {
    const cutoff = Date.parse(before);
    const rows = [...this.queue.values()]
      .filter((r) => r.sent_at === null && Date.parse(r.last_change_at) < cutoff)
      .sort((a, b) => a.last_change_at.localeCompare(b.last_change_at))
      .slice(0, limit)
      .map((r) => ({ ...r }));
    if (this.afterRead) await this.afterRead();
    return rows;
  }

  private matches(row: PlanUpdateRow): PlanUpdateRow | null {
    const live = this.queue.get(row.athlete_id);
    if (!live || live.sent_at !== null) return null;
    if (live.last_change_at !== row.last_change_at || live.change_count !== row.change_count) return null;
    return live;
  }

  async claimPlanUpdate(row: PlanUpdateRow, sentAt: string): Promise<PlanUpdateRow | null> {
    if (this.beforeClaim) await this.beforeClaim(row);
    const live = this.matches(row);
    if (!live) return null;
    live.sent_at = sentAt;
    return { ...live };
  }

  dropPlanUpdate(row: PlanUpdateRow): Promise<boolean> {
    if (!this.matches(row)) return Promise.resolve(false);
    this.queue.delete(row.athlete_id);
    return Promise.resolve(true);
  }
}

interface Sent {
  recipient: string;
  message: ApnsMessage;
  payload: string;
}

function linkState(overrides: Partial<LinkState> = {}): LinkState {
  return {
    link_id: LINK,
    coach_id: COACH,
    link_v2: true,
    sharing_allowed: true,
    coach_name: "Dana",
    athlete_name: "Yoni",
    ...overrides,
  };
}

// Jerusalem in November is UTC+2. 10:00Z is 12:00 local, well outside quiet hours.
function world(start = "2026-11-27T10:00:00Z", prefs: Partial<NotificationPrefs> = {}) {
  let now = new Date(start);
  const store = new FakeDigestStore(() => now);
  const sent: Sent[] = [];
  const flags = { coach_v2: true, coach_v2_push: true };

  store.links.set(ATHLETE, linkState());
  store.prefsRows.set(ATHLETE, defaultPrefs(ATHLETE, "Asia/Jerusalem", prefs));
  store.tokens.set(ATHLETE, [TOKEN]);

  let lastRecipient = "";
  const originalLive = store.liveTokens.bind(store);
  store.liveTokens = (userId: string) => {
    lastRecipient = userId;
    return originalLive(userId);
  };

  const flagsClient: FlagsRpcClient = {
    rpc: () =>
      Promise.resolve({
        data: [
          { key: "coach_v2", enabled: flags.coach_v2 },
          { key: "coach_v2_push", enabled: flags.coach_v2_push },
          { key: "coach_v2_ai", enabled: true },
        ],
        error: null,
      }),
  };

  const digest = (): DigestDeps => ({
    store,
    apns: { keyId: "K", teamId: "T", privateKey: "unused", bundleId: "com.runsmart.lite" },
    disableToken: () => Promise.resolve(),
    now: () => now,
    log: () => {},
    send: (targets, message) => {
      sent.push({ recipient: lastRecipient, message, payload: buildApnsPayload(message) });
      return Promise.resolve(targets.map(() => ({ status: "sent" as const, apnsId: null })));
    },
  });

  const deps = (overrides: Partial<HandlerDeps> = {}): HandlerDeps => ({
    secret: SECRET,
    flags: flagsClient,
    digest: digest(),
    log: () => {},
    ...overrides,
  });

  return {
    store,
    sent,
    flags,
    digest,
    at(iso: string) {
      now = new Date(iso);
    },
    change(athlete = ATHLETE, coach = COACH) {
      store.enqueue(athlete, coach);
    },
    async run(overrides: Partial<HandlerDeps> = {}, secret: string | null = SECRET, init: RequestInit = {}) {
      const headers = new Headers({ "Content-Type": "application/json" });
      if (secret !== null) headers.set("x-coach-notify-secret", secret);
      const res = await handlePlanUpdateDigest(
        new Request("http://localhost/athlete_plan_update_digest", { method: "POST", body: "{}", headers, ...init }),
        deps(overrides),
      );
      return { status: res.status, body: await res.json() as Record<string, unknown> };
    },
    logs() {
      return store.log.filter((g) => g.kind === PLAN_UPDATE_KIND);
    },
    row(athlete = ATHLETE) {
      return store.queue.get(athlete);
    },
  };
}

function rs(sent: Sent): Record<string, unknown> {
  return (JSON.parse(sent.payload) as { rs: Record<string, unknown> }).rs;
}

// AC1: the window ---------------------------------------------------------------------

Deno.test("AC1: nothing goes out while the coach changed something less than 10 minutes ago", async () => {
  const w = world();
  w.change();
  w.at("2026-11-27T10:09:59Z");
  const res = await w.run();
  assertEquals(res.status, 200);
  assertEquals(w.sent.length, 0);
  assertEquals(w.row()?.sent_at, null);
  // Exactly 10 minutes is not yet "older than 10 minutes".
  w.at("2026-11-27T10:10:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
});

Deno.test("AC1: 10 minutes after the last change, one push with the coach's name and the count", async () => {
  const w = world();
  w.change();
  w.at("2026-11-27T10:04:00Z");
  w.change();
  w.at("2026-11-27T10:08:00Z");
  w.change();
  // 10 minutes after the first change is not enough: the last one restarts the wait.
  w.at("2026-11-27T10:12:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);

  w.at("2026-11-27T10:18:01Z");
  const res = await w.run();
  assertEquals(res.status, 200);
  assertEquals(w.sent.length, 1);
  const push = w.sent[0];
  assertEquals(push.recipient, ATHLETE);
  assertEquals(push.message.kind, "athletePlanUpdated");
  assertEquals(push.message.body, `${FSI}Dana${PDI} updated your plan · 3 changes`);
  assertFalse(push.message.body.includes("—"), "no em dash in push copy");
  assertEquals(rs(push).kind, "athletePlanUpdated");
  assertEquals(rs(push).coach_id, COACH);
  assertFalse(push.payload.includes("Yoni"), "the athlete's own name is not in the push");

  const logs = w.logs();
  assertEquals(logs.length, 1);
  assertEquals(logs[0].recipient_id, ATHLETE);
  assertEquals(logs[0].athlete_id, ATHLETE);
  assertEquals(logs[0].ref_id, null);
  assertEquals(logs[0].item_count, 3);
  assertEquals(logs[0].outcome, "sent");
  assertEquals(w.row()?.sent_at, "2026-11-27T10:18:01.000Z");

  // The next run finds nothing to send.
  w.at("2026-11-27T10:20:01Z");
  await w.run();
  assertEquals(w.sent.length, 1);
});

Deno.test("AC1: one change reads '1 change'", async () => {
  const w = world();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].message.body, `${FSI}Dana${PDI} updated your plan · 1 change`);
});

Deno.test("AC1: a change after the push starts a new batch with its own push", async () => {
  const w = world();
  w.change();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);

  w.at("2026-11-27T10:15:00Z");
  w.change();
  assertEquals(w.row()?.change_count, 1);
  assertEquals(w.row()?.sent_at, null);
  w.at("2026-11-27T10:24:00Z");
  await w.run();
  assertEquals(w.sent.length, 1, "the new batch waits its own 10 minutes");
  w.at("2026-11-27T10:25:01Z");
  await w.run();
  assertEquals(w.sent.length, 2);
  assertEquals(w.sent[1].message.body, `${FSI}Dana${PDI} updated your plan · 1 change`);
  assertEquals(w.logs().length, 2);
});

Deno.test("AC1: a Hebrew coach name is isolated and the copy stays in order", async () => {
  const w = world();
  w.store.links.set(ATHLETE, linkState({ coach_name: "דנה" }));
  w.change();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent[0].message.body, `${FSI}דנה${PDI} updated your plan · 2 changes`);
  assertEquals(copy.planUpdated("  ", 2), `${FSI}Your coach${PDI} updated your plan · 2 changes`);
});

Deno.test("AC1: athletes are batched separately, one push each", async () => {
  const w = world();
  w.store.links.set(ATHLETE_2, linkState({ link_id: "11111111-0000-4000-8000-000000000002", athlete_name: "Maya" }));
  w.store.prefsRows.set(ATHLETE_2, defaultPrefs(ATHLETE_2, "Asia/Jerusalem"));
  w.store.tokens.set(ATHLETE_2, [TOKEN]);
  w.change(ATHLETE);
  w.change(ATHLETE_2);
  w.change(ATHLETE_2);
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 2);
  const byRecipient = new Map(w.sent.map((s) => [s.recipient, s.message.body]));
  assertEquals(byRecipient.get(ATHLETE), `${FSI}Dana${PDI} updated your plan · 1 change`);
  assertEquals(byRecipient.get(ATHLETE_2), `${FSI}Dana${PDI} updated your plan · 2 changes`);
});

Deno.test("AC1: no device: logged as no_device, the batch is marked sent", async () => {
  const w = world();
  w.store.tokens.set(ATHLETE, []);
  w.change();
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.logs()[0].outcome, "no_device");
  assert(w.row()?.sent_at);
});

// AC1: prefs ---------------------------------------------------------------------------

Deno.test("AC1: 'Plan updates' off: nothing sent or logged, the batch is marked handled", async () => {
  const w = world("2026-11-27T10:00:00Z", { athlete_plan_updates: false });
  w.change();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  const res = await w.run();
  assertEquals((res.body.run as Record<string, number>).suppressed, 1);
  assertEquals(w.sent.length, 0);
  assertEquals(w.logs().length, 0);
  assert(w.row()?.sent_at, "marked sent, like coach_notify drops a pref-off event");

  // Turning the pref back on does not replay the old batch; a new change does notify.
  w.store.prefsRows.set(ATHLETE, defaultPrefs(ATHLETE, "Asia/Jerusalem"));
  w.at("2026-11-27T10:13:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  w.change();
  w.at("2026-11-27T10:24:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].message.body, `${FSI}Dana${PDI} updated your plan · 1 change`);
});

Deno.test("AC1: other prefs off do not block plan updates", async () => {
  const w = world("2026-11-27T10:00:00Z", { athlete_coach_note: false, athlete_broadcasts: false });
  w.change();
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
});

Deno.test("AC1: no notification_prefs row (no device): nothing sent, the batch is marked handled", async () => {
  const w = world();
  w.store.prefsRows.delete(ATHLETE);
  w.change();
  w.at("2026-11-27T10:11:00Z");
  const res = await w.run();
  assertEquals((res.body.run as Record<string, number>).suppressed, 1);
  assertEquals(w.sent.length, 0);
  assertEquals(w.logs().length, 0);
  assert(w.row()?.sent_at);
});

// AC1: quiet hours ---------------------------------------------------------------------

Deno.test("AC1: in quiet hours the batch is held, then ONE push at quiet end counts the night's changes", async () => {
  // 20:00Z is 22:00 in Jerusalem: inside the default 21:30 to 07:00.
  const w = world("2026-11-27T20:00:00Z");
  w.change();
  w.change();
  w.at("2026-11-27T20:30:00Z");
  const res = await w.run();
  assertEquals((res.body.run as Record<string, number>).kept, 1);
  assertEquals(w.sent.length, 0);
  assertEquals(w.row()?.sent_at, null, "held: still unsent");
  assertEquals(w.store.deferred.length, 0, "no deferred_pushes row, so a publish (C8.7) can still remove it");

  // The coach keeps editing during the night: same batch.
  w.at("2026-11-27T23:00:00Z");
  w.change();
  w.at("2026-11-28T04:59:00Z"); // 06:59 local
  await w.run();
  assertEquals(w.sent.length, 0);

  w.at("2026-11-28T05:00:00Z"); // 07:00 local, quiet end
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].message.body, `${FSI}Dana${PDI} updated your plan · 3 changes`);
  w.at("2026-11-28T05:02:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
});

Deno.test("AC1: quiet hours are read in the athlete's own zone", async () => {
  // 20:00Z is 15:00 in New York: not quiet there, though it is in Jerusalem.
  const w = world("2026-11-27T20:00:00Z");
  w.store.prefsRows.set(ATHLETE, defaultPrefs(ATHLETE, "America/New_York"));
  w.change();
  w.at("2026-11-27T20:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
});

Deno.test("AC1: a held batch whose pref is turned off overnight is dropped at quiet end", async () => {
  const w = world("2026-11-27T20:00:00Z");
  w.change();
  w.at("2026-11-27T20:30:00Z");
  await w.run();
  w.store.prefsRows.set(ATHLETE, defaultPrefs(ATHLETE, "Asia/Jerusalem", { athlete_plan_updates: false }));
  w.at("2026-11-28T05:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assert(w.row()?.sent_at);
});

// AC2: publish suppression -------------------------------------------------------------

Deno.test("AC2: the publish RPC (C8.7) deleted the pending row: nothing is sent", async () => {
  const w = world();
  w.change();
  w.change();
  w.at("2026-11-27T10:05:00Z");
  // C8.7's publish deletes the athlete's queue row in the same transaction.
  w.store.queue.delete(ATHLETE);
  w.at("2026-11-27T10:11:00Z");
  const res = await w.run();
  assertEquals(res.status, 200);
  assertEquals((res.body.run as Record<string, number>).pending, 0);
  assertEquals(w.sent.length, 0);
  assertEquals(w.logs().length, 0);
});

Deno.test("AC2: a publish that lands between the read and the claim still sends nothing", async () => {
  const w = world();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  w.store.beforeClaim = () => {
    w.store.queue.delete(ATHLETE);
    return Promise.resolve();
  };
  const res = await w.run();
  assertEquals((res.body.run as Record<string, number>).raced, 1);
  assertEquals(w.sent.length, 0);
  assertEquals(w.logs().length, 0);
});

Deno.test("AC2: a publish during quiet hours removes the held batch: nothing at quiet end", async () => {
  const w = world("2026-11-27T20:00:00Z"); // 22:00 Jerusalem
  w.change();
  w.change();
  w.at("2026-11-27T20:30:00Z");
  await w.run();
  assertEquals(w.row()?.sent_at, null, "held");
  w.at("2026-11-27T23:00:00Z");
  w.store.queue.delete(ATHLETE); // C8.7 publish
  w.at("2026-11-28T05:00:00Z"); // quiet end
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.logs().length, 0);
  assertEquals(w.store.deferred.length, 0);
});

// AC3: link ended and the kill switch --------------------------------------------------

Deno.test("AC3: the link ended: nothing sent and the row is dropped", async () => {
  const w = world();
  w.change();
  w.store.links.delete(ATHLETE);
  w.at("2026-11-27T10:11:00Z");
  const res = await w.run();
  assertEquals((res.body.run as Record<string, number>).dropped, 1);
  assertEquals(w.sent.length, 0);
  assertEquals(w.row(), undefined);
});

Deno.test("AC3: the pair is no longer v2 (old build, allowlist): nothing sent and the row is dropped", async () => {
  const w = world();
  w.store.links.set(ATHLETE, linkState({ link_v2: false }));
  w.change();
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.row(), undefined);
});

Deno.test("AC3: the athlete now has a different coach: the old coach's batch is dropped", async () => {
  const w = world();
  w.change();
  w.store.links.set(ATHLETE, linkState({ coach_id: OTHER_COACH, link_id: "11111111-0000-4000-8000-000000000009" }));
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.row(), undefined);
});

Deno.test("AC3: the coach account is gone (coach_id set null): the row is dropped", async () => {
  const w = world();
  w.change();
  w.row()!.coach_id = null;
  w.at("2026-11-27T10:11:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.row(), undefined);
});

Deno.test("AC3: kill switch on (coach_v2 or coach_v2_push off): nothing sent, the row is kept", async () => {
  for (const flag of ["coach_v2", "coach_v2_push"] as const) {
    const w = world();
    w.change();
    w.change();
    w.at("2026-11-27T10:11:00Z");
    w.flags[flag] = false;
    const res = await w.run();
    assertEquals(res.status, 200);
    assertEquals(res.body.reason, "skipped_kill_switch");
    assertEquals(w.sent.length, 0);
    assertEquals(w.row()?.sent_at, null, `${flag}: row kept unsent`);
    assertEquals(w.row()?.change_count, 2);

    // The flag returns: the kept batch goes out once.
    w.flags[flag] = true;
    w.at("2026-11-27T10:13:00Z");
    await w.run();
    assertEquals(w.sent.length, 1, `${flag}: sent after the flag returns`);
    assertEquals(w.sent[0].message.body, `${FSI}Dana${PDI} updated your plan · 2 changes`);
  }
});

Deno.test("AC3: flags unreadable: 503, nothing sent, the row is kept", async () => {
  const w = world();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  const res = await w.run({
    flags: { rpc: () => Promise.resolve({ data: null, error: { message: "down" } }) },
  });
  assertEquals(res.status, 503);
  assertEquals(w.sent.length, 0);
  assertEquals(w.row()?.sent_at, null);
});

// AC4: overlapping runs ----------------------------------------------------------------

Deno.test("AC4: two overlapping cron runs read the same row; the push goes out once", async () => {
  const w = world();
  w.change();
  w.change();
  w.at("2026-11-27T10:11:00Z");

  // Both runs finish their read before either claims.
  let reads = 0;
  let release!: () => void;
  const bothRead = new Promise<void>((resolve) => (release = resolve));
  w.store.afterRead = () => {
    reads += 1;
    if (reads === 2) release();
    return bothRead;
  };

  const [a, b] = await Promise.all([w.run(), w.run()]);
  assertEquals(reads, 2);
  assertEquals(a.status, 200);
  assertEquals(b.status, 200);
  assertEquals(w.sent.length, 1, "sent once");
  assertEquals(w.logs().length, 1, "logged once");
  const runs = [a.body.run, b.body.run] as Record<string, number>[];
  assertEquals(runs.map((r) => r.sent).sort(), [0, 1]);
  assertEquals(runs.map((r) => r.raced).sort(), [0, 1]);
});

Deno.test("AC4: two overlapping runs on a link that ended drop the row once and send nothing", async () => {
  const w = world();
  w.change();
  w.store.links.delete(ATHLETE);
  w.at("2026-11-27T10:11:00Z");
  let reads = 0;
  let release!: () => void;
  const bothRead = new Promise<void>((resolve) => (release = resolve));
  w.store.afterRead = () => {
    reads += 1;
    if (reads === 2) release();
    return bothRead;
  };
  const [a, b] = await Promise.all([w.run(), w.run()]);
  const runs = [a.body.run, b.body.run] as Record<string, number>[];
  assertEquals(runs.map((r) => r.dropped).sort(), [0, 1]);
  assertEquals(w.sent.length, 0);
  assertEquals(w.row(), undefined);
});

Deno.test("AC4: a change that lands between the read and the claim is not lost", async () => {
  const w = world();
  w.change();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  let once = true;
  w.store.beforeClaim = () => {
    if (once) {
      once = false;
      w.change(); // the coach edits again right now
    }
    return Promise.resolve();
  };
  const res = await w.run();
  assertEquals((res.body.run as Record<string, number>).raced, 1);
  assertEquals(w.sent.length, 0, "the claim misses, nothing is sent this run");
  assertEquals(w.row()?.sent_at, null);
  assertEquals(w.row()?.change_count, 3, "the new change joined the batch");

  // The batch now waits 10 minutes from that new change, then goes out with all 3.
  w.at("2026-11-27T10:20:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  w.at("2026-11-27T10:21:01Z");
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].message.body, `${FSI}Dana${PDI} updated your plan · 3 changes`);
});

Deno.test("AC4: a link-ended drop that races a new change keeps the row for the next run", async () => {
  const w = world();
  w.change();
  w.store.links.delete(ATHLETE);
  w.at("2026-11-27T10:11:00Z");
  // A change lands after the read: the compare-and-set delete matches nothing.
  w.store.afterRead = () => {
    w.store.afterRead = null;
    w.change();
    return Promise.resolve();
  };
  const res = await w.run();
  assertEquals((res.body.run as Record<string, number>).raced, 1);
  assert(w.row(), "row kept; the next due run drops it");
});

// Robustness and the entry point -------------------------------------------------------

Deno.test("one athlete's failure does not stop the others", async () => {
  const w = world();
  w.store.links.set(ATHLETE_2, linkState({ link_id: "11111111-0000-4000-8000-000000000002" }));
  w.store.prefsRows.set(ATHLETE_2, defaultPrefs(ATHLETE_2, "Asia/Jerusalem"));
  w.store.tokens.set(ATHLETE_2, [TOKEN]);
  w.change(ATHLETE);
  w.at("2026-11-27T10:00:30Z");
  w.change(ATHLETE_2);
  w.store.failLinkStateFor.add(ATHLETE);
  w.at("2026-11-27T10:11:00Z");
  const res = await w.run();
  assertEquals(res.status, 200);
  assertEquals((res.body.run as Record<string, number>).errors, 1);
  assertEquals(w.sent.map((s) => s.recipient), [ATHLETE_2]);
  assertEquals(w.row(ATHLETE)?.sent_at, null, "the failed row is retried next run");
});

Deno.test("the queue read fails: 500, nothing sent", async () => {
  const w = world();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  w.store.pendingPlanUpdates = () => Promise.reject(new Error("queue_read_failed: down"));
  const res = await w.run();
  assertEquals(res.status, 500);
  assertEquals(w.sent.length, 0);
});

Deno.test("entry point: wrong method, missing or wrong secret, bad body, APNs not configured", async () => {
  const w = world();
  w.change();
  w.at("2026-11-27T10:11:00Z");
  assertEquals((await w.run({}, SECRET, { method: "GET", body: undefined })).status, 405);
  assertEquals((await w.run({}, null)).status, 401);
  assertEquals((await w.run({}, "wrong")).status, 401);
  assertEquals((await w.run({ secret: null })).status, 500);
  assertEquals((await w.run({}, SECRET, { body: "[1]" })).status, 400);
  assertEquals((await w.run({}, SECRET, { body: "not json" })).status, 400);
  assertEquals((await w.run({ digest: null })).status, 503);
  assertEquals(w.sent.length, 0);
  assertEquals(w.row()?.sent_at, null);
  // An empty body is fine.
  assertEquals((await w.run({}, SECRET, { body: "" })).status, 200);
  assertEquals(w.sent.length, 1);
});

Deno.test("sendPlanUpdates reads only rows older than 10 minutes, at most one batch", async () => {
  const w = world();
  let seen: { before: string; limit: number } | null = null;
  const original = w.store.pendingPlanUpdates.bind(w.store);
  w.store.pendingPlanUpdates = (before, limit) => {
    seen = { before, limit };
    return original(before, limit);
  };
  await sendPlanUpdates(w.digest());
  assertEquals(seen, { before: "2026-11-27T09:50:00.000Z", limit: 500 });
});
