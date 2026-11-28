import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyCoachLocks,
  buildFlexWeekRequestBody,
  checkFlexWeekResponse,
  fallbackFlexWeek,
  flexWeekLockRule,
  validateFlexWeekResponse,
  type FlexWeekWorkoutDTO,
} from "./flex_week.ts";
import {
  coachLockReply,
  instructionsFor,
  painFlagLockReply,
  readCoachContext,
  resolveCoachContext,
  SYSTEM_PROMPT,
  type CoachPromptContext,
} from "./coach_prompts.ts";
import { loadLockedWorkouts, type LockClient, type LockQuery } from "./locks.ts";

const IDS = [
  "11111111-1111-4111-8111-111111111111",
  "22222222-2222-4222-8222-222222222222",
  "33333333-3333-4333-8333-333333333333",
  "44444444-4444-4444-8444-444444444444",
  "55555555-5555-4555-8555-555555555555",
];

function workout(index: number, kind: string, distance: string, extra: Partial<FlexWeekWorkoutDTO> = {}): FlexWeekWorkoutDTO {
  return {
    workout_id: IDS[index],
    scheduled_date: `2026-05-${19 + index}`,
    weekday: ["MON", "TUE", "WED", "THU", "FRI"][index],
    date_label: String(19 + index),
    kind,
    title: kind,
    distance_label: distance,
    detail_label: "",
    intensity: kind === "Easy Run" ? "easy" : kind === "Recovery" ? "rest" : "hard",
    training_phase: "Build",
    is_today: index === 0,
    is_complete: false,
    ...extra,
  };
}

// Tue tempo is a coach workout; Thu is a coach rest day (a coach delete).
function week(): FlexWeekWorkoutDTO[] {
  return [
    workout(0, "Easy Run", "5.0 km"),
    workout(1, "Tempo Run", "8.0 km"),
    workout(2, "Easy Run", "6.0 km"),
    workout(3, "Recovery", "Rest"),
    workout(4, "Long Run", "14.0 km"),
  ];
}
const LOCKED = [IDS[1], IDS[3]];

function response(restructured: FlexWeekWorkoutDTO[], changes: Record<string, unknown>[]) {
  return { restructured_week: restructured, changes, safety_warnings: [], source: "live_ai" };
}

Deno.test("C8.5 AC2: a change to a locked workout is dropped and the row is copied back", () => {
  const original = week();
  const proposed = original.map((w) => ({ ...w }));
  proposed[1] = { ...proposed[1], kind: "Easy Run", title: "Easy Run", distance_label: "5.0 km", intensity: "easy" };
  proposed[2] = { ...proposed[2], distance_label: "4.0 km" };
  const parsed = response(proposed, [
    { workout_id: IDS[1], change_type: "downgraded", rationale: "Easier tempo.", original_workout_id: null },
    { workout_id: IDS[2], change_type: "downgraded", rationale: "Shorter easy run.", original_workout_id: null },
  ]);

  const validated = validateFlexWeekResponse(parsed, original, LOCKED);
  assertEquals(validated?.changes.map((c) => c.workout_id), [IDS[2]]);
  assertEquals(validated?.restructured_week[1], original[1]);
  assertEquals(validated?.restructured_week[2].distance_label, "4.0 km");
});

Deno.test("C8.5 AC2: lock ids match case-insensitively (the phone sends upper-case UUIDs)", () => {
  const original = week();
  const proposed = original.map((w) => ({ ...w }));
  proposed[1] = { ...proposed[1], distance_label: "6.0 km" };
  proposed[2] = { ...proposed[2], distance_label: "4.0 km" };
  const parsed = response(proposed, [
    { workout_id: IDS[1].toUpperCase(), change_type: "downgraded", rationale: "Shorter.", original_workout_id: null },
    { workout_id: IDS[2], change_type: "downgraded", rationale: "Shorter.", original_workout_id: null },
  ]);
  const validated = validateFlexWeekResponse(parsed, original, LOCKED.map((id) => id.toUpperCase()));
  assertEquals(validated?.changes.map((c) => c.workout_id), [IDS[2]]);
  assertEquals(validated?.restructured_week[1].distance_label, "8.0 km");
});

