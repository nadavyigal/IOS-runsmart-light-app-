import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ApnsMessage, type ApnsTarget, buildApnsPayload } from "../_shared/apns.ts";
import type { FlagsRpcClient } from "../_shared/flags.ts";
import type { NotifyDeps } from "../_shared/notify.ts";
import { defaultPrefs, FakeNotifyStore } from "../_shared/notify_testing.ts";
import {
  type FeedbackRow,
  type FlagRow,
  handleCoachNotify,
  type HandlerDeps,
  type ReplyRow,
  type RunRow,
  type SourceReader,
} from "./handler.ts";

// C7.5 AC1 to AC13 through the webhook and flush entry point. The database is the
// in-memory FakeNotifyStore (same contract as M2b's functions, proven on Postgres by
// supabase/tests/notification_log_and_deferred.sql). APNs is mocked: no request
// leaves the test.

const FSI = "⁨";
const PDI = "⁩";
const SECRET = "test-secret-value";
const COACH = "aaaaaaaa-0000-4000-8000-00000000000a";
const COACH_2 = "cccccccc-0000-4000-8000-00000000000c";
const ATHLETES = ["b1", "b2", "b3", "b4", "b5", "b6"].map((_, i) => `bbbbbbbb-0000-4000-8000-00000000000${i + 1}`);
const [YONI, MAYA, ROI, NOA, TAL] = ATHLETES;
const NAMES: Record<string, string> = { [YONI]: "Yoni", [MAYA]: "Maya", [ROI]: "Roi", [NOA]: "Noa", [TAL]: "Tal" };
const TOKEN: ApnsTarget = { token: "ab".repeat(32), environment: "production" };
const ID_VALUE = /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\d{1,19}|\d{4}-\d{2}-\d{2})$/;
const HEALTH_WORDS = /pain|injur|hurt|knee|shin|ache|sore|heart|rpe|effort/i;

function link(athlete: string): string {
  return `11111111${athlete.slice(8)}`;
}

class FakeSource implements SourceReader {
  runs = new Map<string, RunRow>();
  flags = new Map<string, FlagRow>();
  notes = new Map<string, FeedbackRow>();
  replies = new Map<string, ReplyRow>();
  run(id: string) {
    return Promise.resolve(this.runs.get(id) ?? null);
  }
  flag(id: string) {
    return Promise.resolve(this.flags.get(id) ?? null);
  }
  feedback(id: string) {
    return Promise.resolve(this.notes.get(id) ?? null);
  }
  reply(id: string) {
    return Promise.resolve(this.replies.get(id) ?? null);
  }
}

interface World {
  store: FakeNotifyStore;
  source: FakeSource;
  sent: { recipient: string; message: ApnsMessage; payload: string }[];
  flags: { coach_v2: boolean; coach_v2_push: boolean; unavailable: boolean };
  setNow(iso: string): void;
  now(): Date;
  deps(overrides?: Partial<HandlerDeps>): HandlerDeps;
  call(
    body: unknown,
    overrides?: Partial<HandlerDeps>,
    secret?: string | null,
  ): Promise<{ status: number; body: Record<string, unknown> }>;
}

