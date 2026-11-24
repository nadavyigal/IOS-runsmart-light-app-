/**
 * Live smoke for coach_message model tiers. Calls the real OpenAI API; not a test
 * file (no _test suffix), so `deno test` never runs it.
 *
 *   OPENAI_API_KEY=... deno run --allow-env --allow-net smoke_live.ts
 *   OPENAI_MODEL_FAST=gpt-6-luna deno run --allow-env --allow-net smoke_live.ts
 *
 * Flex week goes through the real generateFlexWeek (prompt, 4 s timeout,
 * validation, fallback). The run debrief request mirrors index.ts
 * (generateRunDebrief is not exported; index.ts starts the server on import).
 */
import { RUN_DEBRIEF_SYSTEM_PROMPT, instructionsFor } from "./coach_prompts.ts";
import { buildFlexWeekRequestBody, generateFlexWeek, validateFlexWeekResponse, type FlexWeekRequestPayload, type FlexWeekWorkoutDTO } from "./flex_week.ts";
import { reasoningParam, selectCoachModel } from "./openai_model.ts";

const apiKey = Deno.env.get("OPENAI_API_KEY");
if (!apiKey) throw new Error("OPENAI_API_KEY is not set");

const RUNS = [
  { runDistanceKm: 5.2, runDurationSeconds: 1690, avgPaceSecondsPerKm: 325, runType: "easy", avgHeartRate: 142, perceivedEffort: 4 },
  { runDistanceKm: 10.1, runDurationSeconds: 2950, avgPaceSecondsPerKm: 292, runType: "tempo", avgHeartRate: 168, perceivedEffort: 8 },
  { runDistanceKm: 18.0, runDurationSeconds: 6300, avgPaceSecondsPerKm: 350, runType: "long", avgHeartRate: 151, perceivedEffort: 6 },
  { runDistanceKm: 3.0, runDurationSeconds: 1200, avgPaceSecondsPerKm: 400, runType: "easy", perceivedEffort: 3, notes: "first run back after a cold" },
  { runDistanceKm: 6.4, runDurationSeconds: 1810, avgPaceSecondsPerKm: 283, runType: "intervals", avgHeartRate: 172, perceivedEffort: 9 },
];

const ids = ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222", "33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444", "55555555-5555-4555-8555-555555555555"];
function week(): FlexWeekWorkoutDTO[] {
  const kinds = ["Easy Run", "Tempo Run", "Tempo Run", "Easy Run", "Long Run"];
  const distances = ["5.0 km", "8.0 km", "8.0 km", "6.0 km", "14.0 km"];
  return ids.map((workout_id, i) => ({
    workout_id,
    scheduled_date: `2026-11-${String(23 + i).padStart(2, "0")}`,
    weekday: ["MON", "TUE", "WED", "THU", "FRI"][i],
    date_label: String(23 + i),
    kind: kinds[i],
    title: kinds[i],
    distance_label: distances[i],
    detail_label: "",
    intensity: kinds[i].includes("Easy") ? "easy" : "hard",
    training_phase: "Build",
    is_today: i === 2,
    is_complete: i === 0,
  })) as FlexWeekWorkoutDTO[];
}
const FLEX: FlexWeekRequestPayload[] = [
  { reason: "tired", current_week: week() },
  { reason: "traveling", current_week: week(), blocked_days: ["2026-11-26", "2026-11-27"] },
  { reason: "missed_workout", current_week: week(), missed_workout_id: ids[1] },
];

type Usage = { input: number; output: number; reasoning: number };
function usage(json: any): Usage {
  const u = json?.usage ?? {};
  return { input: u.input_tokens ?? 0, output: u.output_tokens ?? 0, reasoning: u.output_tokens_details?.reasoning_tokens ?? 0 };
}

const sel = selectCoachModel("FAST");
console.log(`# FAST=${sel.model} effort=${sel.reasoningEffort ?? "-"}`);

const debriefRows: { ok: boolean; ms: number; u: Usage }[] = [];
for (const run of RUNS) {
  const t = Date.now();
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: sel.model,
      ...reasoningParam(sel),
      instructions: instructionsFor(RUN_DEBRIEF_SYSTEM_PROMPT, null),
      input: [{ role: "user", content: [{ type: "input_text", text: `Run data:\n${JSON.stringify(run)}` }] }],
      max_output_tokens: 180,
    }),
  });
  const json = await res.json();
  const text = typeof json.output_text === "string" ? json.output_text : (json.output ?? []).flatMap((o: any) => o.content ?? []).map((c: any) => c.text ?? "").join("");
  let ok = false;
  let detail = json.error?.message ?? text;
  try {
    const p = JSON.parse(text);
    ok = Boolean(p.headline && p.debrief && p.tomorrow);
    detail = p.headline;
  } catch { /* invalid JSON */ }
  const ms = Date.now() - t;
  debriefRows.push({ ok, ms, u: usage(json) });
  console.log(JSON.stringify({ site: "run_debrief", ok, ms, status: json.status, incomplete: json.incomplete_details ?? null, detail: String(detail).slice(0, 90) }));
}

const flexRows: { ok: boolean; ms: number; u: Usage }[] = [];
for (const req of FLEX) {
  let captured: any = null;
  const t = Date.now();
  const fetchImpl: typeof fetch = async (input, init) => {
    const r = await fetch(input, init);
    captured = await r.clone().json().catch(() => null);
    return r;
  };
  const out = await generateFlexWeek(req, fetchImpl, null);
  const ms = Date.now() - t;
  flexRows.push({ ok: out.source === "live_ai", ms, u: usage(captured) });
  console.log(JSON.stringify({ site: "flex_week", reason: req.reason, source: out.source, ms, changes: out.changes.length }));
}

// Same request as generateFlexWeek, without its 4 s abort, to compare model quality.
const flexNoTimeout: { ok: boolean; ms: number; u: Usage }[] = [];
for (const req of FLEX) {
  const t = Date.now();
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify(buildFlexWeekRequestBody(req, sel, null, "en")),
  });
  const json = await res.json();
  const text = typeof json.output_text === "string" ? json.output_text : (json.output ?? []).flatMap((o: any) => o.content ?? []).map((c: any) => c.text ?? "").join("");
  let ok = false;
  let why = "";
  try {
    ok = Boolean(validateFlexWeekResponse(JSON.parse(text), req.current_week));
    if (!ok) why = "failed validation";
  } catch (e) { why = `invalid JSON (${json.status}${json.incomplete_details ? " " + JSON.stringify(json.incomplete_details) : ""})`; }
  const ms = Date.now() - t;
  flexNoTimeout.push({ ok, ms, u: usage(json) });
  console.log(JSON.stringify({ site: "flex_week_no_timeout", reason: req.reason, ok, ms, why }));
}

function summary(name: string, rows: { ok: boolean; ms: number; u: Usage }[]) {
  const ms = rows.map((r) => r.ms).sort((a, b) => a - b);
  const sum = (k: keyof Usage) => rows.reduce((n, r) => n + r.u[k], 0);
  console.log(`| ${name} | ${sel.model} | ${rows.filter((r) => r.ok).length}/${rows.length} | ${ms[Math.floor(ms.length / 2)]} | ${ms[ms.length - 1]} | ${sum("input")} | ${sum("output")} | ${sum("reasoning")} |`);
}
console.log("| Site | Model | Valid (live AI) | p50 ms | max ms | in tok | out tok | reasoning tok |");
summary("run_debrief", debriefRows);
summary("flex_week (prod 4 s timeout)", flexRows);
summary("flex_week (no timeout)", flexNoTimeout);
