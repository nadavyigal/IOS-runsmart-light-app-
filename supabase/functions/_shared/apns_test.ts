import { assert, assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  apnsConfigFromEnv,
  type ApnsConfig,
  ApnsJwtSigner,
  type ApnsMessage,
  buildApnsPayload,
  disableTokenIn,
  liveTokensFor,
  type PushTokenStore,
  resetSharedApnsSigners,
  sendApns,
  sendApnsToAll,
  sharedApnsSigner,
  summarizeOutcomes,
} from "./apns.ts";

// C7.10 AC6: APNs is mocked. No request leaves the test.

const TOKEN = "ab".repeat(32);
const TOKEN_2 = "cd".repeat(32);

async function testKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const body = btoa(binary).match(/.{1,64}/g)!.join("\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`, publicKey: pair.publicKey };
}

async function testConfig(): Promise<{ config: ApnsConfig; publicKey: CryptoKey }> {
  const { pem, publicKey } = await testKey();
  return { config: { keyId: "KEY1234567", teamId: "TEAM123456", privateKey: pem, bundleId: "com.runsmart.lite" }, publicKey };
}

const message: ApnsMessage = {
  kind: "coachRunFinished",
  body: "Dana finished a 5 km run",
  target: { athlete_id: "BBBBBBBB-0000-4000-8000-00000000000B", day: "2026-11-23", run_id: "42" },
};

interface Call {
  url: string;
  headers: Record<string, string>;
  body: string;
}

/** A fake APNs: answers each request with the next scripted response. */
function fakeApns(script: Array<{ status: number; reason?: string } | "network_error">) {
  const calls: Call[] = [];
  const fetchImpl = (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    calls.push({
      url: String(input),
      headers: Object.fromEntries(Object.entries((init?.headers ?? {}) as Record<string, string>)),
      body: String(init?.body ?? ""),
    });
    const step = script.shift();
    if (!step) return Promise.reject(new Error("unexpected extra request"));
    if (step === "network_error") return Promise.reject(new TypeError(`connection reset for ${String(input)}`));
    const body = step.reason ? JSON.stringify({ reason: step.reason }) : "";
    return Promise.resolve(new Response(body || null, { status: step.status, headers: { "apns-id": "apns-uuid-1" } }));
  };
  return { calls, fetch: fetchImpl as typeof fetch };
}

function harness(config: ApnsConfig, script: Parameters<typeof fakeApns>[0]) {
  const apns = fakeApns(script);
  const disabled: string[] = [];
  const logs: Record<string, unknown>[] = [];
  const sleeps: number[] = [];
  return {
    apns,
    disabled,
    logs,
    sleeps,
    deps: {
      config,
      fetch: apns.fetch,
      disableToken: (token: string) => {
        disabled.push(token);
        return Promise.resolve();
      },
      log: (line: Record<string, unknown>) => logs.push(line),
      sleep: (ms: number) => {
        sleeps.push(ms);
        return Promise.resolve();
      },
      now: () => Date.UTC(2026, 10, 23, 10, 0, 0),
    },
  };
}

function decodePart(part: string): Record<string, unknown> {
  const padded = part.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (part.length % 4)) % 4);
  return JSON.parse(atob(padded));
}

// Config ------------------------------------------------------------------------------

Deno.test("config: all four secrets are required", () => {
  const env: Record<string, string> = {
    APNS_KEY_ID: "KEY1234567",
    APNS_TEAM_ID: "TEAM123456",
    APNS_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----",
    APNS_BUNDLE_ID: "com.runsmart.lite",
  };
  const config = apnsConfigFromEnv((key) => env[key]);
  assertEquals(config?.privateKey, "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----");
  for (const key of Object.keys(env)) {
    const missing = { ...env, [key]: "  " };
    assertEquals(apnsConfigFromEnv((k) => missing[k]), null, `${key} missing`);
  }
});

// Provider token ------------------------------------------------------------------------