Deno.test("C8.5 AC4: nothing moves onto a coach rest day", () => {
  const original = week();
  const proposed = original.map((w) => ({ ...w }));
  // Move Wed easy onto Thu (the coach rest day), and shorten Mon.
  proposed[2] = { ...proposed[2], scheduled_date: original[3].scheduled_date, weekday: "THU", date_label: "22" };
  proposed[0] = { ...proposed[0], distance_label: "4.0 km" };
  const parsed = response(proposed, [
    { workout_id: IDS[2], change_type: "moved", rationale: "Moved to Thursday.", original_workout_id: IDS[2] },
    { workout_id: IDS[0], change_type: "downgraded", rationale: "Shorter.", original_workout_id: null },
  ]);
  const validated = validateFlexWeekResponse(parsed, original, LOCKED);
  assertEquals(validated?.restructured_week[2].scheduled_date, original[2].scheduled_date);
  assertEquals(validated?.changes.map((c) => c.workout_id), [IDS[0]]);
});

Deno.test("C8.5 AC4: the coach rest day itself never becomes a workout", () => {
  const original = week();
  const proposed = original.map((w) => ({ ...w }));
  proposed[3] = { ...proposed[3], kind: "Easy Run", title: "Easy Run", distance_label: "4.0 km", intensity: "easy" };
  const parsed = response(proposed, [
    { workout_id: IDS[3], change_type: "added", rationale: "Added an easy run.", original_workout_id: null },
  ]);
  const checked = checkFlexWeekResponse(parsed, original, LOCKED);
  assertEquals(checked.payload, null);
  assertEquals(checked.reason, "only_locked_changes");
});

Deno.test("C8.5: no locked ids leaves validation and the payload as before", () => {
  const original = week();
  const proposed = original.map((w) => ({ ...w }));
  proposed[1] = { ...proposed[1], kind: "Easy Run", title: "Easy Run", distance_label: "5.0 km", intensity: "easy" };
  const parsed = response(proposed, [
    { workout_id: IDS[1], change_type: "downgraded", rationale: "Easier.", original_workout_id: null },
  ]);
  assertEquals(validateFlexWeekResponse(parsed, original), validateFlexWeekResponse(parsed, original, []));
  assertEquals(validateFlexWeekResponse(parsed, original)?.changes.length, 1);
  const payload = { restructured_week: proposed, changes: [], safety_warnings: [], source: "fallback" as const };
  assertEquals(applyCoachLocks(payload, original, []), payload);
});

Deno.test("C8.5 AC2/AC4: the rule-based fallback never touches a coach workout", () => {
  const original = week();
  // Tired downgrades the next hard session: that is Tue's coach tempo.
  const request = { reason: "tired" as const, current_week: original };
  const unlocked = fallbackFlexWeek(request);
  assertEquals(unlocked.changes[0].workout_id, IDS[1]);

  const locked = fallbackFlexWeek(request, null, LOCKED);
  assertEquals(locked.changes.some((c) => LOCKED.includes(c.workout_id)), false);
  assertEquals(locked.restructured_week[1], original[1]);
  assertEquals(locked.restructured_week[3], original[3]);
});

Deno.test("C8.5: the flex week prompt names locked ids only when there are some", () => {
  const request = { reason: "tired" as const, current_week: week() };
  const selection = { model: "gpt-test", tier: "FAST" } as never;
  const plain = buildFlexWeekRequestBody(request, selection, null, "en");
  const locked = buildFlexWeekRequestBody(request, selection, null, "en", LOCKED);
  assertEquals(String(plain.instructions).includes("Coach-set workouts"), false);
  assertEquals(String(locked.instructions).endsWith(flexWeekLockRule(LOCKED)), true);
});

const dana: CoachPromptContext = { coachDisplayName: "Dana", linkActive: true, lockedWorkoutIds: [] };

