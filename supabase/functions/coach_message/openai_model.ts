/**
 * OpenAI model selection for coach_message.
 *
 *   OPENAI_MODEL_FAST   run debrief, weekly summary, live chat, flex week
 *                       (target gpt-6-luna)
 *   OPENAI_MODEL_PLAN   reserved for planning calls; nothing uses it yet
 *   OPENAI_MODEL        shared default (unchanged), then gpt-4.1-mini
 *
 *   OPENAI_REASONING_EFFORT_FAST / _PLAN   effort for reasoning models
 *                                          (default none / low)
 *
 * Unset tier vars fall back to OPENAI_MODEL, then gpt-4.1-mini, so deploying
 * this changes nothing until a tier var is set. Rollback = unset it.
 *
 * gpt-5 / gpt-6 ids are reasoning models: checked on the live API 2026-11-23,
 * gpt-6.2-sol rejects effort "none" (lowest is "low"). Reasoning tokens count
 * against max_output_tokens and bill as output.
 */

export type CoachModelTier = "FAST" | "PLAN";

export type ReasoningEffort = "none" | "minimal" | "low" | "medium" | "high" | "xhigh";

const EFFORTS: readonly ReasoningEffort[] = ["none", "minimal", "low", "medium", "high", "xhigh"];
const DEFAULT_EFFORT: Record<CoachModelTier, ReasoningEffort> = { FAST: "none", PLAN: "low" };
const LEGACY_DEFAULT_MODEL = "gpt-4.1-mini";

export interface CoachModelSelection {
  tier: CoachModelTier;
  model: string;
  reasoningEffort?: ReasoningEffort;
}

type EnvReader = (name: string) => string | undefined;

const denoEnv: EnvReader = (name) => Deno.env.get(name);

function read(env: EnvReader, name: string): string | undefined {
  const value = env(name)?.trim();
  return value ? value : undefined;
}

export function isReasoningModel(model: string): boolean {
  return /^(o\d|gpt-5|gpt-6)/i.test(model.trim());
}

export function selectCoachModel(tier: CoachModelTier, env: EnvReader = denoEnv): CoachModelSelection {
  const model = read(env, `OPENAI_MODEL_${tier}`) ?? read(env, "OPENAI_MODEL") ?? LEGACY_DEFAULT_MODEL;
  if (!isReasoningModel(model)) return { tier, model };
  const envEffort = read(env, `OPENAI_REASONING_EFFORT_${tier}`) as ReasoningEffort | undefined;
  let effort = envEffort && EFFORTS.includes(envEffort) ? envEffort : DEFAULT_EFFORT[tier];
  if ((effort === "none" || effort === "minimal") && /^gpt-6\.2-sol/i.test(model)) effort = "low";
  return { tier, model, reasoningEffort: effort };
}

/** Responses API `reasoning` param; empty for non-reasoning models. */
export function reasoningParam(selection: CoachModelSelection): { reasoning?: { effort: ReasoningEffort } } {
  return selection.reasoningEffort ? { reasoning: { effort: selection.reasoningEffort } } : {};
}

// deno-lint-ignore no-explicit-any
export function logModelUsage(callSite: string, selection: CoachModelSelection, json: any, latencyMs: number): void {
  const usage = json?.usage ?? {};
  console.info(JSON.stringify({
    event: "openai_usage",
    callSite,
    tier: selection.tier,
    model: selection.model,
    reasoningEffort: selection.reasoningEffort ?? null,
    latencyMs,
    inputTokens: usage.input_tokens ?? null,
    outputTokens: usage.output_tokens ?? null,
    reasoningTokens: usage.output_tokens_details?.reasoning_tokens ?? null,
  }));
}
