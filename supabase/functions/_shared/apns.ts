// APNs sender for Coach Experience v2 (story C7.10). Every push sender uses it:
// push_selftest now, coach_notify (C7.5) and the later digests through
// _shared/notify.ts.
//
// Secrets come from the environment only, never from code or a request:
//   APNS_KEY_ID       the Auth Key id (10 characters)
//   APNS_TEAM_ID      the Apple Developer team id
//   APNS_PRIVATE_KEY  the .p8 file's contents (PEM, "\n" escapes are accepted)
//   APNS_BUNDLE_ID    the app's bundle id, sent as apns-topic
// Nadav sets them as Edge Function secrets. Agents never handle the key.
//
// The provider token is an ES256 JWT signed with WebCrypto (no dependency). It is
// cached for 50 minutes: Apple rejects tokens older than an hour and answers 429
// TooManyProviderTokenUpdates when the token changes more often than every 20
// minutes. So one signer per key lives at module level and is reused by every
// invocation in the same isolate (sharedApnsSigner). Deno's fetch speaks HTTP/2
// to APNs.
//
// Each token row carries its environment: 'sandbox' tokens (Debug builds) go to
// api.sandbox.push.apple.com, 'production' tokens (TestFlight, App Store) to
// api.push.apple.com.
//
// Response policy (C7.10 AC6):
//   200        sent.
//   410        the token is gone: disableToken(token) sets push_tokens.disabled_at.
//   400, 403   logged, not retried. A 403 for an expired or invalid provider token
//              also drops the cached JWT so the next send signs a new one.
//   5xx        retried once [ASSUMPTION, v1.3 §7.5]. A network error counts as 5xx.
//   other 4xx  logged, not retried (404 bad path, 413 too large, 429 too many).
//
// Logs never carry the alert text or the full token: only the kind, the status,
// Apple's reason and the token's last 6 characters.
//
// Payload: aps.alert plus one custom object "rs" that the app's push router
// reads (C7.10 AC8, §3.5): { v: 1, kind, ...target ids }. Target values must be
// ids (uuid, digits) or yyyy-MM-dd days. Free text is refused, so no note, flag
// or reply text can travel in the custom data.

export type PushEnvironment = "sandbox" | "production";

export const APNS_HOSTS: Record<PushEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

/** §3.5 kinds, plus selfTest for push_selftest. The app's router knows each one. */
export const REMOTE_PUSH_KINDS = [
  "coachRunFinished",
  "coachEveningSummary",
  "coachPainFlag",
  "athleteCoachNote",
  "athleteCoachReply",
  "athletePlanPublished",
  "athletePlanUpdated",
  "athleteBroadcast",
  "selfTest",
] as const;
export type RemotePushKind = typeof REMOTE_PUSH_KINDS[number];

/** Ids the router may need. Anything else is refused. */
export const REMOTE_PUSH_TARGET_KEYS = [
  "athlete_id",
  "coach_id",
  "day",
  "run_id",
  "flag_id",
  "feedback_id",
  "workout_id",
  "plan_id",
] as const;
export type RemotePushTargetKey = typeof REMOTE_PUSH_TARGET_KEYS[number];

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  privateKey: string;
  bundleId: string;
}

export interface ApnsTarget {
  token: string;
  environment: PushEnvironment;
}

export interface ApnsMessage {
  kind: RemotePushKind;
  title?: string;
  body: string;
  target?: Partial<Record<RemotePushTargetKey, string>>;
  /** apns-collapse-id: a newer push with the same id replaces the older one. */
  collapseId?: string;
  /** Seconds APNs keeps trying an offline device. Default 24 hours. */
  ttlSeconds?: number;
}

export type ApnsOutcome =
  | { status: "sent"; apnsId: string | null }
  | { status: "disabled"; reason: string }
  | { status: "rejected"; httpStatus: number; reason: string }
  | { status: "failed"; httpStatus: number | null; reason: string };

export type ApnsLogger = (line: Record<string, unknown>) => void;