// Jerusalem in November is UTC+2. 12:00 UTC = 14:00 local, outside quiet hours.
function world(start = "2026-11-23T12:00:00Z"): World {
  let now = new Date(start);
  const store = new FakeNotifyStore(() => now);
  const source = new FakeSource();
  const sent: World["sent"] = [];
  const flags = { coach_v2: true, coach_v2_push: true, unavailable: false };

  for (const athlete of ATHLETES) {
    store.links.set(athlete, {
      link_id: link(athlete),
      coach_id: COACH,
      link_v2: true,
      sharing_allowed: true,
      coach_name: "Dana",
      athlete_name: NAMES[athlete] ?? "Athlete",
    });
    store.prefsRows.set(athlete, defaultPrefs(athlete, "Asia/Jerusalem"));
    store.tokens.set(athlete, [TOKEN]);
  }
  store.prefsRows.set(COACH, defaultPrefs(COACH, "Asia/Jerusalem"));
  store.tokens.set(COACH, [TOKEN]);

  const flagsClient: FlagsRpcClient = {
    rpc: () =>
      Promise.resolve(
        flags.unavailable ? { data: null, error: { message: "down" } } : {
          data: [
            { key: "coach_v2", enabled: flags.coach_v2 },
            { key: "coach_v2_push", enabled: flags.coach_v2_push },
            { key: "coach_v2_ai", enabled: true },
          ],
          error: null,
        },
      ),
  };

  const tokenOwner = new Map<string, string>();
  const notify = (): NotifyDeps => ({
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
  // liveTokens is called right before send: remember whose tokens they were.
  let lastRecipient = "";
  const originalLive = store.liveTokens.bind(store);
  store.liveTokens = (userId: string) => {
    lastRecipient = userId;
    tokenOwner.set(userId, userId);
    return originalLive(userId);
  };

  const self: World = {
    store,
    source,
    sent,
    flags,
    setNow: (iso) => (now = new Date(iso)),
    now: () => now,
    deps: (overrides = {}) => ({
      secret: SECRET,
      flags: flagsClient,
      notify: notify(),
      source,
      log: () => {},
      ...overrides,
    }),
    async call(body, overrides, secret = SECRET) {
      const headers: Record<string, string> = { "content-type": "application/json" };
      if (secret !== null) headers["x-coach-notify-secret"] = secret;
      const response = await handleCoachNotify(
        new Request("http://localhost/coach_notify", { method: "POST", headers, body: JSON.stringify(body) }),
        self.deps(overrides),
      );
      return { status: response.status, body: await response.json() };
    },
  };
  return self;
}

let runSeq = 1000;
function addRun(w: World, athlete: string, opts: { distance?: number | null; completedAgoMs?: number } = {}): string {
  const id = String(++runSeq);
  w.source.runs.set(id, {
    id: Number(id),
    auth_user_id: athlete,
    distance: opts.distance === undefined ? 5.2 : opts.distance,
    completed_at: new Date(w.now().getTime() - (opts.completedAgoMs ?? 5 * 60 * 1000)).toISOString(),
  });
  return id;
}

let uuidSeq = 0;
function uuid(prefix: string): string {
  uuidSeq += 1;
  return `${prefix}-0000-4000-8000-${String(uuidSeq).padStart(12, "0")}`;
}

function addFlag(w: World, athlete: string): string {
  const id = uuid("f1f1f1f1");
  w.source.flags.set(id, {
    id,
    athlete_id: athlete,
    link_id: link(athlete),
    run_id: 1,
    created_at: w.now().toISOString(),
  });
  return id;
}

function addNote(w: World, athlete: string, kind = "note", coach = COACH): string {
  const id = uuid("d1d1d1d1");
  w.source.notes.set(id, { id, coach_id: coach, athlete_id: athlete, kind, run_id: null, week_start: "2026-11-23" });
  return id;
}

function addReply(w: World, athlete: string): string {
  const id = uuid("e1e1e1e1");
  const feedback = addNote(w, athlete);
  w.source.replies.set(id, {
    id,
    feedback_id: feedback,
    author_id: athlete,
    link_id: link(athlete),
    feedback: { coach_id: COACH, athlete_id: athlete },
  });
  return id;
}

const insert = (table: string, id: string | number) => ({
  type: "INSERT",
  table,
  schema: "public",
  record: { id },
  old_record: null,
});
const flush = { action: "flush" };

function assertSafe(w: World) {
  for (const { message, payload } of w.sent) {
    assertFalse(HEALTH_WORDS.test(message.body), `health word in "${message.body}"`);
    const rs = JSON.parse(payload).rs as Record<string, unknown>;
    for (const [key, value] of Object.entries(rs)) {
      if (key === "v" || key === "kind") continue;
      assert(typeof value === "string" && ID_VALUE.test(value), `custom data ${key} is not an id`);
    }
  }
}

// Entry checks -----------------------------------------------------------------------------

Deno.test("a call without the secret, or with a wrong one, is refused and touches nothing", async () => {
  const w = world();
  const run = addRun(w, YONI);
  assertEquals((await w.call(insert("runs", run), {}, null)).status, 401);
  assertEquals((await w.call(insert("runs", run), {}, "nope")).status, 401);
  assertEquals((await w.call(insert("runs", run), { secret: null })).status, 500);
  assertEquals(w.sent.length + w.store.log.length, 0);
});

Deno.test("APNs secrets missing: 503 and nothing is held or logged", async () => {
  const w = world();
  const res = await w.call(insert("runs", addRun(w, YONI)), { notify: null });
  assertEquals(res.status, 503);
  assertEquals(w.store.log.length + w.store.deferred.length, 0);
});

Deno.test("unsupported events are refused", async () => {
  const w = world();
  assertEquals((await w.call({ type: "UPDATE", table: "runs", record: { id: 1 } })).status, 400);
  assertEquals((await w.call({ type: "INSERT", table: "profiles", record: { id: 1 } })).status, 400);
  assertEquals((await w.call({ type: "INSERT", table: "runs", record: {} })).status, 400);
});

// AC1, AC2: run finished, once per run, dedupe -------------------------------------------------

Deno.test("AC1: a run insert sends the coach one push, once per runs.id; the log row records it", async () => {
  const w = world();
  const run = addRun(w, YONI);
  const res = await w.call(insert("runs", run));
  assertEquals(res.body.result, "sent");
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].recipient, COACH);
  assertEquals(w.sent[0].message.kind, "coachRunFinished");
  assertEquals(w.sent[0].message.body, `${FSI}Yoni${PDI} finished a 5.2 km run`);
  assertEquals(w.sent[0].message.target, { athlete_id: YONI, run_id: run, day: "2026-11-23" });
  // AC12
  assertEquals(w.store.log.map((g) => [g.recipient_id, g.athlete_id, g.kind, g.ref_id, g.outcome]), [
    [COACH, YONI, "coachRunFinished", run, "sent"],
  ]);

  // A retried webhook for the same run.
  assertEquals((await w.call(insert("runs", run))).body.result, "duplicate");
  assertEquals(w.sent.length, 1);
  assertSafe(w);
});

