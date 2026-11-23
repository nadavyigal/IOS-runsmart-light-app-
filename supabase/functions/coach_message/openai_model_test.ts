import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { reasoningParam, selectCoachModel } from "./openai_model.ts";

const env = (vars: Record<string, string>) => (name: string) => vars[name];

Deno.test("selectCoachModel keeps today's default when nothing is set", () => {
  assertEquals(selectCoachModel("FAST", env({})), { tier: "FAST", model: "gpt-4.1-mini" });
});

Deno.test("selectCoachModel falls back to OPENAI_MODEL", () => {
  assertEquals(selectCoachModel("FAST", env({ OPENAI_MODEL: "gpt-4o-mini" })).model, "gpt-4o-mini");
  assertEquals(selectCoachModel("PLAN", env({ OPENAI_MODEL: "gpt-4o-mini" })).model, "gpt-4o-mini");
});

Deno.test("tier var wins over OPENAI_MODEL and adds the tier effort", () => {
  const sel = selectCoachModel("FAST", env({ OPENAI_MODEL: "gpt-4.1-mini", OPENAI_MODEL_FAST: "gpt-6-luna" }));
  assertEquals(sel, { tier: "FAST", model: "gpt-6-luna", reasoningEffort: "none" });
  assertEquals(reasoningParam(sel), { reasoning: { effort: "none" } });
});

Deno.test("effort env var applies; invalid values fall back to the default", () => {
  assertEquals(selectCoachModel("FAST", env({ OPENAI_MODEL_FAST: "gpt-6-luna", OPENAI_REASONING_EFFORT_FAST: "low" })).reasoningEffort, "low");
  assertEquals(selectCoachModel("FAST", env({ OPENAI_MODEL_FAST: "gpt-6-luna", OPENAI_REASONING_EFFORT_FAST: "x" })).reasoningEffort, "none");
});

Deno.test("gpt-6.2-sol never gets effort none", () => {
  assertEquals(selectCoachModel("FAST", env({ OPENAI_MODEL_FAST: "gpt-6.2-sol" })).reasoningEffort, "low");
});

Deno.test("non-reasoning models send no reasoning param", () => {
  assertEquals(reasoningParam(selectCoachModel("FAST", env({}))), {});
});
