import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ApnsMessage, type ApnsTarget, buildApnsPayload } from "../_shared/apns.ts";
import type { FlagsRpcClient } from "../_shared/flags.ts";
import { addDays, copy, localDay, type NotificationPrefs } from "../_shared/notify.ts";
import { defaultPrefs, FakeNotifyStore } from "../_shared/notify_testing.ts";
import { handleEveningSummary, type HandlerDeps } from "./handler.ts";
import {
  isSummaryHour,
  NO_LINK,
  SUMMARY_KIND,
  type SummaryCounts,
  type SummaryDeps,
  type SummaryStore,
} from "./summary.ts";

// C7.6 AC1 to AC4 and AC7 through the cron entry point. The database is the
// in-memory FakeNotifyStore (M2b's contract) plus the summary reads below; the
// counts themselves are proven on Postgres by supabase/tests/workout_adherence_state.sql.
// APNs is mocked: no request leaves the test.

const SECRET = "test-secret-value";
const DANA = "aaaaaaaa-0000-4000-8000-00000000000a";
const RON = "cccccccc-0000-4000-8000-00000000000c";
const TOKEN: ApnsTarget = { token: "ab".repeat(32), environment: "production" };
const NAMES = ["Yoni", "Maya", "Roi", "Noa"];
const HEALTH_WORDS = /pain|injur|hurt|knee|shin|ache|sore|heart|rpe|effort/i;

/** One athlete of a coach, as coach_evening_summary_counts sees them. */
interface FakeAthlete {
  coach: string;
  name: string;
  /** Active, v2 and sharing-allowed (AC7). Revoked, not-v2 or not-acked: false. */
  eligible: boolean;
  missed: boolean;
  openFlags: number;
  changed: boolean;
}

class FakeSummaryStore extends FakeNotifyStore implements SummaryStore {
  athletes: FakeAthlete[] = [];
  countCalls: { coach: string; day: string; timeZone: string }[] = [];

  summaryRecipients(): Promise<NotificationPrefs[]> {
    const coaches = new Set(this.athletes.map((a) => a.coach));
    return Promise.resolve(
      [...this.prefsRows.values()].filter((p) => coaches.has(p.user_id) && p.coach_evening_summary).map((p) => ({
        ...p,
      })),
    );
  }

  summaryCounts(coach: string, day: string, timeZone: string): Promise<SummaryCounts> {
    this.countCalls.push({ coach, day, timeZone });
    const mine = this.athletes.filter((a) => a.coach === coach && a.eligible);
    return Promise.resolve({
      missed: mine.filter((a) => a.missed).length,
      open_flags: mine.reduce((sum, a) => sum + a.openFlags, 0),
      plan_changes: mine.filter((a) => a.changed).length,
    });
  }

  summaryLogged(coach: string, day: string): Promise<boolean> {
    return Promise.resolve(
      this.log.some((g) => g.recipient_id === coach && g.kind === SUMMARY_KIND && g.ref_id === day),
    );
  }

  deferSummary(coach: string, day: string) {
    // deferred_pushes_event_key: one row per (recipient, kind, ref_id).
    if (this.deferred.some((d) => d.recipient_id === coach && d.kind === SUMMARY_KIND && d.ref_id === day)) {
      return Promise.resolve("duplicate" as const);
    }
    this.deferred.push({
      id: crypto.randomUUID(),
      recipient_id: coach,
      kind: SUMMARY_KIND,
      payload: { day },
      created_at: new Date().toISOString(),
      athlete_id: coach,
      coach_id: coach,
      link_id: NO_LINK,
      ref_id: day,
      reason: "quiet",
      deliver_after: null,
    });
    return Promise.resolve("deferred" as const);
  }
}

interface Sent {
  recipient: string;
  message: ApnsMessage;
  payload: string;
}

