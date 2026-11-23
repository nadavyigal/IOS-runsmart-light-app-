// coach_evening_summary (story C7.6): the 20:00 coach push with counts.
//
// Called only by the hourly cron (docs/coach-v2-batch-b-runbook.md), with the header
// x-coach-notify-secret = COACH_NOTIFY_SECRET, the same secret coach_notify checks.
// Never a user JWT. Body: {} (anything else in it is ignored).
//
// Every request checks the kill switch first (coach_v2 and coach_v2_push, C7.12,
// AC7): with either off it sends nothing, holds nothing and deletes nothing.
// Then it flushes held summaries and sends the ones due now (summary.ts).

import { exitIfFlagsOff, type FlagsRpcClient } from "../_shared/flags.ts";
import { secretMatches } from "../_shared/notify.ts";
import { flushEveningSummaries, sendEveningSummaries, type SummaryDeps } from "./summary.ts";

export interface HandlerDeps {
  /** COACH_NOTIFY_SECRET. Null when unset: every call is refused. */
  secret: string | null;
  flags: FlagsRpcClient;
  /** Null when the APNs secrets are missing: every call is refused, nothing is touched. */
  summary: SummaryDeps | null;
  log?: (line: Record<string, unknown>) => void;
}

export async function handleEveningSummary(req: Request, deps: HandlerDeps): Promise<Response> {
  const log = deps.log ?? ((line: Record<string, unknown>) => console.log(JSON.stringify(line)));
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!deps.secret) return json(500, { error: "server_configuration_missing" });
  if (!(await secretMatches(req.headers.get("x-coach-notify-secret") ?? "", deps.secret))) {
    return json(401, { error: "unauthorized" });
  }

  try {
    const text = await req.text();
    if (text.trim()) {
      const parsed = JSON.parse(text);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not_object");
    }
  } catch {
    return json(400, { error: "bad_body" });
  }

  const skip = await exitIfFlagsOff(deps.flags, ["coach_v2", "coach_v2_push"], "coach_evening_summary", { log });
  if (skip) return skip;
  if (!deps.summary) {
    log({ event: "apns_not_configured", function: "coach_evening_summary" });
    return json(503, { error: "apns_not_configured" });
  }

  try {
    const summaryDeps = { ...deps.summary, log };
    const flush = await flushEveningSummaries(summaryDeps);
    const run = await sendEveningSummaries(summaryDeps);
    return json(200, { flush, run });
  } catch (error) {
    log({ event: "coach_evening_summary_error", detail: error instanceof Error ? error.message : String(error) });
    return json(500, { error: "internal_error" });
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
