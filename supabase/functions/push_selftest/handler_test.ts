import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { ApnsConfig, ApnsTarget } from "../_shared/apns.ts";
import { handleSelftest, SELFTEST_MESSAGE, type SelftestDeps } from "./handler.ts";

// C7.10 AC7: push_selftest sends one fixed push to the caller's own devices, is off
// unless PUSH_SELFTEST_ENABLED is "true", and is in no deploy script.
//
// Run: deno test --allow-read supabase/functions
// (the deploy-script check reads scripts/ and .github/workflows/).

const TOKEN = "ab".repeat(32);
const config: ApnsConfig = { keyId: "K", teamId: "T", privateKey: "unused", bundleId: "com.runsmart.lite" };

function deps(overrides: Partial<SelftestDeps> = {}) {
  const sent: Array<{ targets: readonly ApnsTarget[] }> = [];
  const base: SelftestDeps = {
    enabled: true,
    config,
    userIdFor: (accessToken) => Promise.resolve(accessToken === "good" ? "user-a" : null),
    liveTokens: (userId) => Promise.resolve(userId === "user-a" ? [{ token: TOKEN, environment: "production" }] : []),
    disableToken: () => Promise.resolve(),
    send: (targets) => {
      sent.push({ targets });
      return Promise.resolve(targets.map(() => ({ status: "sent" as const, apnsId: null })));
    },
    ...overrides,
  };
  return { deps: base, sent };
}

function post(token?: string, body = "{}"): Request {
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request("http://localhost/push_selftest", { method: "POST", headers, body });
}

Deno.test("off unless PUSH_SELFTEST_ENABLED is true: 404 and nothing sent", async () => {
  const { deps: d, sent } = deps({ enabled: false });
  const response = await handleSelftest(post("good"), d);
  assertEquals(response.status, 404);
  assertEquals(sent.length, 0);
});

Deno.test("AC7: the caller's own devices get the fixed test push", async () => {
  const { deps: d, sent } = deps();
  // A user id or text in the body is ignored.
  const response = await handleSelftest(post("good", JSON.stringify({ user_id: "user-b", body: "hi" })), d);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { devices: 1, sent: 1, disabled: 0, rejected: 0, failed: 0 });
  assertEquals(sent[0].targets, [{ token: TOKEN, environment: "production" }]);
  assertEquals(SELFTEST_MESSAGE.kind, "selfTest");
});

Deno.test("no or bad access token: 401, nothing sent", async () => {
  for (const token of [undefined, "bad"]) {
    const { deps: d, sent } = deps();
    const response = await handleSelftest(post(token), d);
    assertEquals(response.status, 401);
    assertEquals(sent.length, 0);
  }
});

Deno.test("APNs secrets missing: 503, nothing sent", async () => {
  const { deps: d, sent } = deps({ config: null });
  assertEquals((await handleSelftest(post("good"), d)).status, 503);
  assertEquals(sent.length, 0);
});

Deno.test("no live token: 404 no_tokens", async () => {
  const { deps: d } = deps({ liveTokens: () => Promise.resolve([]) });
  const response = await handleSelftest(post("good"), d);
  assertEquals(response.status, 404);
  assertEquals((await response.json()).error, "no_tokens");
});

Deno.test("GET is refused", async () => {
  const { deps: d } = deps();
  const response = await handleSelftest(new Request("http://localhost/push_selftest"), d);
  assertEquals(response.status, 405);
});

Deno.test("AC7: push_selftest is in no deploy script or workflow", async () => {
  const root = new URL("../../../", import.meta.url);
  const offenders: string[] = [];
  for (const dir of ["scripts", ".github/workflows"]) {
    let entries: AsyncIterable<Deno.DirEntry>;
    try {
      entries = Deno.readDir(new URL(`${dir}/`, root));
    } catch {
      continue;
    }
    for await (const entry of entries) {
      if (!entry.isFile) continue;
      const text = await Deno.readTextFile(new URL(`${dir}/${entry.name}`, root));
      if (text.includes("push_selftest")) offenders.push(`${dir}/${entry.name}`);
    }
  }
  assert(offenders.length === 0, `push_selftest is referenced in: ${offenders.join(", ")}`);
});
