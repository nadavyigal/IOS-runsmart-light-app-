import { assertEquals, assertExists } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  fallbackFlexWeek,
  sanitizeFlexWeekRequest,
  validateFlexWeekResponse,
  type FlexWeekWorkoutDTO,
} from "./flex_week.ts";

const workoutIDs = [
  "11111111-1111-4111-8111-111111111111",
  "22222222-2222-4222-8222-222222222222",
  "33333333-3333-4333-8333-333333333333",
  "44444444-4444-4444-8444-444444444444",
  "55555555-5555-4555-8555-555555555555",
];

function sampleWeek(options: { taper?: boolean; hardToday?: boolean } = {}): FlexWeekWorkoutDTO[] {
  const base = "2026-05-19";
  const kinds = ["Easy Run", "Tempo Run", "Tempo Run", "Easy Run", "Long Run"];
  const titles = ["Easy Run", "Tempo Run", "Tempo Run", "Easy Run", "Long Run"];
  const distances = ["5.0 km", "8.0 km", "8.0 km", "6.0 km", "14.0 km"];

  if (!options.hardToday) {
    kinds[2] = "Easy Run";
    titles[2] = "Easy Run";
    distances[2] = "5.0 km";
  }

  return workoutIDs.map((workout_id, index) => ({
    workout_id,
    scheduled_date: addDays(base, index),
    weekday: ["MON", "TUE", "WED", "THU", "FRI"][index],
    date_label: String(19 + index),
    kind: kinds[index],
    title: titles[index],
    distance_label: distances[index],
    detail_label: "",
    intensity: kinds[index].includes("Easy") ? "easy" : "hard",
    training_phase: options.taper ? "Taper" : "Build",
    is_today: index === 2,
    is_complete: index === 0,
  }));
}

function addDays(isoDate: string, days: number): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

Deno.test("sanitizeFlexWeekRequest accepts tired payload", () => {
  const request = sanitizeFlexWeekRequest({
    intent: "flex_week",
    reason: "tired",
    currentWeek: sampleWeek(),
    readinessContext: { readiness: 42, readinessLabel: "Low" },
  });
  assertExists(request);
  assertEquals(request?.reason, "tired");
  assertEquals(request?.current_week.length, 5);
});

Deno.test("sanitizeFlexWeekRequest keeps training load fields", () => {
  const request = sanitizeFlexWeekRequest({
    intent: "flex_week",
    reason: "tired",
    currentWeek: sampleWeek(),
    readinessContext: {
      readiness: 42,
      readinessLabel: "Low",
      acwr: 1.62,
      acuteLoad: 1780,
      chronicLoad: 1100,
      loadStatus: "highRisk",
    },
  });
  assertExists(request);
  assertEquals(request?.readiness_context?.acwr, 1.62);
  assertEquals(request?.readiness_context?.acute_load, 1780);
  assertEquals(request?.readiness_context?.chronic_load, 1100);
  assertEquals(request?.readiness_context?.load_status, "highRisk");
});

Deno.test("sanitizeFlexWeekRequest accepts snake_case load fields", () => {
  const request = sanitizeFlexWeekRequest({
    intent: "flex_week",
    reason: "tired",
    currentWeek: sampleWeek(),
    readiness_context: {
      readiness: 42,
      acwr: 0.7,
      acute_load: 400,
      chronic_load: 570,
      load_status: "detraining",
    },
  });
  assertExists(request);
  assertEquals(request?.readiness_context?.acwr, 0.7);
  assertEquals(request?.readiness_context?.load_status, "detraining");
});

Deno.test("fallbackFlexWeek tired downgrades hard today", () => {
  const request = sanitizeFlexWeekRequest({
    reason: "tired",
    currentWeek: sampleWeek({ hardToday: true }),
  });
  assertExists(request);
  const outcome = fallbackFlexWeek(request!);
  const today = outcome.restructured_week.find((w) => w.is_today);
  assertExists(today);
  assertEquals(today?.kind, "Easy Run");
  assertEquals(outcome.changes.some((c) => c.change_type === "downgraded"), true);
  assertEquals(outcome.source, "fallback");
});

Deno.test("fallbackFlexWeek traveling marks blocked days as rest", () => {
  const week = sampleWeek();
  const request = sanitizeFlexWeekRequest({
    reason: "traveling",
    currentWeek: week,
    blockedDays: [week[3].scheduled_date],
  });
  assertExists(request);
  const outcome = fallbackFlexWeek(request!);
  assertEquals(outcome.restructured_week[3].distance_label, "Rest");
  assertEquals(outcome.changes.some((c) => c.rationale.toLowerCase().includes("travel")), true);
});

Deno.test("fallbackFlexWeek missed workout moves to open slot", () => {
  const week = sampleWeek({ hardToday: false });
  const request = sanitizeFlexWeekRequest({
    reason: "missed_workout",
    currentWeek: week,
    missedWorkoutId: week[1].workout_id,
  });
  assertExists(request);
  const outcome = fallbackFlexWeek(request!);
  assertEquals(outcome.restructured_week[1].distance_label, "Rest");
  assertEquals(outcome.changes.some((c) => c.change_type === "moved"), true);
});

Deno.test("fallbackFlexWeek sick marks recovery window as rest", () => {
  const week = sampleWeek({ hardToday: false });
  const request = sanitizeFlexWeekRequest({
    reason: "sick",
    currentWeek: week,
    sickDaysOut: 4,
  });
  assertExists(request);
  const outcome = fallbackFlexWeek(request!);
  assertEquals(outcome.restructured_week[2].distance_label, "Rest");
  assertEquals(outcome.restructured_week[3].distance_label, "Rest");
  assertEquals(outcome.changes.some((c) => c.rationale.toLowerCase().includes("recover")), true);
});

Deno.test("fallbackFlexWeek taper week locks schedule", () => {
  const week = sampleWeek({ taper: true, hardToday: true });
  const request = sanitizeFlexWeekRequest({
    reason: "tired",
    currentWeek: week,
  });
  assertExists(request);
  const outcome = fallbackFlexWeek(request!);
  assertEquals(
    outcome.restructured_week.map((workout) => workout.workout_id),
    week.map((workout) => workout.workout_id),
  );
  assertEquals(outcome.changes[0]?.rationale.includes("Taper week"), true);
});

Deno.test("validateFlexWeekResponse rejects long-run removal", () => {
  const week = sampleWeek();
  const mutated = week.map((workout) => ({ ...workout }));
  mutated[4] = {
    ...mutated[4],
    kind: "Easy Run",
    title: "Easy Run",
    distance_label: "5.0 km",
  };
  const validated = validateFlexWeekResponse({
    restructuredWeek: mutated,
    changes: [{
      workoutId: mutated[4].workout_id,
      changeType: "downgraded",
      rationale: "Removed long run",
    }],
    safetyWarnings: [],
    source: "live_ai",
  }, week);
  assertEquals(validated, null);
});
