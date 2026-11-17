import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  carefulPathWarning,
  FLEX_WEEK_SYSTEM_PROMPT,
  instructionsFor,
  readCoachContext,
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
  assertEquals(RUN_DEBRIEF_SYSTEM_PROMPT.startsWith("You are RunSmart Coach. Given a completed run's data"), true);
});

Deno.test("weekly summary prompt: solo is unchanged and linked defers to the coach", () => {
  assertSoloUnchanged(WEEKLY_SUMMARY_SYSTEM_PROMPT);
  assertLinkedDefers(WEEKLY_SUMMARY_SYSTEM_PROMPT);
  assertEquals(
    WEEKLY_SUMMARY_SYSTEM_PROMPT.startsWith("You are RunSmart Coach. Given a runner's week summary data"),
    true,
  );
});

Deno.test("flex week prompt: solo is unchanged and linked defers to the coach", () => {
  assertSoloUnchanged(FLEX_WEEK_SYSTEM_PROMPT);
  assertLinkedDefers(FLEX_WEEK_SYSTEM_PROMPT);
  assertEquals(
    FLEX_WEEK_SYSTEM_PROMPT.startsWith("You are RunSmart Coach. Restructure the runner's current ISO week"),
    true,
  );
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
