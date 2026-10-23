import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, isOriginAllowed } from "../_shared/cors.ts";

// Strava token exchange for the iOS app. The Strava client secret lives only here.
// Validates the caller's Supabase JWT, then trades an authorization code or a refresh
// token with Strava. Tokens are returned to the app (which keeps them in the Keychain);
// they are never stored server-side and never logged.

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";
const MAX_CREDENTIAL_LENGTH = 512;

function jsonResponse(req: Request, status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

function credential(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > MAX_CREDENTIAL_LENGTH) return null;
  return trimmed;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    if (!isOriginAllowed(req)) {
      return new Response("Forbidden", { status: 403, headers: corsHeaders(req) });
    }
    return new Response("ok", { headers: corsHeaders(req) });
  }
  if (req.method !== "POST") {
    return jsonResponse(req, 405, { error: "Method not allowed" });
  }
  if (!isOriginAllowed(req)) {
    return jsonResponse(req, 403, { error: "Origin not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const clientId = Deno.env.get("STRAVA_CLIENT_ID");
  const clientSecret = Deno.env.get("STRAVA_CLIENT_SECRET");
  if (!supabaseUrl || !anonKey || !clientId || !clientSecret) {
    return jsonResponse(req, 500, { error: "Server configuration missing" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return jsonResponse(req, 401, { error: "Missing access token" });
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData?.user) {
    return jsonResponse(req, 401, { error: "Invalid or expired access token" });
  }

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    body = parsed && typeof parsed === "object" ? parsed as Record<string, unknown> : {};
  } catch {
    return jsonResponse(req, 400, { error: "Invalid JSON body" });
  }

  const form = new URLSearchParams();
  form.set("client_id", clientId);
  form.set("client_secret", clientSecret);

  if (body.action === "exchange") {
    const code = credential(body.code);
    if (!code) return jsonResponse(req, 400, { error: "Missing code" });
    form.set("grant_type", "authorization_code");
    form.set("code", code);
  } else if (body.action === "refresh") {
    const refreshToken = credential(body.refresh_token);
    if (!refreshToken) return jsonResponse(req, 400, { error: "Missing refresh_token" });
    form.set("grant_type", "refresh_token");
    form.set("refresh_token", refreshToken);
  } else {
    return jsonResponse(req, 400, { error: "Unknown action" });
  }

  let stravaResponse: Response;
  try {
    stravaResponse = await fetch(STRAVA_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
      body: form,
    });
  } catch {
    return jsonResponse(req, 502, { error: "Could not reach Strava" });
  }

  let payload: Record<string, unknown> | null = null;
  try {
    payload = await stravaResponse.json();
  } catch {
    payload = null;
  }

  if (!stravaResponse.ok || !payload || typeof payload.access_token !== "string") {
    // Strava error bodies carry no tokens, but only the status is passed on.
    const status = stravaResponse.status >= 400 && stravaResponse.status < 500 ? 400 : 502;
    return jsonResponse(req, status, { error: "Strava rejected the request", strava_status: stravaResponse.status });
  }

  const athlete = payload.athlete && typeof payload.athlete === "object"
    ? payload.athlete as Record<string, unknown>
    : null;
  const athleteName = athlete
    ? [athlete.firstname, athlete.lastname].filter((part) => typeof part === "string" && part.trim()).join(" ")
    : "";

  return jsonResponse(req, 200, {
    access_token: payload.access_token,
    refresh_token: payload.refresh_token,
    expires_at: payload.expires_at,
    athlete_id: athlete && typeof athlete.id === "number" ? athlete.id : null,
    athlete_name: athleteName || null,
  });
});