Deno.test("AC1: an import older than 24 h sends nothing", async () => {
  const w = world();
  const res = await w.call(insert("runs", addRun(w, YONI, { completedAgoMs: 25 * 60 * 60 * 1000 })));
  assertEquals(res.body.result, "old_import");
  assertEquals(w.sent.length + w.store.log.length, 0);
  const recent = await w.call(insert("runs", addRun(w, YONI, { completedAgoMs: 23 * 60 * 60 * 1000 })));
  assertEquals(recent.body.result, "sent");
});

Deno.test("AC1: a run with no distance says 'finished a run'", async () => {
  const w = world();
  await w.call(insert("runs", addRun(w, YONI, { distance: null })));
  assertEquals(w.sent[0].message.body, `${FSI}Yoni${PDI} finished a run`);
});

Deno.test("AC2 dedupe: a second run within 30 minutes is not sent; after 30 minutes it is", async () => {
  const w = world();
  await w.call(insert("runs", addRun(w, YONI)));
  w.setNow("2026-11-23T12:20:00Z");
  // A Garmin copy of the same run, or a second short run.
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "deduped");
  assertEquals(w.sent.length, 1);
  // Another athlete is not deduped.
  assertEquals((await w.call(insert("runs", addRun(w, MAYA)))).body.result, "sent");
  w.setNow("2026-11-23T12:31:00Z");
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "sent");
  assertEquals(w.sent.length, 3);
});

// AC3: burst collapse ---------------------------------------------------------------------------

Deno.test("AC3 collapse: the 4th and later run pushes in 10 minutes become one at the end of the window", async () => {
  const w = world();
  for (const [athlete, minute] of [[YONI, "00"], [MAYA, "02"], [ROI, "04"]] as const) {
    w.setNow(`2026-11-23T12:${minute}:00Z`);
    assertEquals((await w.call(insert("runs", addRun(w, athlete)))).body.result, "sent");
  }
  w.setNow("2026-11-23T12:05:00Z");
  assertEquals((await w.call(insert("runs", addRun(w, NOA)))).body.result, "deferred_burst");
  w.setNow("2026-11-23T12:07:00Z");
  assertEquals((await w.call(insert("runs", addRun(w, TAL)))).body.result, "deferred_burst");
  // Noa again inside 30 minutes: deduped, not counted twice.
  assertEquals((await w.call(insert("runs", addRun(w, NOA)))).body.result, "deduped");
  assertEquals(w.sent.length, 3);

  // Before the window ends (12:00 + 10 min) the flush keeps them.
  w.setNow("2026-11-23T12:09:00Z");
  await w.call(flush);
  assertEquals(w.sent.length, 3);
  assertEquals(w.store.deferred.length, 2);

  w.setNow("2026-11-23T12:10:30Z");
  await w.call(flush);
  assertEquals(w.sent.length, 4);
  assertEquals(w.sent[3].message.kind, "coachDigest");
  assertEquals(w.sent[3].message.body, "2 more athletes finished runs");
  assertEquals(w.store.deferred.length, 0);
  const digest = w.store.log.find((g) => g.kind === "coachDigest")!;
  assertEquals([digest.item_count, digest.outcome, digest.athlete_id], [2, "sent", null]);

  // A second flush finds nothing: no double push.
  await w.call(flush);
  assertEquals(w.sent.length, 4);
  assertSafe(w);
});

