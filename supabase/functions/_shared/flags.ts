// Server kill switch for Coach Experience v2 (story C7.12, folded into C7.0).
//
// Every v2 Edge Function reads the flags at start and exits early when one it
// needs is off:
//
//   const skip = await exitIfFlagsOff(admin, ["coach_v2", "coach_v2_push"], "coach_notify");
//   if (skip) return skip;
//
// Flags live in public.runtime_flags and are read through get_runtime_flags()
// (migration 20261121100000_coach_v2_gate.sql). Nadav flips one with a single SQL
// update; docs/coach-v2-rollback.md has the lines.
//
// Off, the function returns 200 and logs skipped_kill_switch. It sends nothing
// and deletes nothing, so queued and deferred rows wait for the flag to return.
// If the flags cannot be read, it also sends nothing: it returns 503 and logs
// flags_unavailable, so a webhook or cron caller retries later.

export const RUNTIME_FLAG_KEYS = ["coach_v2", "coach_v2_push", "coach_v2_ai"] as const;
export type RuntimeFlagKey = typeof RUNTIME_FLAG_KEYS[number];
export type RuntimeFlags = Record<RuntimeFlagKey, boolean>;

/** The slice of a supabase-js client this helper uses. */
export interface FlagsRpcClient {
  rpc(fn: "get_runtime_flags"): PromiseLike<{ data: unknown; error: unknown }>;
}

export type FlagsLogger = (line: Record<string, unknown>) => void;

const defaultLogger: FlagsLogger = (line) => console.log(JSON.stringify(line));

export type FlagsReadResult =
  | { ok: true; flags: RuntimeFlags }
  | { ok: false; error: string };

/**
 * Reads the allow-listed flags. A key missing from the result counts as off,
 * like the SQL side (link_is_v2 treats a missing coach_v2 row as off).
 */
export async function readRuntimeFlags(client: FlagsRpcClient): Promise<FlagsReadResult> {
  let response: { data: unknown; error: unknown };
  try {
    response = await client.rpc("get_runtime_flags");
  } catch (error) {
    return { ok: false, error: describe(error) };
  }
  if (response.error) return { ok: false, error: describe(response.error) };
  if (!Array.isArray(response.data)) return { ok: false, error: "unexpected_shape" };

  const flags: RuntimeFlags = { coach_v2: false, coach_v2_push: false, coach_v2_ai: false };
  for (const row of response.data) {
    if (!row || typeof row !== "object") continue;
    const { key, enabled } = row as { key?: unknown; enabled?: unknown };
    if (typeof key === "string" && isFlagKey(key)) flags[key] = enabled === true;
  }
  return { ok: true, flags };
}

/**
 * Returns a Response the caller must return right away, or null when every
 * required flag is on.
 */
export async function exitIfFlagsOff(
  client: FlagsRpcClient,
  required: readonly RuntimeFlagKey[],
  functionName: string,
  options: { headers?: HeadersInit; log?: FlagsLogger } = {},
): Promise<Response | null> {
  const log = options.log ?? defaultLogger;
  const result = await readRuntimeFlags(client);

  if (!result.ok) {
    log({ event: "flags_unavailable", function: functionName, error: result.error });
    return json({ skipped: true, reason: "flags_unavailable" }, 503, options.headers);
  }

  const off = required.filter((key) => !result.flags[key]);
  if (off.length === 0) return null;

  log({ event: "skipped_kill_switch", function: functionName, flags_off: off });
  return json({ skipped: true, reason: "skipped_kill_switch", flags_off: off }, 200, options.headers);
}

function isFlagKey(key: string): key is RuntimeFlagKey {
  return (RUNTIME_FLAG_KEYS as readonly string[]).includes(key);
}

function describe(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) {
    return String((error as { message: unknown }).message);
  }
  return String(error);
}

function json(body: Record<string, unknown>, status: number, headers?: HeadersInit): Response {
  const merged = new Headers(headers);
  merged.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { status, headers: merged });
}