export interface ApnsSendDeps {
  config: ApnsConfig;
  /** Sets push_tokens.disabled_at for this token (410). */
  disableToken: (token: string) => Promise<void>;
  signer?: ApnsJwtSigner;
  fetch?: typeof fetch;
  log?: ApnsLogger;
  /** The wait before the one 5xx retry. */
  sleep?: (ms: number) => Promise<void>;
  now?: () => number;
}

const MAX_PAYLOAD_BYTES = 4096;
const JWT_REUSE_MS = 50 * 60 * 1000;
const RETRY_DELAY_MS = 500;
const DEFAULT_TTL_SECONDS = 24 * 60 * 60;

const defaultLogger: ApnsLogger = (line) => console.log(JSON.stringify(line));

// Config -------------------------------------------------------------------------

/** Reads the four secrets. Null when any is missing: the caller must not send. */
export function apnsConfigFromEnv(
  get: (key: string) => string | undefined = (key) => Deno.env.get(key),
): ApnsConfig | null {
  const keyId = get("APNS_KEY_ID")?.trim();
  const teamId = get("APNS_TEAM_ID")?.trim();
  const privateKey = get("APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n").trim();
  const bundleId = get("APNS_BUNDLE_ID")?.trim();
  if (!keyId || !teamId || !privateKey || !bundleId) return null;
  return { keyId, teamId, privateKey, bundleId };
}

// Provider token -----------------------------------------------------------------

export class ApnsJwtSigner {
  private key: Promise<CryptoKey> | null = null;
  private cached: { jwt: string; issuedAtMs: number } | null = null;
  /** A signing in progress. Concurrent sends wait for it instead of signing again. */
  private pending: Promise<string> | null = null;

  constructor(
    private readonly config: ApnsConfig,
    private readonly now: () => number = () => Date.now(),
  ) {}

  async token(): Promise<string> {
    const nowMs = this.now();
    if (this.cached && nowMs - this.cached.issuedAtMs < JWT_REUSE_MS && nowMs >= this.cached.issuedAtMs) {
      return this.cached.jwt;
    }
    if (!this.pending) {
      const signing: Promise<string> = this.sign(nowMs)
        .then((jwt) => {
          // An invalidate() during the signing drops this result.
          if (this.pending === signing) this.cached = { jwt, issuedAtMs: nowMs };
          return jwt;
        })
        .finally(() => {
          if (this.pending === signing) this.pending = null;
        });
      this.pending = signing;
    }
    return await this.pending;
  }

  /** Drops the cached JWT, after APNs said it is expired or invalid. */
  invalidate(): void {
    this.cached = null;
    this.pending = null;
  }

  private async sign(nowMs: number): Promise<string> {
    const header = { alg: "ES256", kid: this.config.keyId };
    const claims = { iss: this.config.teamId, iat: Math.floor(nowMs / 1000) };
    const signingInput = `${base64UrlJson(header)}.${base64UrlJson(claims)}`;
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      await this.signingKey(),
      new TextEncoder().encode(signingInput),
    );
    return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
  }

  private signingKey(): Promise<CryptoKey> {
    if (!this.key) {
      this.key = crypto.subtle.importKey(
        "pkcs8",
        pemToDer(this.config.privateKey),
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["sign"],
      );
      // A bad key must not stay cached as a rejected promise.
      this.key.catch(() => {
        this.key = null;
      });
    }
    return this.key;
  }
}

/** One signer per `${keyId}:${teamId}`, kept for the life of the isolate. */
const sharedSigners = new Map<string, { privateKey: string; signer: ApnsJwtSigner }>();

/**
 * The signer every send uses unless a test passes its own. Reusing it across invocations
 * keeps the provider token stable for 50 minutes (Apple's 429 TooManyProviderTokenUpdates).
 * A changed private key (a rotated secret) replaces the signer. `now` is used only when the
 * signer is created.
 */
export function sharedApnsSigner(config: ApnsConfig, now?: () => number): ApnsJwtSigner {
  const cacheKey = `${config.keyId}:${config.teamId}`;
  const entry = sharedSigners.get(cacheKey);
  if (entry && entry.privateKey === config.privateKey) return entry.signer;
  const signer = new ApnsJwtSigner(config, now);
  sharedSigners.set(cacheKey, { privateKey: config.privateKey, signer });
  return signer;
}