// AC4, AC5, AC6: flags, replies, notes -------------------------------------------------------------

Deno.test("AC4: a flag sends 'flagged something after a run', with no health words", async () => {
  const w = world();
  const flag = addFlag(w, YONI);
  assertEquals((await w.call(insert("athlete_run_flags", flag))).body.result, "sent");
  assertEquals(w.sent[0].message.kind, "coachPainFlag");
  assertEquals(w.sent[0].message.body, `${FSI}Yoni${PDI} flagged something after a run`);
  assertEquals(w.sent[0].message.target?.flag_id, flag);
  assertSafe(w);
});

Deno.test("AC4: a flag needs the athlete's v2 consent ack; a run does not", async () => {
  const w = world();
  w.store.links.set(YONI, { ...w.store.links.get(YONI)!, sharing_allowed: false });
  assertEquals((await w.call(insert("athlete_run_flags", addFlag(w, YONI)))).body.result, "not_v2");
  assertEquals((await w.call(insert("coach_feedback_replies", addReply(w, YONI)))).body.result, "not_v2");
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "sent");
});

Deno.test("AC5: a reply sends the coach 'replied to your note'", async () => {
  const w = world();
  assertEquals((await w.call(insert("coach_feedback_replies", addReply(w, YONI)))).body.result, "sent");
  assertEquals(w.sent[0].recipient, COACH);
  assertEquals(w.sent[0].message.kind, "athleteCoachReply");
  assertEquals(w.sent[0].message.body, `${FSI}Yoni${PDI} replied to your note`);
});

Deno.test("AC6: a note sends the athlete '{Coach} left you a note'; a welcome note sends nothing", async () => {
  const w = world();
  const note = addNote(w, YONI);
  assertEquals((await w.call(insert("coach_feedback", note))).body.result, "sent");
  assertEquals(w.sent[0].recipient, YONI);
  assertEquals(w.sent[0].message.body, `${FSI}Dana${PDI} left you a note`);
  assertEquals(w.sent[0].message.target, { coach_id: COACH, feedback_id: note });

  assertEquals((await w.call(insert("coach_feedback", addNote(w, YONI, "welcome")))).body.result, "not_a_note");
  assertEquals(w.sent.length, 1);
});

Deno.test("a note from a coach who is not the athlete's active coach sends nothing", async () => {
  const w = world();
  assertEquals((await w.call(insert("coach_feedback", addNote(w, YONI, "note", COACH_2)))).body.result, "link_changed");
  assertEquals(w.sent.length, 0);
});

Deno.test("mixed version: a pair that is not v2 gets no push", async () => {
  const w = world();
  w.store.links.set(YONI, { ...w.store.links.get(YONI)!, link_v2: false, sharing_allowed: false });
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "not_v2");
  assertEquals((await w.call(insert("coach_feedback", addNote(w, YONI)))).body.result, "not_v2");
  assertEquals(w.sent.length + w.store.log.length, 0);
});

Deno.test("a deleted source row sends nothing (a forged webhook body cannot invent one)", async () => {
  const w = world();
  assertEquals((await w.call(insert("runs", 999999))).body.result, "source_missing");
  assertEquals(
    (await w.call(insert("athlete_run_flags", "f0000000-0000-4000-8000-000000000000"))).body.result,
    "source_missing",
  );
  assertEquals(w.sent.length, 0);
});

// AC7: quiet hours ----------------------------------------------------------------------------------

Deno.test("AC7: inside quiet hours nothing is sent; at quiet end one collapsed push goes out, pain included", async () => {
  const w = world("2026-11-23T21:30:00Z"); // 23:30 in Jerusalem
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "deferred_quiet");
  assertEquals((await w.call(insert("runs", addRun(w, MAYA)))).body.result, "deferred_quiet");
  // Pain does not break quiet hours (D6).
  assertEquals((await w.call(insert("athlete_run_flags", addFlag(w, ROI)))).body.result, "deferred_quiet");
  assertEquals((await w.call(insert("coach_feedback_replies", addReply(w, NOA)))).body.result, "deferred_quiet");
  // The same run again in quiet hours: deduped, counted once.
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "deduped");
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.log.length, 0);

  w.setNow("2026-11-24T01:00:00Z"); // 03:00 local
  await w.call(flush);
  assertEquals(w.sent.length, 0);

  w.setNow("2026-11-24T05:01:00Z"); // 07:01 local
  await w.call(flush);
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].recipient, COACH);
  assertEquals(w.sent[0].message.kind, "coachDigest");
  assertEquals(w.sent[0].message.body, "While you were away: 2 runs · 1 flag · 1 reply");
  assertEquals(w.store.deferred.length, 0);
  assertEquals(w.store.log.map((g) => [g.kind, g.item_count, g.outcome]), [["coachDigest", 4, "sent"]]);
  assertSafe(w);
});