function world(start: string, zone = "Asia/Jerusalem", prefs: Partial<NotificationPrefs> = {}) {
  let now = new Date(start);
  const store = new FakeSummaryStore(() => now);
  const sent: Sent[] = [];
  const flags = { coach_v2: true, coach_v2_push: true };

  store.prefsRows.set(DANA, defaultPrefs(DANA, zone, prefs));
  store.tokens.set(DANA, [TOKEN]);
  store.athletes = [
    { coach: DANA, name: "Yoni", eligible: true, missed: true, openFlags: 0, changed: true },
    { coach: DANA, name: "Maya", eligible: true, missed: true, openFlags: 1, changed: false },
    { coach: DANA, name: "Roi", eligible: true, missed: false, openFlags: 0, changed: false },
    // AC7: a revoked link, a 1.2.6 athlete and an athlete without the consent ack.
    { coach: DANA, name: "Noa", eligible: false, missed: true, openFlags: 2, changed: true },
  ];

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

  const summary = (): SummaryDeps => ({
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
    summary: summary(),
    log: () => {},
    ...overrides,
  });

  return {
    store,
    sent,
    flags,
    at(iso: string) {
      now = new Date(iso);
    },
    setPrefs(patch: Partial<NotificationPrefs>) {
      store.prefsRows.set(DANA, { ...store.prefsRows.get(DANA)!, ...patch });
    },
    async run(overrides: Partial<HandlerDeps> = {}, secret: string | null = SECRET, init: RequestInit = {}) {
      const headers = new Headers({ "Content-Type": "application/json" });
      if (secret !== null) headers.set("x-coach-notify-secret", secret);
      const res = await handleEveningSummary(
        new Request("http://localhost/coach_evening_summary", { method: "POST", body: "{}", headers, ...init }),
        deps(overrides),
      );
      return { status: res.status, body: await res.json() as Record<string, unknown> };
    },
    summaryLogs() {
      return store.log.filter((g) => g.kind === SUMMARY_KIND);
    },
  };
}

function rs(sent: Sent): Record<string, unknown> {
  return (JSON.parse(sent.payload) as { rs: Record<string, unknown> }).rs;
}

// AC1 ---------------------------------------------------------------------------------

Deno.test("AC1: at 20:00 local the coach gets one push with the three counts and no names", async () => {
  // Jerusalem in November is UTC+2: 18:00Z is 20:00.
  const w = world("2026-11-23T18:00:00Z");
  const res = await w.run();
  assertEquals(res.status, 200);
  assertEquals(w.sent.length, 1);
  const push = w.sent[0];
  assertEquals(push.recipient, DANA);
  assertEquals(push.message.kind, "coachEveningSummary");
  assertEquals(push.message.body, "Today: 2 missed · 1 flag open · 1 changed their plan");
  for (const name of NAMES) assertFalse(push.payload.includes(name), `name ${name} in the push`);
  assertFalse(HEALTH_WORDS.test(push.message.body));
  assertEquals(rs(push).kind, "coachEveningSummary");
  assertEquals(rs(push).day, "2026-11-23");
  assertEquals(w.store.countCalls, [{ coach: DANA, day: "2026-11-23", timeZone: "Asia/Jerusalem" }]);
  const logs = w.summaryLogs();
  assertEquals(logs.length, 1);
  assertEquals(logs[0].ref_id, "2026-11-23");
  assertEquals(logs[0].athlete_id, null);
  assertEquals(logs[0].outcome, "sent");
});

Deno.test("AC1: nothing before 20:00 or after the 20:00 hour", async () => {
  for (const at of ["2026-11-23T17:59:00Z", "2026-11-23T19:00:00Z", "2026-11-23T10:00:00Z"]) {
    const w = world(at);
    await w.run();
    assertEquals(w.sent.length, 0, at);
    assertEquals(w.store.countCalls.length, 0, at);
  }
});

