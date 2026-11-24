import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  carefulPathWarning,
  FLEX_WEEK_SYSTEM_PROMPT,
  flexWeekInstructions,
  HEBREW_STYLE,
  instructionsFor,
  readCoachContext,
  resolveCoachContext,
  RUN_DEBRIEF_SYSTEM_PROMPT,
  SOLO_CAREFUL_PATH,
  SYSTEM_PROMPT,
  WEEKLY_SUMMARY_SYSTEM_PROMPT,
  type CoachPromptContext,
} from "./coach_prompts.ts";

const dana: CoachPromptContext = {
  coachDisplayName: "Dana",
  linkActive: true,
  lockedWorkoutIds: [],
};

function assertSoloUnchanged(base: string) {
  assertEquals(instructionsFor(base, null), base);
  assertEquals(
    instructionsFor(base, { coachDisplayName: "Dana", linkActive: false, lockedWorkoutIds: ["x"] }),
    base,
  );
}

function assertLinkedDefers(base: string) {
  const prompt = instructionsFor(base, dana);
  assertEquals(prompt.startsWith(base), true);
  assertEquals(prompt.length > base.length, true);
  assertEquals(prompt.includes("Adjusted Tuesday within Dana's plan"), true);
  assertEquals(prompt.includes("Never change, override, or criticize a workout Dana set."), true);
  assertEquals(prompt.includes("Never write as or on behalf of Dana."), true);
  assertEquals(prompt.includes("Injury or pain goes to a doctor or physio."), true);
  assertEquals(prompt.includes("Plan disputes defer to Dana's plan."), true);
  assertEquals(prompt.includes("Do not tell the athlete to ask Dana in chat."), true);
  assertEquals(prompt.includes("Locked workout ids (do not change these): (none)."), true);
  assertEquals(prompt.slice(0, base.length), base);
}

Deno.test("chat prompt: solo is unchanged and linked defers to the coach", () => {
  assertSoloUnchanged(SYSTEM_PROMPT);
  assertLinkedDefers(SYSTEM_PROMPT);
  assertEquals(SYSTEM_PROMPT.startsWith("You are RunSmart Coach, a calm AI running coach"), true);
});

Deno.test("run debrief prompt: solo is unchanged and linked defers to the coach", () => {
  assertSoloUnchanged(RUN_DEBRIEF_SYSTEM_PROMPT);
  assertLinkedDefers(RUN_DEBRIEF_SYSTEM_PROMPT);
  assertEquals(RUN_DEBRIEF_SYSTEM_PROMPT.startsWith("You are RunSmart Coach writing a short debrief right after a run."), true);
  assertEquals(RUN_DEBRIEF_SYSTEM_PROMPT.includes("This is not medical advice; do not diagnose."), true);
  assertEquals(RUN_DEBRIEF_SYSTEM_PROMPT.includes("suggest a qualified professional"), true);
});

Deno.test("weekly summary prompt: solo is unchanged and linked defers to the coach", () => {
  assertSoloUnchanged(WEEKLY_SUMMARY_SYSTEM_PROMPT);
  assertLinkedDefers(WEEKLY_SUMMARY_SYSTEM_PROMPT);
  assertEquals(
    WEEKLY_SUMMARY_SYSTEM_PROMPT.startsWith("You are RunSmart Coach writing a short end-of-week summary"),
    true,
  );
});

Deno.test("flex week prompt: solo is unchanged and linked defers to the coach", () => {
  assertSoloUnchanged(FLEX_WEEK_SYSTEM_PROMPT);
  assertLinkedDefers(FLEX_WEEK_SYSTEM_PROMPT);
  assertEquals(
    FLEX_WEEK_SYSTEM_PROMPT.startsWith("You are RunSmart Coach. The runner hit a life disruption"),
    true,
  );
  for (const rule of [
    "Never drop a Long Run.",
    "Weekly distance must not rise more than 10% versus current_week.",
    "No back-to-back hard days",
    "At most 6 changes. Never turn a rest day into a hard effort.",
    "Sick: no hard sessions within 48 hours after the last sick day.",
    "Do not diagnose illness or injury.",
    "same English vocabulary used in current_week",
  ]) {
    assertEquals(FLEX_WEEK_SYSTEM_PROMPT.includes(rule), true, rule);
  }
  assertLinkedDefers(flexWeekInstructions("he"));
  assertEquals(
    flexWeekInstructions("en").endsWith("Language: write rationale and safety_warnings in English."),
    true,
  );
  assertEquals(flexWeekInstructions("he").includes("rationale and safety_warnings in Hebrew."), true);
  assertEquals(flexWeekInstructions("he").includes(HEBREW_STYLE), true);
  assertEquals(carefulPathWarning(null), SOLO_CAREFUL_PATH);
  assertEquals(
    carefulPathWarning(dana),
    "RunSmart is taking a careful path — here's a safe adjustment based on standard recovery rules.",
  );
});

Deno.test("linked prompt carries locked workout ids and ignores a solo body", () => {
  const locked = instructionsFor(SYSTEM_PROMPT, { ...dana, lockedWorkoutIds: ["workout-9"] });
  assertEquals(locked.includes("Locked workout ids (do not change these): workout-9."), true);
  assertEquals(readCoachContext({}), null);
  assertEquals(readCoachContext({ coachContext: { linkActive: false, coachDisplayName: "Dana" } }), null);
  assertEquals(
    readCoachContext({
      coachContext: { linkActive: true, coachDisplayName: " Dana ", lockedWorkoutIds: ["a", ""] },
    }),
    { coachDisplayName: "Dana", linkActive: true, lockedWorkoutIds: ["a"] },
  );
});

Deno.test("solo requests do not look up a coach link", async () => {
  const coach = await resolveCoachContext({}, async () => {
    throw new Error("Solo requests must skip the lookup");
  });
  assertEquals(coach, null);
});

Deno.test("linked requests require an active matching coach and ignore client locks", async () => {
  const body = { coachContext: { ...dana, lockedWorkoutIds: ["client-supplied"] } };
  assertEquals(await resolveCoachContext(body, () => Promise.resolve(null)), null);
  assertEquals(await resolveCoachContext(body, () => Promise.resolve("New coach")), null);
  assertEquals(await resolveCoachContext(body, () => Promise.resolve("Dana")), dana);
});