/** Tests only: forget every shared signer. */
export function resetSharedApnsSigners(): void {
  sharedSigners.clear();
}

// Payload ------------------------------------------------------------------------

const TARGET_VALUE = /^(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|\d{1,19}|\d{4}-\d{2}-\d{2})$/;

/** Builds the JSON body. Throws on an unknown kind, a non-id target value or an oversize payload. */
export function buildApnsPayload(message: ApnsMessage): string {
  if (!(REMOTE_PUSH_KINDS as readonly string[]).includes(message.kind)) {
    throw new Error("unknown_kind");
  }
  const body = message.body.trim();
  if (!body) throw new Error("empty_body");

  const rs: Record<string, string | number> = { v: 1, kind: message.kind };
  for (const [key, value] of Object.entries(message.target ?? {})) {
    if (value === undefined) continue;
    if (!(REMOTE_PUSH_TARGET_KEYS as readonly string[]).includes(key)) {
      throw new Error(`bad_target_key:${key}`);
    }
    if (typeof value !== "string" || !TARGET_VALUE.test(value)) {
      throw new Error(`bad_target_value:${key}`);
    }
    rs[key] = value.toLowerCase();
  }

  const alert: Record<string, string> = { body };
  const title = message.title?.trim();
  if (title) alert.title = title;

  const payload = JSON.stringify({
    aps: { alert, sound: "default", "thread-id": message.kind },
    rs,
  });
  if (new TextEncoder().encode(payload).length > MAX_PAYLOAD_BYTES) {
    throw new Error("payload_too_large");
  }
  return payload;
}

// Send ---------------------------------------------------------------------------

/** Sends one push to one device. Never throws for an APNs answer or a network error. */
export async function sendApns(
  target: ApnsTarget,
  message: ApnsMessage,
  deps: ApnsSendDeps,
): Promise<ApnsOutcome> {
  const log = deps.log ?? defaultLogger;
  const doFetch = deps.fetch ?? fetch;
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  const now = deps.now ?? (() => Date.now());
  const signer = deps.signer ?? sharedApnsSigner(deps.config, now);
  const base = { event: "", kind: message.kind, environment: target.environment, token_suffix: tokenSuffix(target.token) };

  const host = APNS_HOSTS[target.environment];
  if (!host) {
    log({ ...base, event: "apns_rejected", reason: "bad_environment" });
    return { status: "rejected", httpStatus: 0, reason: "bad_environment" };
  }
  // The token goes into the URL path, so only the shape push_tokens allows is sent.
  if (!/^[0-9a-f]{64,200}$/.test(target.token)) {
    log({ ...base, event: "apns_rejected", reason: "bad_token" });
    return { status: "rejected", httpStatus: 0, reason: "bad_token" };
  }
  const payload = buildApnsPayload(message);

  for (let attempt = 1; attempt <= 2; attempt++) {
    let jwt: string;
    try {
      jwt = await signer.token();
    } catch {
      // A key that does not import or sign. Not a network problem: no retry.
      log({ ...base, event: "apns_failed", attempt, reason: "bad_signing_key" });
      return { status: "failed", httpStatus: null, reason: "bad_signing_key" };
    }
    let response: Response;
    try {
      const headers: Record<string, string> = {
        authorization: `bearer ${jwt}`,
        "apns-topic": deps.config.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(now() / 1000) + (message.ttlSeconds ?? DEFAULT_TTL_SECONDS)),
        "content-type": "application/json",
      };
      if (message.collapseId) headers["apns-collapse-id"] = message.collapseId.slice(0, 64);
      response = await doFetch(`${host}/3/device/${target.token}`, { method: "POST", headers, body: payload });
    } catch {
      // The error text can carry the URL, and so the token: it is not logged.
      if (attempt === 1) {
        log({ ...base, event: "apns_retry", attempt, reason: "network_error" });
        await sleep(RETRY_DELAY_MS);
        continue;
      }
      log({ ...base, event: "apns_failed", attempt, reason: "network_error" });
      return { status: "failed", httpStatus: null, reason: "network_error" };
    }

    const status = response.status;
    if (status === 200) {
      await response.body?.cancel();
      log({ ...base, event: "apns_sent", attempt });
      return { status: "sent", apnsId: response.headers.get("apns-id") };
    }

    const reason = await readReason(response);
    if (status === 410) {
      try {
        await deps.disableToken(target.token);
        log({ ...base, event: "apns_token_disabled", status, reason });
      } catch (error) {
        log({ ...base, event: "apns_disable_failed", status, reason, detail: describe(error) });
      }
      return { status: "disabled", reason };
    }
    if (status >= 500 && attempt === 1) {
      log({ ...base, event: "apns_retry", attempt, status, reason });
      await sleep(RETRY_DELAY_MS);
      continue;
    }
    if (status >= 500) {
      log({ ...base, event: "apns_failed", attempt, status, reason });
      return { status: "failed", httpStatus: status, reason };
    }
    if (status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken")) {
      signer.invalidate();
    }
    log({ ...base, event: "apns_rejected", attempt, status, reason });
    return { status: "rejected", httpStatus: status, reason };
  }
  // Unreachable: the loop returns on the second attempt.
  return { status: "failed", httpStatus: null, reason: "unreachable" };
}