Deno.test("AC1: the 20:00 crossing in several zones, including half-hour zones and DST", async () => {
  const cases: { zone: string; at: string; due: boolean; day?: string }[] = [
    { zone: "Asia/Kolkata", at: "2026-11-23T14:30:00Z", due: true, day: "2026-11-23" }, // 20:00 IST
    { zone: "Asia/Kolkata", at: "2026-11-23T14:00:00Z", due: false }, // 19:30
    { zone: "Asia/Kolkata", at: "2026-11-23T15:00:00Z", due: true, day: "2026-11-23" }, // 20:30, a cron on :00
    { zone: "America/New_York", at: "2026-11-24T01:00:00Z", due: true, day: "2026-11-23" }, // 20:00 EST
    { zone: "Pacific/Auckland", at: "2026-11-23T07:00:00Z", due: true, day: "2026-11-23" }, // 20:00 NZDT
    // New York leaves summer time on 2026-11-01.
    { zone: "America/New_York", at: "2026-11-01T00:00:00Z", due: true, day: "2026-10-31" }, // 20:00 EDT
    { zone: "America/New_York", at: "2026-11-01T01:00:00Z", due: false }, // 21:00 EDT
    { zone: "America/New_York", at: "2026-11-02T00:00:00Z", due: false }, // 19:00 EST
    { zone: "America/New_York", at: "2026-11-02T01:00:00Z", due: true, day: "2026-11-01" }, // 20:00 EST
    // London leaves summer time on 2026-10-25.
    { zone: "Europe/London", at: "2026-10-24T19:00:00Z", due: true, day: "2026-10-24" }, // 20:00 BST
    { zone: "Europe/London", at: "2026-10-25T19:00:00Z", due: false }, // 19:00 GMT
    { zone: "Europe/London", at: "2026-10-25T20:00:00Z", due: true, day: "2026-10-25" }, // 20:00 GMT
    // Jerusalem left summer time on 2026-10-25.
    { zone: "Asia/Jerusalem", at: "2026-10-24T17:00:00Z", due: true, day: "2026-10-24" }, // 20:00 IDT
    { zone: "Asia/Jerusalem", at: "2026-10-25T18:00:00Z", due: true, day: "2026-10-25" }, // 20:00 IST
    // An unknown zone is UTC, like quiet hours.
    { zone: "Not/AZone", at: "2026-11-23T20:00:00Z", due: true, day: "2026-11-23" },
  ];
  for (const c of cases) {
    const w = world(c.at, c.zone);
    await w.run();
    assertEquals(w.sent.length, c.due ? 1 : 0, `${c.zone} at ${c.at}`);
    if (c.due) assertEquals(rs(w.sent[0]).day, c.day, `${c.zone} at ${c.at}`);
  }
});

Deno.test("isSummaryHour covers exactly one hourly run per local day", () => {
  for (const zone of ["Asia/Jerusalem", "Asia/Kolkata", "Asia/Kathmandu", "America/St_Johns", "America/New_York"]) {
    let hits = 0;
    const start = Date.parse("2026-11-10T12:00:00Z");
    for (let h = 0; h < 24 * 3; h++) {
      if (isSummaryHour(new Date(start + h * 3_600_000), zone)) hits += 1;
    }
    assertEquals(hits, 3, zone);
  }
});

// AC2 ---------------------------------------------------------------------------------

Deno.test("AC2: all three counts 0 sends nothing and writes no log row", async () => {
  const w = world("2026-11-23T18:00:00Z");
  w.store.athletes = w.store.athletes.map((a) => ({ ...a, missed: false, openFlags: 0, changed: false }));
  const res = await w.run();
  assertEquals(res.status, 200);
  assertEquals(w.sent.length, 0);
  assertEquals(w.summaryLogs().length, 0);
  assertEquals((res.body.run as Record<string, number>).all_zero, 1);
});

Deno.test("AC2: one count alone is enough", async () => {
  const w = world("2026-11-23T18:00:00Z");
  w.store.athletes = [{ coach: DANA, name: "Yoni", eligible: true, missed: false, openFlags: 0, changed: true }];
  await w.run();
  assertEquals(w.sent[0].message.body, "Today: 0 missed · 0 flags open · 1 changed their plan");
});

// AC3 ---------------------------------------------------------------------------------

Deno.test("AC3: 20:00 inside quiet hours is held, then sent as Yesterday after midnight", async () => {
  const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { quiet_start: "19:00:00", quiet_end: "07:00:00" });
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 1);
  const row = w.store.deferred[0];
  assertEquals(row.kind, "coachEveningSummary");
  assertEquals(row.ref_id, "2026-11-23");
  assertEquals(row.payload, { day: "2026-11-23" });
  assertEquals(w.summaryLogs().length, 0);

  // Still quiet at 06:00 local: kept.
  w.at("2026-11-24T04:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 1);

  // 07:00 local on the 24th: quiet hours are over.
  w.at("2026-11-24T05:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].message.body, "Yesterday: 2 missed · 1 flag open · 1 changed their plan");
  assertEquals(rs(w.sent[0]).day, "2026-11-23");
  assertEquals(w.store.deferred.length, 0);
  assertEquals(w.summaryLogs().map((g) => g.ref_id), ["2026-11-23"]);
  // The counts are for the held day, in the coach's zone.
  assertEquals(w.store.countCalls.at(-1), { coach: DANA, day: "2026-11-23", timeZone: "Asia/Jerusalem" });

  // The next runs send nothing more for that day.
  w.at("2026-11-24T06:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
});

Deno.test("AC3: quiet hours that end before midnight send it the same evening as Today", async () => {
  const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { quiet_start: "19:00:00", quiet_end: "23:00:00" });
  await w.run();
  assertEquals(w.store.deferred.length, 1);
  w.at("2026-11-23T20:00:00Z"); // 22:00, still quiet
  await w.run();
  assertEquals(w.sent.length, 0);
  w.at("2026-11-23T21:00:00Z"); // 23:00
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].message.body, "Today: 2 missed · 1 flag open · 1 changed their plan");
});

