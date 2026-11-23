import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type ApnsMessage, type ApnsTarget, buildApnsPayload } from "./apns.ts";
import {
  copy,
  flushDeferred,
  formatKm,
  isQuietTime,
  localMinutes,
  type NotifyDeps,
  notifyOne,
  RUN_DEDUPE_SECONDS,
} from "./notify.ts";
import { defaultPrefs, FakeNotifyStore } from "./notify_testing.ts";

// C7.5 AC13 (unit level): quiet hours across midnight, a time-zone change, DST,
// prefs off, and the copy rules. APNs is mocked: no request leaves the test.

const FSI = "⁨";
const PDI = "⁩";
const COACH = "aaaaaaaa-0000-4000-8000-00000000000a";
const ATHLETE = "bbbbbbbb-0000-4000-8000-00000000000b";
const LINK = "11111111-0000-4000-8000-00000000000b";
const TOKEN: ApnsTarget = { token: "ab".repeat(32), environment: "production" };
const HEALTH_WORDS = /pain|injur|hurt|knee|shin|ache|sore|heart|hr\b|rpe|effort|sick|ill\b/i;

function at(iso: string): Date {
  return new Date(iso);
}

function harness(start: string) {
  let now = at(start);
  const store = new FakeNotifyStore(() => now);
  const sent: { targets: readonly ApnsTarget[]; message: ApnsMessage; payload: string }[] = [];
  store.links.set(ATHLETE, {
    link_id: LINK,
    coach_id: COACH,
    link_v2: true,
    sharing_allowed: true,
    coach_name: "Dana",
    athlete_name: "Yoni",
  });
  store.tokens.set(COACH, [TOKEN]);
  store.tokens.set(ATHLETE, [TOKEN]);
  const deps: NotifyDeps = {
    store,
    apns: { keyId: "K", teamId: "T", privateKey: "unused", bundleId: "com.runsmart.lite" },
    disableToken: () => Promise.resolve(),
    now: () => now,
    log: () => {},
    send: (targets, message) => {
      // The real payload builder: refuses free text in the custom data.
      sent.push({ targets, message, payload: buildApnsPayload(message) });
      return Promise.resolve(targets.map(() => ({ status: "sent" as const, apnsId: null })));
    },
  };
  return { store, sent, deps, setNow: (iso: string) => (now = at(iso)) };
}

function runEvent(ref: string, athlete = ATHLETE) {
  return {
    kind: "coachRunFinished" as const,
    recipientId: COACH,
    athleteId: athlete,
    linkId: LINK,
    refId: ref,
    body: copy.runFinished("Yoni", 5),
    target: { athlete_id: athlete, run_id: ref },
  };
}

// Quiet hours ---------------------------------------------------------------------------

Deno.test("quiet hours across midnight: 21:30 to 07:00, start inside, end outside", () => {
  const prefs = defaultPrefs(COACH, "UTC");
  assert(isQuietTime(prefs, at("2026-11-23T21:30:00Z")), "21:30 is quiet");
  assert(isQuietTime(prefs, at("2026-11-23T23:59:00Z")), "23:59 is quiet");
  assert(isQuietTime(prefs, at("2026-11-24T00:00:00Z")), "midnight is quiet");
  assert(isQuietTime(prefs, at("2026-11-24T03:00:00Z")), "03:00 is quiet");
  assert(isQuietTime(prefs, at("2026-11-24T06:59:00Z")), "06:59 is quiet");
  assertFalse(isQuietTime(prefs, at("2026-11-24T07:00:00Z")), "07:00 is not quiet");
  assertFalse(isQuietTime(prefs, at("2026-11-24T12:00:00Z")), "noon is not quiet");
  assertFalse(isQuietTime(prefs, at("2026-11-23T21:29:00Z")), "21:29 is not quiet");
});

Deno.test("quiet hours inside one day (13:00 to 15:00) and an equal start and end", () => {
  const prefs = defaultPrefs(COACH, "UTC", { quiet_start: "13:00", quiet_end: "15:00" });
  assert(isQuietTime(prefs, at("2026-11-23T14:00:00Z")));
  assertFalse(isQuietTime(prefs, at("2026-11-23T15:00:00Z")));
  assertFalse(isQuietTime(prefs, at("2026-11-23T03:00:00Z")));
  assertFalse(
    isQuietTime(defaultPrefs(COACH, "UTC", { quiet_start: "10:00", quiet_end: "10:00" }), at("2026-11-23T10:00:00Z")),
  );
});