Deno.test("AC7: an athlete's held notes become '{Coach} left you {n} notes'; one note stays a note", async () => {
  const w = world("2026-11-23T21:30:00Z");
  await w.call(insert("coach_feedback", addNote(w, YONI)));
  await w.call(insert("coach_feedback", addNote(w, YONI)));
  const single = addNote(w, MAYA);
  await w.call(insert("coach_feedback", single));
  w.setNow("2026-11-24T05:05:00Z");
  await w.call(flush);
  const byRecipient = Object.fromEntries(w.sent.map((s) => [s.recipient, s.message]));
  assertEquals(byRecipient[YONI].kind, "athleteNotesDigest");
  assertEquals(byRecipient[YONI].body, `${FSI}Dana${PDI} left you 2 notes`);
  assertEquals(byRecipient[YONI].target, { coach_id: COACH });
  assertEquals(byRecipient[MAYA].kind, "athleteCoachNote");
  assertEquals(byRecipient[MAYA].body, `${FSI}Dana${PDI} left you a note`);
  assertEquals(byRecipient[MAYA].target?.feedback_id, single);
});

// AC8: prefs off -------------------------------------------------------------------------------------

Deno.test("AC8: with a kind's toggle off nothing is sent and nothing is held", async () => {
  const w = world();
  w.store.prefsRows.set(
    COACH,
    defaultPrefs(COACH, "Asia/Jerusalem", { coach_run_finished: false, coach_pain_flag: false }),
  );
  w.store.prefsRows.set(YONI, defaultPrefs(YONI, "Asia/Jerusalem", { athlete_coach_note: false }));
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "pref_off");
  assertEquals((await w.call(insert("athlete_run_flags", addFlag(w, YONI)))).body.result, "pref_off");
  assertEquals((await w.call(insert("coach_feedback", addNote(w, YONI)))).body.result, "pref_off");
  assertEquals(w.sent.length + w.store.log.length + w.store.deferred.length, 0);
});

Deno.test("AC8: a toggle turned off during quiet hours drops those held rows", async () => {
  const w = world("2026-11-23T21:30:00Z");
  await w.call(insert("runs", addRun(w, YONI)));
  await w.call(insert("athlete_run_flags", addFlag(w, MAYA)));
  w.store.prefsRows.set(COACH, defaultPrefs(COACH, "Asia/Jerusalem", { coach_run_finished: false }));
  w.setNow("2026-11-24T05:05:00Z");
  await w.call(flush);
  assertEquals(w.sent.map((s) => s.message.body), ["While you were away: 1 flag"]);
  assertEquals(w.store.deferred.length, 0);
});

// AC9: link revoked or no longer v2 at send time ----------------------------------------------------------

Deno.test("AC9: link revoked before the event is handled: nothing is sent", async () => {
  const w = world();
  const run = addRun(w, YONI);
  w.store.links.delete(YONI);
  assertEquals((await w.call(insert("runs", run))).body.result, "no_link");
  assertEquals(w.sent.length + w.store.log.length, 0);
});

Deno.test("AC9: link revoked while held: the rows for that link are dropped at send time", async () => {
  const w = world("2026-11-23T21:30:00Z");
  await w.call(insert("runs", addRun(w, YONI)));
  await w.call(insert("athlete_run_flags", addFlag(w, YONI)));
  await w.call(insert("runs", addRun(w, MAYA)));
  await w.call(insert("coach_feedback", addNote(w, YONI)));
  w.store.links.delete(YONI); // Yoni left
  w.setNow("2026-11-24T05:05:00Z");
  await w.call(flush);
  assertEquals(w.sent.map((s) => [s.recipient, s.message.body]), [[COACH, "While you were away: 1 run"]]);
  assertEquals(w.store.deferred.length, 0, "dropped rows are deleted, not kept");
});