Deno.test("AC3: a held summary still unsent at the next 20:00 is dropped for that evening's own", async () => {
  const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { quiet_start: "19:00:00", quiet_end: "07:00:00" });
  await w.run();
  assertEquals(w.store.deferred.length, 1);
  // The coach moves quiet hours to the default before the flush ever ran.
  w.setPrefs({ quiet_start: "21:30:00", quiet_end: "07:00:00" });
  w.at("2026-11-24T18:00:00Z"); // 20:00 on the 24th
  const res = await w.run();
  assertEquals((res.body.flush as Record<string, number>).dropped, 1);
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].message.body, "Today: 2 missed · 1 flag open · 1 changed their plan");
  assertEquals(rs(w.sent[0]).day, "2026-11-24");
  assertEquals(w.store.deferred.length, 0);
});

Deno.test("AC3: a held summary whose counts dropped to 0 is not sent", async () => {
  const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { quiet_start: "19:00:00", quiet_end: "07:00:00" });
  await w.run();
  // Every athlete left overnight.
  w.store.athletes = w.store.athletes.map((a) => ({ ...a, eligible: false }));
  w.at("2026-11-24T05:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 0);
});

// AC4 ---------------------------------------------------------------------------------

Deno.test("AC4: the summary toggle off sends nothing and holds nothing", async () => {
  const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { coach_evening_summary: false });
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 0);
  assertEquals(w.store.countCalls.length, 0);
});

Deno.test("AC4: turning the toggle off drops a held summary", async () => {
  const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { quiet_start: "19:00:00", quiet_end: "07:00:00" });
  await w.run();
  assertEquals(w.store.deferred.length, 1);
  w.setPrefs({ coach_evening_summary: false });
  w.at("2026-11-24T05:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 0);
  assertEquals(w.store.deferred.length, 0);
});

