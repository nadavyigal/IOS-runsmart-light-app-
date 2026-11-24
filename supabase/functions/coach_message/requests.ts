// Responses API request bodies for the coach_message intents that live in
// index.ts. index.ts starts the server on import, so the bodies are built here
// where tests and the live smoke harness can import them.

import { instructionsFor, runDebriefInstructions, weeklySummaryInstructions, type CoachPromptContext } from "./coach_prompts.ts";
import { reasoningParam, type CoachModelSelection } from "./openai_model.ts";
import { RUN_DEBRIEF_SCHEMA, strictJsonText, WEEKLY_SUMMARY_SCHEMA } from "./response_format.ts";
import type { CoachLanguage } from "./safety.ts";

type JsonRecord = Record<string, unknown>;

// Caps are unchanged. Raise them only after the live eval measures Hebrew
// truncation (status "incomplete").
export const RUN_DEBRIEF_MAX_OUTPUT_TOKENS = 180;
export const WEEKLY_SUMMARY_MAX_OUTPUT_TOKENS = 220;

function userInput(label: string, data: unknown) {
  return [{ role: "user", content: [{ type: "input_text", text: `${label}:\n${JSON.stringify(data)}` }] }];
}

export function buildRunDebriefRequestBody(
  context: JsonRecord,
  selection: CoachModelSelection,
  coach: CoachPromptContext | null,
  language: CoachLanguage,
): JsonRecord {
  return {
    model: selection.model,
    ...reasoningParam(selection),
    instructions: instructionsFor(runDebriefInstructions(language), coach),
    input: userInput("Run data", context),
    text: strictJsonText("run_debrief", RUN_DEBRIEF_SCHEMA),
    max_output_tokens: RUN_DEBRIEF_MAX_OUTPUT_TOKENS,
  };
}

export function buildWeeklySummaryRequestBody(
  context: JsonRecord,
  selection: CoachModelSelection,
  coach: CoachPromptContext | null,
  language: CoachLanguage,
): JsonRecord {
  return {
    model: selection.model,
    ...reasoningParam(selection),
    instructions: instructionsFor(weeklySummaryInstructions(language), coach),
    input: userInput("Week data", context),
    text: strictJsonText("weekly_summary", WEEKLY_SUMMARY_SCHEMA),
    max_output_tokens: WEEKLY_SUMMARY_MAX_OUTPUT_TOKENS,
  };
}