Deno.test("JWT: ES256 header and claims, a valid signature, cached for 50 minutes", async () => {
  const { config, publicKey } = await testConfig();
  let nowMs = Date.UTC(2026, 10, 23, 10, 0, 0);
  const signer = new ApnsJwtSigner(config, () => nowMs);
  const jwt = await signer.token();
  const [header, claims, signature] = jwt.split(".");
  assertEquals(decodePart(header), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(decodePart(claims), { iss: "TEAM123456", iat: Math.floor(nowMs / 1000) });

  const sigPadded = signature.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (signature.length % 4)) % 4);
  const sigBytes = Uint8Array.from(atob(sigPadded), (c) => c.charCodeAt(0));
  assertEquals(sigBytes.length, 64);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    sigBytes,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert(valid, "signature verifies with the public key");

  nowMs += 49 * 60 * 1000;
  assertEquals(await signer.token(), jwt, "reused inside 50 minutes");
  nowMs += 2 * 60 * 1000;
  assert((await signer.token()) !== jwt, "re-signed after 50 minutes");
});

Deno.test("JWT: a key that does not import is not cached as a failure forever", async () => {
  const { config } = await testConfig();
  const signer = new ApnsJwtSigner({ ...config, privateKey: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----" });
  await assertRejects(() => signer.token());
  await assertRejects(() => signer.token());
});

// Payload -------------------------------------------------------------------------------

Deno.test("payload: alert plus rs { v, kind, ids }, ids lowercased", () => {
  const payload = JSON.parse(buildApnsPayload({ ...message, title: "RunSmart" }));
  assertEquals(payload, {
    aps: { alert: { body: "Dana finished a 5 km run", title: "RunSmart" }, sound: "default", "thread-id": "coachRunFinished" },
    rs: { v: 1, kind: "coachRunFinished", athlete_id: "bbbbbbbb-0000-4000-8000-00000000000b", day: "2026-11-23", run_id: "42" },
  });
});

Deno.test("payload: free text, unknown keys and unknown kinds are refused (push AC: no note or flag text)", () => {
  assertThrows(() => buildApnsPayload({ ...message, target: { day: "knee hurts" } }), Error, "bad_target_value:day");
  assertThrows(
    () => buildApnsPayload({ ...message, target: { note: "x" } as unknown as ApnsMessage["target"] }),
    Error,
    "bad_target_key:note",
  );
  assertThrows(() => buildApnsPayload({ ...message, kind: "painDetails" as ApnsMessage["kind"] }), Error, "unknown_kind");
  assertThrows(() => buildApnsPayload({ ...message, body: "   " }), Error, "empty_body");
  assertThrows(() => buildApnsPayload({ ...message, body: "x".repeat(5000) }), Error, "payload_too_large");
});

// Send ----------------------------------------------------------------------------------

Deno.test("200: sent once to the host that matches the token's environment", async () => {
  const { config } = await testConfig();
  for (const [environment, host] of [["sandbox", "https://api.sandbox.push.apple.com"], ["production", "https://api.push.apple.com"]] as const) {
    const h = harness(config, [{ status: 200 }]);
    const outcome = await sendApns({ token: TOKEN, environment }, message, h.deps);
    assertEquals(outcome, { status: "sent", apnsId: "apns-uuid-1" });
    assertEquals(h.apns.calls.length, 1);
    const call = h.apns.calls[0];
    assertEquals(call.url, `${host}/3/device/${TOKEN}`);
    assertEquals(call.headers["apns-topic"], "com.runsmart.lite");
    assertEquals(call.headers["apns-push-type"], "alert");
    assertEquals(call.headers["apns-priority"], "10");
    assertEquals(call.headers["apns-expiration"], String(Date.UTC(2026, 10, 23, 10, 0, 0) / 1000 + 86400));
    assert(call.headers.authorization.startsWith("bearer "));
    assertEquals(JSON.parse(call.body).rs.kind, "coachRunFinished");
    assertEquals(h.disabled, []);
  }
});

Deno.test("AC6: 410 sets disabled_at on that token and is not retried", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 410, reason: "Unregistered" }]);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  assertEquals(outcome, { status: "disabled", reason: "Unregistered" });
  assertEquals(h.disabled, [TOKEN]);
  assertEquals(h.apns.calls.length, 1);
  assertEquals(h.logs.at(-1)?.event, "apns_token_disabled");
});

