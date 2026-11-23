import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { exitIfFlagsOff, type FlagsRpcClient, readRuntimeFlags } from "./flags.ts";

function client(data: unknown, error: unknown = null): FlagsRpcClient & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    rpc(fn) {
      calls.push(fn);
      return Promise.resolve({ data, error });
    },
  };
}

function throwingClient(): FlagsRpcClient {
  return { rpc: () => Promise.reject(new Error("network down")) };
}

const allOn = [
  { key: "coach_v2", enabled: true },
  { key: "coach_v2_ai", enabled: true },
  { key: "coach_v2_push", enabled: true },
];

function capture() {
  const lines: Record<string, unknown>[] = [];
  return { lines, log: (line: Record<string, unknown>) => lines.push(line) };
}

Deno.test("all required flags on: the function carries on", async () => {
  const c = client(allOn);
  const { lines, log } = capture();
  const skip = await exitIfFlagsOff(c, ["coach_v2", "coach_v2_push"], "coach_notify", { log });
  assertEquals(skip, null);
  assertEquals(c.calls, ["get_runtime_flags"]);
  assertEquals(lines, []);
});

Deno.test("C7.12 AC4: a flag off exits early with 200 and logs skipped_kill_switch", async () => {
  const c = client([
    { key: "coach_v2", enabled: true },
    { key: "coach_v2_push", enabled: false },
    { key: "coach_v2_ai", enabled: true },
  ]);
  const { lines, log } = capture();
  const skip = await exitIfFlagsOff(c, ["coach_v2", "coach_v2_push"], "coach_notify", { log });
  assertEquals(skip?.status, 200);
  assertEquals(await skip?.json(), {
    skipped: true,
    reason: "skipped_kill_switch",
    flags_off: ["coach_v2_push"],
  });
  assertEquals(lines, [{ event: "skipped_kill_switch", function: "coach_notify", flags_off: ["coach_v2_push"] }]);
});

Deno.test("the main switch off stops every v2 function", async () => {
  const c = client([
    { key: "coach_v2", enabled: false },
    { key: "coach_v2_push", enabled: true },
    { key: "coach_v2_ai", enabled: true },
  ]);
  const { lines, log } = capture();
  const skip = await exitIfFlagsOff(c, ["coach_v2", "coach_v2_ai"], "coach_plan_draft", { log });
  assertEquals(skip?.status, 200);
  assertEquals(lines[0].event, "skipped_kill_switch");
  assertEquals(lines[0].flags_off, ["coach_v2"]);
});

Deno.test("a flag this function does not need is ignored", async () => {
  const c = client([
    { key: "coach_v2", enabled: true },
    { key: "coach_v2_push", enabled: true },
    { key: "coach_v2_ai", enabled: false },
  ]);
  assertEquals(await exitIfFlagsOff(c, ["coach_v2", "coach_v2_push"], "coach_notify", { log: () => {} }), null);
});

Deno.test("a missing key counts as off", async () => {
  const c = client([{ key: "coach_v2", enabled: true }]);
  const { lines, log } = capture();
  const skip = await exitIfFlagsOff(c, ["coach_v2", "coach_v2_push"], "coach_notify", { log });
  assertEquals(skip?.status, 200);
  assertEquals(lines[0].flags_off, ["coach_v2_push"]);
});

Deno.test("an unreadable flag table sends nothing and asks for a retry (503)", async () => {
  for (const c of [client(null, { message: "permission denied" }), client({ not: "an array" }), throwingClient()]) {
    const { lines, log } = capture();
    const skip = await exitIfFlagsOff(c, ["coach_v2"], "coach_notify", { log });
    assertEquals(skip?.status, 503);
    assertEquals(lines[0].event, "flags_unavailable");
  }
});

Deno.test("unknown keys and non-boolean values never turn a flag on", async () => {
  const result = await readRuntimeFlags(client([
    { key: "coach_v2", enabled: "true" },
    { key: "coach_v2_push", enabled: 1 },
    { key: "internal_only", enabled: true },
    null,
  ]));
  assertEquals(result, { ok: true, flags: { coach_v2: false, coach_v2_push: false, coach_v2_ai: false } });
});

Deno.test("CORS headers pass through on the skip response", async () => {
  const c = client([{ key: "coach_v2", enabled: false }]);
  const skip = await exitIfFlagsOff(c, ["coach_v2"], "coach_notify", {
    headers: { "Access-Control-Allow-Origin": "https://runsmart.app" },
    log: () => {},
  });
  assertEquals(skip?.headers.get("Access-Control-Allow-Origin"), "https://runsmart.app");
  assertEquals(skip?.headers.get("Content-Type"), "application/json");
});