Deno.test("quiet hours use the recipient's own zone", () => {
  // 21:00 UTC is 23:00 in Jerusalem (UTC+2 in November) and 16:00 in New York.
  const instant = at("2026-11-23T21:00:00Z");
  assert(isQuietTime(defaultPrefs(COACH, "Asia/Jerusalem"), instant));
  assertFalse(isQuietTime(defaultPrefs(COACH, "America/New_York"), instant));
  assertEquals(localMinutes(instant, "Asia/Jerusalem"), 23 * 60);
});

Deno.test("an unknown zone falls back to UTC instead of throwing", () => {
  assertEquals(localMinutes(at("2026-11-23T05:15:00Z"), "Mars/Olympus"), 5 * 60 + 15);
  assert(isQuietTime(defaultPrefs(COACH, "Mars/Olympus"), at("2026-11-23T05:15:00Z")));
});

Deno.test("DST: New York spring forward and fall back move the quiet end in UTC", () => {
  const prefs = defaultPrefs(COACH, "America/New_York");
  // Sat 7 Mar 2026, EST (UTC-5): 11:30 UTC is 06:30, quiet.
  assert(isQuietTime(prefs, at("2026-03-07T11:30:00Z")));
  // Sun 8 Mar 2026, EDT (UTC-4): the same 11:30 UTC is 07:30, not quiet.
  // A fixed -5 offset would say 06:30 and hold the push for another 30 minutes.
  assertFalse(isQuietTime(prefs, at("2026-03-08T11:30:00Z")));
  // Sat 31 Oct 2026, EDT: 11:30 UTC is 07:30, not quiet.
  assertFalse(isQuietTime(prefs, at("2026-10-31T11:30:00Z")));
  // Sun 1 Nov 2026, EST again: 11:30 UTC is 06:30, quiet.
  assert(isQuietTime(prefs, at("2026-11-01T11:30:00Z")));
});

Deno.test("DST: Jerusalem summer time starts Fri 27 Mar 2026", () => {
  const prefs = defaultPrefs(COACH, "Asia/Jerusalem");
  // 04:30 UTC: 06:30 IST (quiet) on the 26th, 07:30 IDT (not quiet) on the 27th.
  assert(isQuietTime(prefs, at("2026-03-26T04:30:00Z")));
  assertFalse(isQuietTime(prefs, at("2026-03-27T04:30:00Z")));
});

// Prefs off (AC8) ---------------------------------------------------------------------------

Deno.test("prefs off: nothing is sent and nothing is held, also in quiet hours", async () => {
  for (const instant of ["2026-11-23T12:00:00Z", "2026-11-23T23:00:00Z"]) {
    const { store, sent, deps } = harness(instant);
    store.prefsRows.set(COACH, defaultPrefs(COACH, "UTC", { coach_run_finished: false }));
    assertEquals(await notifyOne(runEvent("1"), deps), "pref_off");
    assertEquals(sent.length, 0);
    assertEquals(store.log.length, 0);
    assertEquals(store.deferred.length, 0);
  }
});

Deno.test("no prefs row: nothing is sent or held", async () => {
  const { store, sent, deps } = harness("2026-11-23T12:00:00Z");
  assertEquals(await notifyOne(runEvent("1"), deps), "no_prefs");
  assertEquals(sent.length + store.log.length + store.deferred.length, 0);
});

Deno.test("a reply has no toggle: it still notifies with every coach toggle off", async () => {
  const { store, sent, deps } = harness("2026-11-23T12:00:00Z");
  store.prefsRows.set(
    COACH,
    defaultPrefs(COACH, "UTC", { coach_run_finished: false, coach_pain_flag: false, coach_evening_summary: false }),
  );
  const result = await notifyOne({
    kind: "athleteCoachReply",
    recipientId: COACH,
    athleteId: ATHLETE,
    linkId: LINK,
    refId: "cccccccc-0000-4000-8000-000000000001",
    body: copy.replied("Yoni"),
    target: { athlete_id: ATHLETE, feedback_id: "dddddddd-0000-4000-8000-000000000001" },
  }, deps);
  assertEquals(result, "sent");
  assertEquals(sent.length, 1);
});

// Time-zone change and DST at flush time ------------------------------------------------------