Deno.test("AC6: 410 whose disable write fails is logged, not thrown", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 410, reason: "Unregistered" }]);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, {
    ...h.deps,
    disableToken: () => Promise.reject(new Error("db down")),
  });
  assertEquals(outcome.status, "disabled");
  assertEquals(h.logs.at(-1)?.event, "apns_disable_failed");
});

Deno.test("AC6: 400 is logged and not retried; the token stays live", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 400, reason: "BadDeviceToken" }]);
  const outcome = await sendApns({ token: TOKEN, environment: "sandbox" }, message, h.deps);
  assertEquals(outcome, { status: "rejected", httpStatus: 400, reason: "BadDeviceToken" });
  assertEquals(h.apns.calls.length, 1);
  assertEquals(h.disabled, []);
  assertEquals(h.sleeps, []);
  assertEquals(h.logs.at(-1)?.event, "apns_rejected");
  assertEquals(h.logs.at(-1)?.status, 400);
});

Deno.test("AC6: 403 is logged and not retried; an expired provider token is re-signed next time", async () => {
  const { config } = await testConfig();
  let nowMs = Date.UTC(2026, 10, 23, 10, 0, 0);
  const signer = new ApnsJwtSigner(config, () => nowMs);
  const h = harness(config, [{ status: 403, reason: "ExpiredProviderToken" }, { status: 200 }]);
  const first = await sendApns({ token: TOKEN, environment: "production" }, message, { ...h.deps, signer });
  assertEquals(first, { status: "rejected", httpStatus: 403, reason: "ExpiredProviderToken" });
  assertEquals(h.apns.calls.length, 1);
  nowMs += 1000;
  await sendApns({ token: TOKEN, environment: "production" }, message, { ...h.deps, signer });
  assert(h.apns.calls[0].headers.authorization !== h.apns.calls[1].headers.authorization, "new JWT after 403");
});

Deno.test("AC6: 5xx is retried once, then succeeds", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 503, reason: "ServiceUnavailable" }, { status: 200 }]);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  assertEquals(outcome.status, "sent");
  assertEquals(h.apns.calls.length, 2);
  assertEquals(h.sleeps, [500]);
  assertEquals(h.logs.map((l) => l.event), ["apns_retry", "apns_sent"]);
});

Deno.test("AC6: 5xx twice fails after exactly one retry", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 500, reason: "InternalServerError" }, { status: 500, reason: "InternalServerError" }]);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  assertEquals(outcome, { status: "failed", httpStatus: 500, reason: "InternalServerError" });
  assertEquals(h.apns.calls.length, 2);
  assertEquals(h.disabled, []);
});

Deno.test("AC6: a 5xx then a 410 disables the token", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 502 }, { status: 410, reason: "Unregistered" }]);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  assertEquals(outcome.status, "disabled");
  assertEquals(h.disabled, [TOKEN]);
});

Deno.test("a network error counts as 5xx: one retry, and the error text (with the URL) is never logged", async () => {
  const { config } = await testConfig();
  const h = harness(config, ["network_error", "network_error"]);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  assertEquals(outcome, { status: "failed", httpStatus: null, reason: "network_error" });
  assertEquals(h.apns.calls.length, 2);
  assert(!JSON.stringify(h.logs).includes(TOKEN), "full token never logged");
});

Deno.test("429 and other 4xx are not retried", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 429, reason: "TooManyRequests" }]);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  assertEquals(outcome.status, "rejected");
  assertEquals(h.apns.calls.length, 1);
});