Deno.test("AC9: a rejoin (new link) does not deliver events from the old link", async () => {
  const w = world("2026-11-23T21:30:00Z");
  await w.call(insert("runs", addRun(w, YONI)));
  w.store.links.set(YONI, { ...w.store.links.get(YONI)!, link_id: "22222222-0000-4000-8000-000000000001" });
  w.setNow("2026-11-24T05:05:00Z");
  await w.call(flush);
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 0);
});

Deno.test("AC9: link_is_v2 turned false while held: dropped, nothing sent", async () => {
  const w = world("2026-11-23T21:30:00Z");
  await w.call(insert("runs", addRun(w, YONI)));
  w.store.links.set(YONI, { ...w.store.links.get(YONI)!, link_v2: false });
  w.setNow("2026-11-24T05:05:00Z");
  await w.call(flush);
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 0);
});

// AC10: kill switch ------------------------------------------------------------------------------------------

Deno.test("AC10: coach_v2_push off: nothing is sent and held rows are kept", async () => {
  const w = world("2026-11-23T21:30:00Z");
  await w.call(insert("runs", addRun(w, YONI)));
  assertEquals(w.store.deferred.length, 1);

  w.flags.coach_v2_push = false;
  w.setNow("2026-11-24T05:05:00Z");
  const res = await w.call(flush);
  assertEquals(res.status, 200);
  assertEquals(res.body.reason, "skipped_kill_switch");
  const event = await w.call(insert("runs", addRun(w, MAYA)));
  assertEquals(event.body.reason, "skipped_kill_switch");
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 1, "held row kept");
  assertEquals(w.store.log.length, 0);

  // coach_v2 off (the wider switch) also keeps the rows: link_is_v2 is never asked.
  w.flags.coach_v2_push = true;
  w.flags.coach_v2 = false;
  await w.call(flush);
  assertEquals(w.store.deferred.length, 1);

  // Back on: the held push goes out.
  w.flags.coach_v2 = true;
  await w.call(flush);
  assertEquals(w.sent.length, 1);
  assertEquals(w.store.deferred.length, 0);
});

Deno.test("flags unreadable: 503, nothing sent or touched", async () => {
  const w = world();
  w.flags.unavailable = true;
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).status, 503);
  assertEquals(w.sent.length + w.store.log.length, 0);
});

// AC12: log and outcomes -------------------------------------------------------------------------------------

Deno.test("AC12: a recipient with no device is logged as no_device", async () => {
  const w = world();
  w.store.tokens.set(COACH, []);
  assertEquals((await w.call(insert("runs", addRun(w, YONI)))).body.result, "no_device");
  assertEquals(w.store.log[0].outcome, "no_device");
});

Deno.test("a coach who is also an athlete gets the coach digest and the note digest separately", async () => {
  const w = world("2026-11-23T21:30:00Z");
  // Coach A is coached by C2.
  w.store.links.set(COACH, {
    link_id: link(COACH),
    coach_id: COACH_2,
    link_v2: true,
    sharing_allowed: true,
    coach_name: "Ron",
    athlete_name: "Dana",
  });
  await w.call(insert("runs", addRun(w, YONI)));
  await w.call(insert("coach_feedback", addNote(w, COACH, "note", COACH_2)));
  w.setNow("2026-11-24T05:05:00Z");
  await w.call(flush);
  assertEquals(
    w.sent.map((s) => s.message.body).sort(),
    [
      "While you were away: 1 run",
      `${FSI}Ron${PDI} left you a note`,
    ].sort(),
  );
});

Deno.test("the flush leaves held rows of other senders' kinds alone", async () => {
  const w = world("2026-11-23T21:30:00Z");
  await w.call(insert("runs", addRun(w, YONI)));
  // A C7.6 evening summary held for the same coach.
  w.store.deferred.push({
    id: "99999999-0000-4000-8000-000000000099",
    recipient_id: COACH,
    kind: "coachEveningSummary" as never,
    payload: {},
    created_at: w.now().toISOString(),
    athlete_id: YONI,
    coach_id: COACH,
    link_id: link(YONI),
    ref_id: "2026-11-23",
    reason: "quiet",
    deliver_after: null,
  });
  w.setNow("2026-11-24T05:05:00Z");
  await w.call(flush);
  assertEquals(w.sent.map((s) => s.message.body), ["While you were away: 1 run"]);
  assertEquals(w.store.deferred.map((d) => d.kind), ["coachEveningSummary"]);
});