/** Sends to every device of one user. All sends share one signer, so the JWT is signed once. */
export async function sendApnsToAll(
  targets: readonly ApnsTarget[],
  message: ApnsMessage,
  deps: ApnsSendDeps,
): Promise<ApnsOutcome[]> {
  const shared: ApnsSendDeps = { ...deps, signer: deps.signer ?? sharedApnsSigner(deps.config, deps.now) };
  return await Promise.all(targets.map((target) => sendApns(target, message, shared)));
}

export function summarizeOutcomes(outcomes: readonly ApnsOutcome[]): Record<ApnsOutcome["status"], number> {
  const counts = { sent: 0, disabled: 0, rejected: 0, failed: 0 };
  for (const outcome of outcomes) counts[outcome.status] += 1;
  return counts;
}

// Token store ---------------------------------------------------------------------

/** The slice of a service-role supabase-js client the token helpers use. */
export interface PushTokenStore {
  from(table: "push_tokens"): {
    select(columns: string): {
      eq(column: "user_id", value: string): {
        is(column: "disabled_at", value: null): PromiseLike<{ data: unknown; error: unknown }>;
      };
    };
    update(values: { disabled_at: string }): {
      eq(column: "token", value: string): PromiseLike<{ error: unknown }>;
    };
  };
}

/** A user's live device tokens (disabled_at is null). */
export async function liveTokensFor(store: PushTokenStore, userId: string): Promise<ApnsTarget[]> {
  const { data, error } = await store.from("push_tokens").select("token, environment").eq("user_id", userId).is(
    "disabled_at",
    null,
  );
  if (error) throw new Error(`push_tokens_read_failed: ${describe(error)}`);
  if (!Array.isArray(data)) return [];
  const targets: ApnsTarget[] = [];
  for (const row of data) {
    const { token, environment } = (row ?? {}) as { token?: unknown; environment?: unknown };
    if (typeof token === "string" && (environment === "sandbox" || environment === "production")) {
      targets.push({ token, environment });
    }
  }
  return targets;
}

/** disableToken for ApnsSendDeps, backed by push_tokens. */
export function disableTokenIn(store: PushTokenStore, now: () => Date = () => new Date()) {
  return async (token: string): Promise<void> => {
    const { error } = await store.from("push_tokens").update({ disabled_at: now().toISOString() }).eq("token", token);
    if (error) throw new Error(`push_tokens_disable_failed: ${describe(error)}`);
  };
}

// Helpers ------------------------------------------------------------------------

async function readReason(response: Response): Promise<string> {
  try {
    const text = await response.text();
    if (!text) return "none";
    const parsed = JSON.parse(text) as { reason?: unknown };
    return typeof parsed.reason === "string" ? parsed.reason.slice(0, 64) : "none";
  } catch {
    return "unreadable";
  }
}

function tokenSuffix(token: string): string {
  return token.slice(-6);
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function describe(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) {
    return String((error as { message: unknown }).message);
  }
  return String(error);
}