Deno.test("time-zone change: held pushes wait for quiet end in the NEW zone", async () => {
  // 23:00 in Jerusalem: held.
  const { store, sent, deps, setNow } = harness("2026-11-23T21:00:00Z");
  store.prefsRows.set(COACH, defaultPrefs(COACH, "Asia/Jerusalem"));
  assertEquals(await notifyOne(runEvent("1"), deps), "deferred_quiet");

  // The coach flies to New York and the app updates the zone.
  store.prefsRows.set(COACH, defaultPrefs(COACH, "America/New_York"));
  // 05:30 UTC: 07:30 in Jerusalem (would be out of quiet), 00:30 in New York (quiet).
  setNow("2026-11-24T05:30:00Z");
  await flushDeferred(deps);
  assertEquals(sent.length, 0, "still quiet in the new zone");
  assertEquals(store.deferred.length, 1);

  // 12:05 UTC: 07:05 in New York.
  setNow("2026-11-24T12:05:00Z");
  await flushDeferred(deps);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].message.body, "While you were away: 1 run");
  assertEquals(store.deferred.length, 0);
});

Deno.test("DST at flush: the spring-forward morning releases at 07:00 EDT", async () => {
  const { store, sent, deps, setNow } = harness("2026-03-08T04:00:00Z"); // 23:00 EST Sat
  store.prefsRows.set(COACH, defaultPrefs(COACH, "America/New_York"));
  assertEquals(await notifyOne(runEvent("1"), deps), "deferred_quiet");
  setNow("2026-03-08T10:30:00Z"); // 06:30 EDT
  await flushDeferred(deps);
  assertEquals(sent.length, 0);
  setNow("2026-03-08T11:01:00Z"); // 07:01 EDT (06:01 under a fixed EST offset)
  await flushDeferred(deps);
  assertEquals(sent.length, 1);
});

// Copy ----------------------------------------------------------------------------------------

Deno.test("copy: names are isolated, no health words, no free text", () => {
  assertEquals(copy.runFinished("Yoni", 5.24), `${FSI}Yoni${PDI} finished a 5.2 km run`);
  assertEquals(copy.runFinished("Yoni", 10), `${FSI}Yoni${PDI} finished a 10 km run`);
  assertEquals(copy.runFinished("Yoni", null), `${FSI}Yoni${PDI} finished a run`);
  assertEquals(copy.flagged("Yoni"), `${FSI}Yoni${PDI} flagged something after a run`);
  assertEquals(copy.replied("Yoni"), `${FSI}Yoni${PDI} replied to your note`);
  assertEquals(copy.note("Dana"), `${FSI}Dana${PDI} left you a note`);
  assertEquals(copy.notes("Dana", 3), `${FSI}Dana${PDI} left you 3 notes`);
  assertEquals(copy.notes("Dana", 1), `${FSI}Dana${PDI} left you a note`);
  assertEquals(copy.whileAway(4, 1, 2), "While you were away: 4 runs · 1 flag · 2 replies");
  assertEquals(copy.whileAway(1, 0, 1), "While you were away: 1 run · 1 reply");
  assertEquals(copy.moreFinished(2), "2 more athletes finished runs");
  assertEquals(copy.moreFinished(1), "1 more athlete finished a run");
  for (
    const text of [copy.runFinished("Yoni", 5), copy.flagged("Yoni"), copy.replied("Yoni"), copy.whileAway(1, 1, 1)]
  ) {
    assertFalse(HEALTH_WORDS.test(text), text);
  }
});

Deno.test("copy: a Hebrew name stays one isolated run inside English copy (C7.15)", () => {
  assertEquals(copy.flagged("יוני כהן"), `${FSI}יוני כהן${PDI} flagged something after a run`);
  assertEquals(copy.note("דנה"), `${FSI}דנה${PDI} left you a note`);
});

Deno.test("copy: blank names fall back, long names are cut at a grapheme", () => {
  assertEquals(copy.replied("   "), `${FSI}Athlete${PDI} replied to your note`);
  assertEquals(copy.note(""), `${FSI}Your coach${PDI} left you a note`);
  const long = "👩🏽‍🦱".repeat(30);
  const body = copy.replied(long);
  assert(body.startsWith(FSI) && body.includes("…"));
});

Deno.test("formatKm", () => {
  assertEquals(formatKm(5), "5");
  assertEquals(formatKm(5.04), "5");
  assertEquals(formatKm(21.0975), "21.1");
  assertEquals(formatKm(0), null);
  assertEquals(formatKm(null), null);
  assertEquals(formatKm(Number.NaN), null);
});

Deno.test("the run dedupe window is 30 minutes (D6)", () => {
  assertEquals(RUN_DEDUPE_SECONDS, 1800);
});
