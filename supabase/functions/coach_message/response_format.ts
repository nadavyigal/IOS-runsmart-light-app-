// Responses API structured-output helpers shared by coach_message call sites.
// A strict schema makes valid JSON the norm, but refusals and truncated
// (incomplete) responses still happen, so every caller keeps its JSON.parse,
// its validation and its deterministic fallback.

type JsonRecord = Record<string, unknown>;

/** `text` parameter for a strict json_schema response. */
export function strictJsonText(name: string, schema: JsonRecord): { format: JsonRecord } {
  return { format: { type: "json_schema", name, strict: true, schema } };
}

/**
 * Why a Responses payload has no usable answer, or null when it does.
 * "incomplete:max_output_tokens" means the cap was hit (reasoning tokens count
 * against it); "refusal" means the model declined.
 */
export function responseFailureReason(json: JsonRecord): string | null {
  if (json.status === "incomplete") {
    const details = json.incomplete_details;
    const reason = details && typeof details === "object" && !Array.isArray(details)
      ? (details as JsonRecord).reason
      : null;
    return `incomplete:${typeof reason === "string" ? reason : "unknown"}`;
  }
  const output = Array.isArray(json.output) ? json.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as JsonRecord).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (part && typeof part === "object" && (part as JsonRecord).type === "refusal") return "refusal";
    }
  }
  return null;
}

const nullableString = { type: ["string", "null"] };

export const RUN_DEBRIEF_SCHEMA: JsonRecord = {
  type: "object",
  additionalProperties: false,
  required: ["headline", "debrief", "tomorrow", "planImpact"],
  properties: {
    headline: { type: "string" },
    debrief: { type: "string" },
    tomorrow: { type: "string" },
    planImpact: nullableString,
  },
};

export const WEEKLY_SUMMARY_SCHEMA: JsonRecord = {
  type: "object",
  additionalProperties: false,
  required: ["headline", "narrative", "forwardLook", "weekLabel"],
  properties: {
    headline: { type: "string" },
    narrative: { type: "string" },
    forwardLook: { type: "string" },
    weekLabel: { type: "string" },
  },
};
