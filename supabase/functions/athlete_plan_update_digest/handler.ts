// athlete_plan_update_digest (story C8.16): the bundled "{Coach} updated your plan ·
// {n} changes" push (D3).
//
// Called only by the 2-minute cron, with the header x-coach-notify-secret =
// COACH_NOTIFY_SECRET, the same secret coach_notify and coach_evening_summary check.
// Never a user JWT. Body: {} or empty. Other object fields are ignored; a body that is
// not a JSON object gets 400.
//
// Every request checks the kill switch first (coach_v2 and coach_v2_push, C7.12):
// with either off it sends nothing and deletes nothing, so every queued batch is
// kept for when the flag returns (AC3). Then digest.ts sends what is due.

import { exitIfFlagsOff, type FlagsRpcClient } from "../_shared/flags.ts";
import { secretMatches } from "../_shared/notify.ts";
import { type DigestDeps, sendPlanUpdates } from "./digest.ts";

export interface HandlerDeps {
  /** COACH_NOTIFY_SECRET. Null when unset: every call is refused. */
  secret: string | null;
  flags: FlagsRpcClient;
  /** Null when the APNs secrets are missing: every call is refused, nothing is touched. */
  digest: DigestDeps | null;
  log?: (line: Record<string, unknown>) => void;
}

export async function handlePlanUpdateDigest(req: Request, deps: HandlerDeps): Promise<Response> {
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

  const skip = await exitIfFlagsOff(deps.flags, ["coach_v2", "coach_v2_push"], "athlete_plan_update_digest", { log });
  if (skip) return skip;
  if (!deps.digest) {
    log({ event: "apns_not_configured", function: "athlete_plan_update_digest" });
    return json(503, { error: "apns_not_configured" });
  }

  try {
    const run = await sendPlanUpdates({ ...deps.digest, log });
    return json(200, { run });
  } catch (error) {
    log({ event: "athlete_plan_update_digest_error", detail: error instanceof Error ? error.message : String(error) });
    return json(500, { error: "internal_error" });
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