Deno.test("logs carry no alert text and only the token's last 6 characters", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 503 }, { status: 410, reason: "Unregistered" }]);
  await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  const text = JSON.stringify(h.logs);
  assert(!text.includes("Dana"), "no alert text");
  assert(!text.includes(TOKEN), "no full token");
  assertEquals(h.logs[0].token_suffix, TOKEN.slice(-6));
});

Deno.test("a malformed token or environment is refused before any request", async () => {
  const { config } = await testConfig();
  const h = harness(config, []);
  assertEquals(
    (await sendApns({ token: "../../3/device/x", environment: "production" }, message, h.deps)).status,
    "rejected",
  );
  assertEquals(
    (await sendApns({ token: TOKEN, environment: "staging" as "production" }, message, h.deps)).status,
    "rejected",
  );
  assertEquals(h.apns.calls.length, 0);
});

Deno.test("a bad signing key fails without a retry or a request", async () => {
  const { config } = await testConfig();
  const h = harness({ ...config, privateKey: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----" }, []);
  const outcome = await sendApns({ token: TOKEN, environment: "production" }, message, h.deps);
  assertEquals(outcome, { status: "failed", httpStatus: null, reason: "bad_signing_key" });
  assertEquals(h.apns.calls.length, 0);
});

Deno.test("AC5: two devices get one push each, with one shared JWT", async () => {
  const { config } = await testConfig();
  const h = harness(config, [{ status: 200 }, { status: 410, reason: "Unregistered" }]);
  const outcomes = await sendApnsToAll(
    [{ token: TOKEN, environment: "production" }, { token: TOKEN_2, environment: "sandbox" }],
    message,
    h.deps,
  );
  assertEquals(summarizeOutcomes(outcomes), { sent: 1, disabled: 1, rejected: 0, failed: 0 });
  assertEquals(h.apns.calls.length, 2);
  assertEquals(h.apns.calls[0].headers.authorization, h.apns.calls[1].headers.authorization);
  assertEquals(h.disabled.length, 1);
});

// Shared signer across invocations ------------------------------------------------------
// Apple answers 429 TooManyProviderTokenUpdates when the provider token changes more often
// than every 20 minutes, so separate invocations in one isolate must reuse one JWT.

/** Counts real ECDSA signings while `body` runs. */
async function countingSigns<T>(body: () => Promise<T>): Promise<{ result: T; signs: number }> {
  const subtle = crypto.subtle as SubtleCrypto & { sign: SubtleCrypto["sign"] };
  const original = subtle.sign;
  let signs = 0;
  subtle.sign = ((...args: Parameters<SubtleCrypto["sign"]>) => {
    signs++;
    return original.apply(subtle, args);
  }) as SubtleCrypto["sign"];
  try {
    return { result: await body(), signs };
  } finally {
    subtle.sign = original;
  }
}

function iatOf(authorization: string): number {
  const jwt = authorization.replace(/^bearer /, "");
  return decodePart(jwt.split(".")[1]).iat as number;
}

const TWO_DEVICES = [
  { token: TOKEN, environment: "production" as const },
  { token: TOKEN_2, environment: "production" as const },
];

Deno.test("shared signer: two sendApnsToAll calls within 50 minutes sign once", async () => {
  resetSharedApnsSigners();
  const { config } = await testConfig();
  let nowMs = Date.UTC(2026, 10, 23, 10, 0, 0);
  const firstIat = Math.floor(nowMs / 1000);
  const h = harness(config, [{ status: 200 }, { status: 200 }, { status: 200 }, { status: 200 }]);
  const deps = { ...h.deps, now: () => nowMs };
  const { signs } = await countingSigns(async () => {
    await sendApnsToAll(TWO_DEVICES, message, deps);
    nowMs += 40 * 60 * 1000;
    // A second invocation: a fresh deps object, as a new request would build.
    await sendApnsToAll(TWO_DEVICES, message, { ...deps });
  });
  assertEquals(signs, 1, "one signing for two invocations and four sends");
  assertEquals(h.apns.calls.length, 4);
  assertEquals(new Set(h.apns.calls.map((call) => call.headers.authorization)).size, 1);
  assertEquals(iatOf(h.apns.calls[3].headers.authorization), firstIat);
  resetSharedApnsSigners();
});

Deno.test("shared signer: after a 403 ExpiredProviderToken the next call signs a new JWT", async () => {
  resetSharedApnsSigners();
  const { config } = await testConfig();
  let nowMs = Date.UTC(2026, 10, 23, 10, 0, 0);
  const h = harness(config, [{ status: 403, reason: "ExpiredProviderToken" }, { status: 200 }]);
  const deps = { ...h.deps, now: () => nowMs };
  const { signs } = await countingSigns(async () => {
    const first = await sendApnsToAll([TWO_DEVICES[0]], message, deps);
    assertEquals(first, [{ status: "rejected", httpStatus: 403, reason: "ExpiredProviderToken" }]);
    nowMs += 60 * 1000;
    await sendApnsToAll([TWO_DEVICES[0]], message, { ...deps });
  });
  assertEquals(signs, 2);
  assert(h.apns.calls[0].headers.authorization !== h.apns.calls[1].headers.authorization);
  assertEquals(iatOf(h.apns.calls[1].headers.authorization), Math.floor(nowMs / 1000));
  resetSharedApnsSigners();
});

Deno.test("shared signer: one per key id and team, replaced when the private key changes", async () => {
  resetSharedApnsSigners();
  const { config } = await testConfig();
  const { config: rotated } = await testConfig();
  const signer = sharedApnsSigner(config);
  assert(sharedApnsSigner({ ...config }) === signer, "same key: same signer");
  assert(sharedApnsSigner({ ...config, bundleId: "other" }) === signer, "the topic is not part of the JWT");
  const afterRotation = sharedApnsSigner({ ...config, privateKey: rotated.privateKey });
  assert(afterRotation !== signer, "a rotated key gets a new signer");
  assert(sharedApnsSigner({ ...config, keyId: "KEY7654321" }) !== afterRotation, "another key id");
  resetSharedApnsSigners();
});

// Token store ---------------------------------------------------------------------------

function fakeStore(rows: unknown[], error: unknown = null) {
  const queries: string[] = [];
  const updates: Array<{ values: unknown; token: string }> = [];
  const store: PushTokenStore = {
    from: (table) => {
      queries.push(table);
      return {
        select: (columns) => ({
          eq: (column, value) => ({
            is: (nullColumn) => {
              queries.push(`${columns}|${column}=${value}|${nullColumn} is null`);
              return Promise.resolve({ data: rows, error });
            },
          }),
        }),
        update: (values) => ({
          eq: (_column, token) => {
            updates.push({ values, token });
            return Promise.resolve({ error });
          },
        }),
      };
    },
  };
  return { store, queries, updates };
}

Deno.test("liveTokensFor reads only live rows and skips malformed ones", async () => {
  const { store, queries } = fakeStore([
    { token: TOKEN, environment: "production" },
    { token: TOKEN_2, environment: "sandbox" },
    { token: 7, environment: "sandbox" },
    { token: TOKEN, environment: "staging" },
  ]);
  const targets = await liveTokensFor(store, "aaaaaaaa-0000-4000-8000-00000000000a");
  assertEquals(targets, [{ token: TOKEN, environment: "production" }, { token: TOKEN_2, environment: "sandbox" }]);
  assertEquals(queries[1], "token, environment|user_id=aaaaaaaa-0000-4000-8000-00000000000a|disabled_at is null");
});

Deno.test("disableTokenIn writes disabled_at for that token only", async () => {
  const { store, updates } = fakeStore([]);
  await disableTokenIn(store, () => new Date("2026-11-23T10:00:00Z"))(TOKEN);
  assertEquals(updates, [{ values: { disabled_at: "2026-11-23T10:00:00.000Z" }, token: TOKEN }]);
  const failing = fakeStore([], { message: "denied" });
  await assertRejects(() => disableTokenIn(failing.store)(TOKEN), Error, "push_tokens_disable_failed");
});