Deno.test("C8.5 AC3: chat gets the exact lock reply when there are locked rows", () => {
  assertEquals(coachLockReply("Dana"), "That's Dana's workout.");
  const prompt = instructionsFor(SYSTEM_PROMPT, {
    ...dana,
    lockedWorkoutIds: [IDS[1]],
    lockedWorkouts: [{ id: IDS[1], scheduledDate: "2026-05-20", type: "tempo" }],
  });
  assertEquals(prompt.includes(`reply only: "That's Dana's workout."`), true);
  assertEquals(prompt.includes("Locked workouts set by Dana: 2026-05-20 tempo."), true);
  // A linked prompt with no locks and no flag keeps its bytes.
  assertEquals(instructionsFor(SYSTEM_PROMPT, dana).endsWith("(do not change these): (none)."), true);
});

Deno.test("C8.5 AC8: an open pain flag gives the G21 line, and the flag bit comes from the phone", () => {
  assertEquals(
    painFlagLockReply("Dana"),
    "That's Dana's workout. Your flag was sent to Dana. If the pain is sharp or doesn't go away, check with a doctor or physio.",
  );
  const prompt = instructionsFor(SYSTEM_PROMPT, { ...dana, lockedWorkoutIds: [IDS[1]], openPainFlag: true });
  assertEquals(prompt.includes(painFlagLockReply("Dana")), true);
  assertEquals(prompt.includes("Never change the plan because of it."), true);
  assertEquals(readCoachContext({ coachContext: { ...dana, openPainFlag: true } })?.openPainFlag, true);
  assertEquals(readCoachContext({ coachContext: { ...dana, openPainFlag: "yes" } })?.openPainFlag, undefined);
});

Deno.test("C8.5 AC1: locked ids come from the database, never from the client", async () => {
  const body = { coachContext: { ...dana, lockedWorkoutIds: ["client-supplied"], openPainFlag: true } };
  const rows = [{ id: IDS[1], scheduledDate: "2026-05-20", type: "tempo" }];
  const coach = await resolveCoachContext(body, () => Promise.resolve("Dana"), () => Promise.resolve(rows));
  assertEquals(coach?.lockedWorkoutIds, [IDS[1]]);
  assertEquals(coach?.lockedWorkouts, rows);
  assertEquals(coach?.openPainFlag, true);
  // A revoked link never runs the lookup.
  const revoked = await resolveCoachContext(body, () => Promise.resolve(null), () => {
    throw new Error("must not look up locks");
  });
  assertEquals(revoked, null);
});

function fakeClient(result: { data: unknown; error: unknown }, calls: string[]): LockClient {
  const query: LockQuery = {
    eq: (c, v) => (calls.push(`eq ${c}=${v}`), query),
    in: (c, v) => (calls.push(`in ${c}=${v.length}`), query),
    gte: (c, v) => (calls.push(`gte ${c}=${v}`), query),
    order: (c) => (calls.push(`order ${c}`), query),
    limit: (n) => (calls.push(`limit ${n}`), query),
    then: (resolve, reject) => Promise.resolve(result).then(resolve, reject),
  };
  return { from: (table) => ({ select: (cols) => (calls.push(`${table}:${cols}`), query) }) };
}

Deno.test("C8.5: before Batch C the missing column reads as no locks", async () => {
  const calls: string[] = [];
  const missing = fakeClient({ data: null, error: { code: "42703", message: "column workouts.locked does not exist" } }, calls);
  assertEquals(await loadLockedWorkouts(missing, IDS), []);
  assertEquals(calls, ["workouts:id, scheduled_date, type", "eq locked=true", `in id=${IDS.length}`]);
  assertEquals(await loadLockedWorkouts(missing, []), []);
});

Deno.test("C8.5: the chat lookup reads recent and upcoming locked rows", async () => {
  const calls: string[] = [];
  const client = fakeClient({ data: [{ id: IDS[1], scheduled_date: "2026-05-20", type: "tempo" }, { id: 7 }], error: null }, calls);
  const rows = await loadLockedWorkouts(client, undefined, new Date("2026-05-19T10:00:00Z"));
  assertEquals(rows, [{ id: IDS[1], scheduledDate: "2026-05-20", type: "tempo" }]);
  assertEquals(calls.includes("gte scheduled_date=2026-05-12"), true);
  assertEquals(calls.includes("limit 60"), true);
});
