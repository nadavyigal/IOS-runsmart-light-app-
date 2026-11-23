// push_selftest (story C7.10 AC7). DEV ONLY.
//
// Sends one fixed test push to the caller's own devices, so Nadav can check APNs
// end to end on TestFlight. It never takes a user id, a token or any text from the
// request: the target is always the signed-in caller.
//
// Two locks keep it out of production use:
//   1. It answers 404 unless the secret PUSH_SELFTEST_ENABLED is "true".
//   2. It is in no deploy script. Deploy it by hand to a dev project only:
//        supabase functions deploy push_selftest --project-ref <dev ref>
//      The Deno test push_selftest/handler_test.ts fails if any file in scripts/
//      or .github/workflows/ mentions it.

import {
  type ApnsConfig,
  type ApnsSendDeps,
  type ApnsTarget,
  type ApnsOutcome,
  sendApnsToAll,
  summarizeOutcomes,
} from "../_shared/apns.ts";

export const SELFTEST_MESSAGE = {
  kind: "selfTest" as const,
  title: "RunSmart test push",
  body: "If you can read this, push works on this device.",
};

export interface SelftestDeps {
  enabled: boolean;
  config: ApnsConfig | null;
  /** The caller's user id from their access token, or null when it is missing or invalid. */
  userIdFor: (accessToken: string) => Promise<string | null>;
  liveTokens: (userId: string) => Promise<ApnsTarget[]>;
  disableToken: (token: string) => Promise<void>;
  send?: (targets: readonly ApnsTarget[], deps: ApnsSendDeps) => Promise<ApnsOutcome[]>;
  fetch?: typeof fetch;
  log?: (line: Record<string, unknown>) => void;
}

export async function handleSelftest(req: Request, deps: SelftestDeps): Promise<Response> {
  if (!deps.enabled) return json(404, { error: "not_found" });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!deps.config) return json(503, { error: "apns_not_configured" });

  const accessToken = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!accessToken) return json(401, { error: "missing_access_token" });
  const userId = await deps.userIdFor(accessToken);
  if (!userId) return json(401, { error: "invalid_access_token" });

  let targets: ApnsTarget[];
  try {
    targets = await deps.liveTokens(userId);
  } catch {
    return json(500, { error: "tokens_unavailable" });
  }
  if (targets.length === 0) return json(404, { error: "no_tokens" });

  const sendDeps: ApnsSendDeps = {
    config: deps.config,
    disableToken: deps.disableToken,
    fetch: deps.fetch,
    log: deps.log,
  };
  const outcomes = deps.send
    ? await deps.send(targets, sendDeps)
    : await sendApnsToAll(targets, SELFTEST_MESSAGE, sendDeps);
  return json(200, { devices: targets.length, ...summarizeOutcomes(outcomes) });
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