Deno.test("AC4: the cron running twice in the hour sends one", async () => {
  const w = world("2026-11-23T18:00:00Z");
  await w.run();
  w.at("2026-11-23T18:20:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.summaryLogs().length, 1);
});

Deno.test("AC4: a time-zone change that lands on 20:00 again the same day sends nothing more", async () => {
  const w = world("2026-11-23T18:00:00Z"); // Jerusalem 20:00
  await w.run();
  assertEquals(w.sent.length, 1);

  // Flies to London: 20:00 there is 20:00Z, still the 23rd.
  w.setPrefs({ time_zone: "Europe/London" });
  w.at("2026-11-23T20:00:00Z");
  await w.run();
  // Then New York: 20:00 EST is 01:00Z on the 24th, still the 23rd locally.
  w.setPrefs({ time_zone: "America/New_York" });
  w.at("2026-11-24T01:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.summaryLogs().length, 1);

  // Inside quiet hours there, it is not held again either.
  w.setPrefs({ time_zone: "America/Chicago", quiet_start: "19:00:00", quiet_end: "07:00:00" });
  w.at("2026-11-24T02:00:00Z"); // 20:00 CST on the 23rd
  await w.run();
  assertEquals(w.store.deferred.length, 0);
  assertEquals(w.sent.length, 1);
});

Deno.test("AC4: a held summary and a same-day send after a quiet-hours change still make one push", async () => {
  const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { quiet_start: "19:00:00", quiet_end: "07:00:00" });
  await w.run();
  assertEquals(w.store.deferred.length, 1);
  // Quiet hours turned off in the same hour, and the cron runs again.
  w.setPrefs({ quiet_start: "23:00:00", quiet_end: "06:00:00" });
  w.at("2026-11-23T18:30:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.store.deferred.length, 0);
  w.at("2026-11-24T05:00:00Z");
  await w.run();
  assertEquals(w.sent.length, 1);
});

// AC7 ---------------------------------------------------------------------------------

Deno.test("AC7: revoked, not-v2 and not-acked athletes add nothing", async () => {
  const w = world("2026-11-23T18:00:00Z");
  // Only Noa (not eligible) has anything to report.
  w.store.athletes = [
    { coach: DANA, name: "Roi", eligible: true, missed: false, openFlags: 0, changed: false },
    { coach: DANA, name: "Noa", eligible: false, missed: true, openFlags: 2, changed: true },
  ];
  await w.run();
  assertEquals(w.sent.length, 0);
});

Deno.test("AC7: the kill switch sends nothing, holds nothing and keeps held rows", async () => {
  for (const flag of ["coach_v2", "coach_v2_push"] as const) {
    const w = world("2026-11-23T18:00:00Z", "Asia/Jerusalem", { quiet_start: "19:00:00", quiet_end: "07:00:00" });
    await w.run();
    assertEquals(w.store.deferred.length, 1);
    w.flags[flag] = false;
    w.at("2026-11-24T05:00:00Z");
    const res = await w.run();
    assertEquals(res.status, 200, flag);
    assertEquals(res.body.reason, "skipped_kill_switch", flag);
    assertEquals(w.sent.length, 0, flag);
    assertEquals(w.store.deferred.length, 1, flag);

    // A fresh evening with the switch off: nothing at all.
    const fresh = world("2026-11-23T18:00:00Z");
    fresh.flags[flag] = false;
    await fresh.run();
    assertEquals(fresh.sent.length, 0, flag);
    assertEquals(fresh.store.countCalls.length, 0, flag);
    assertEquals(fresh.summaryLogs().length, 0, flag);
  }
});

// Other coaches, devices, auth ---------------------------------------------------------------

Deno.test("each coach is counted alone; a coach with no device gets a no_device log row", async () => {
  const w = world("2026-11-23T18:00:00Z");
  w.store.prefsRows.set(RON, defaultPrefs(RON, "Asia/Jerusalem"));
  w.store.athletes.push({ coach: RON, name: "Tal", eligible: true, missed: true, openFlags: 0, changed: false });
  await w.run();
  assertEquals(w.sent.length, 1);
  assertEquals(w.sent[0].recipient, DANA);
  const ron = w.summaryLogs().find((g) => g.recipient_id === RON);
  assertEquals(ron?.outcome, "no_device");
});

Deno.test("only the cron's secret is accepted", async () => {
  const w = world("2026-11-23T18:00:00Z");
  assertEquals((await w.run({}, null)).status, 401);
  assertEquals((await w.run({}, "wrong")).status, 401);
  assertEquals((await w.run({ secret: null })).status, 500);
  assertEquals((await w.run({}, SECRET, { method: "GET", body: undefined })).status, 405);
  assertEquals((await w.run({}, SECRET, { body: "[1]" })).status, 400);
  assertEquals((await w.run({ summary: null })).status, 503);
  assertEquals(w.sent.length, 0);
  assertEquals((await w.run()).status, 200);
  assertEquals(w.sent.length, 1);
});

// Copy and dates ------------------------------------------------------------------------------

Deno.test("copy: counts only, singular flag, Yesterday prefix", () => {
  assertEquals(copy.eveningSummary(3, 2, 1, "today"), "Today: 3 missed · 2 flags open · 1 changed their plan");
  assertEquals(copy.eveningSummary(0, 1, 0, "today"), "Today: 0 missed · 1 flag open · 0 changed their plan");
  assertEquals(
    copy.eveningSummary(1, 0, 4, "yesterday"),
    "Yesterday: 1 missed · 0 flags open · 4 changed their plan",
  );
  assert(!/[⁨⁩]/.test(copy.eveningSummary(1, 1, 1, "today")), "no names, so nothing to isolate");
});

Deno.test("localDay and addDays", () => {
  assertEquals(localDay(new Date("2026-11-23T22:30:00Z"), "Asia/Jerusalem"), "2026-11-24");
  assertEquals(localDay(new Date("2026-11-23T22:30:00Z"), "America/New_York"), "2026-11-23");
  assertEquals(localDay(new Date("2026-11-23T22:30:00Z"), "Not/AZone"), "2026-11-23");
  assertEquals(addDays("2026-11-30", 1), "2026-12-01");
  assertEquals(addDays("2026-12-31", 1), "2027-01-01");
  assertEquals(addDays("2026-03-01", -1), "2026-02-28");
});
