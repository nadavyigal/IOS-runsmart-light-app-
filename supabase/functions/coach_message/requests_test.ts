import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { HEBREW_STYLE, type CoachPromptContext } from "./coach_prompts.ts";
import { FLEX_WEEK_SCHEMA } from "./flex_week.ts";
import {
  buildRunDebriefRequestBody,
  buildWeeklySummaryRequestBody,
  RUN_DEBRIEF_MAX_OUTPUT_TOKENS,
  WEEKLY_SUMMARY_MAX_OUTPUT_TOKENS,
} from "./requests.ts";
import { responseFailureReason, RUN_DEBRIEF_SCHEMA, WEEKLY_SUMMARY_SCHEMA } from "./response_format.ts";

const fast = { tier: "FAST" as const, model: "gpt-6-luna", reasoningEffort: "none" as const };
const dana: CoachPromptContext = { coachDisplayName: "Dana", linkActive: true, lockedWorkoutIds: [] };

// Strict mode: every object lists all its properties as required and allows no extras.
function assertStrict(schema: Record<string, unknown>, path = "$") {
  if (schema.type === "object") {
    const props = Object.keys(schema.properties as Record<string, unknown>);
    assertEquals(schema.additionalProperties, false, path);
    assertEquals([...(schema.required as string[])].sort(), [...props].sort(), path);
    for (const [key, value] of Object.entries(schema.properties as Record<string, Record<string, unknown>>)) {
      assertStrict(value, `${path}.${key}`);
    }
  }
  if (schema.type === "array") assertStrict(schema.items as Record<string, unknown>, `${path}[]`);
}

Deno.test("structured-output schemas follow strict-mode rules", () => {
  assertStrict(RUN_DEBRIEF_SCHEMA);
  assertStrict(WEEKLY_SUMMARY_SCHEMA);
  assertStrict(FLEX_WEEK_SCHEMA);
});

Deno.test("debrief body: strict schema, language line, unchanged cap, coach rules last", () => {
  const he = buildRunDebriefRequestBody({ runDistanceKm: 5 }, fast, dana, "he");
  const format = (he.text as { format: Record<string, unknown> }).format;
  assertEquals(format.type, "json_schema");
  assertEquals(format.strict, true);
  assertEquals(format.name, "run_debrief");
  assertEquals(he.max_output_tokens, RUN_DEBRIEF_MAX_OUTPUT_TOKENS);
  assertEquals(RUN_DEBRIEF_MAX_OUTPUT_TOKENS, 180);
  const instructions = String(he.instructions);
  assertEquals(instructions.includes("Language: write all four fields in Hebrew."), true);
  assertEquals(instructions.includes(HEBREW_STYLE), true);
  assertEquals(instructions.includes("Never change, override, or criticize a workout Dana set."), true);
  assertEquals(he.reasoning, { effort: "none" });

  const en = buildRunDebriefRequestBody({ runDistanceKm: 5 }, fast, null, "en");
  assertEquals(String(en.instructions).endsWith("Language: write all four fields in English."), true);
});

Deno.test("weekly body: strict schema and unchanged cap", () => {
  const body = buildWeeklySummaryRequestBody({ runsCompleted: 3 }, fast, null, "en");
  assertEquals((body.text as { format: Record<string, unknown> }).format.name, "weekly_summary");
  assertEquals(body.max_output_tokens, WEEKLY_SUMMARY_MAX_OUTPUT_TOKENS);
  assertEquals(WEEKLY_SUMMARY_MAX_OUTPUT_TOKENS, 220);
});

Deno.test("responseFailureReason spots truncation and refusals", () => {
  assertEquals(responseFailureReason({ status: "completed", output_text: "{}" }), null);
  assertEquals(
    responseFailureReason({ status: "incomplete", incomplete_details: { reason: "max_output_tokens" } }),
    "incomplete:max_output_tokens",
  );
  assertEquals(
    responseFailureReason({ status: "completed", output: [{ content: [{ type: "refusal", refusal: "no" }] }] }),
    "refusal",
  );
});
