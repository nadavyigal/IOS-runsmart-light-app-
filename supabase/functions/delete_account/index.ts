import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Account deletion endpoint required by App Store Guideline 5.1.1(v).
// Validates the caller's JWT, removes all rows owned by the user across
// public tables, then deletes the auth user itself via the admin API.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(500, { error: "Server configuration missing" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return jsonResponse(401, { error: "Missing access token" });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) {
    return jsonResponse(401, { error: "Invalid or expired access token" });
  }
  const authUserId = userData.user.id;

  // Resolve the legacy bigint profile id used by several tables.
  const { data: profileRow } = await admin
    .from("profiles")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  // profiles.id is bigint for legacy rows and uuid for web-created rows; the
  // bigint-keyed tables below only apply to legacy rows.
  const rawProfileId = profileRow?.id;
  const legacyProfileId: number | null =
    typeof rawProfileId === "number"
      ? rawProfileId
      : typeof rawProfileId === "string" && /^\d+$/.test(rawProfileId)
        ? Number(rawProfileId)
        : null;

  const failures: string[] = [];

  async function wipe(table: string, column: string, value: string | number) {
    const { error } = await admin.from(table).delete().eq(column, value);
    // Ignore "relation does not exist" style errors so schema drift never
    // blocks deletion of the remaining tables.
    if (error && error.code !== "42P01") {
      failures.push(`${table}.${column}: ${error.message}`);
    }
  }

  // Tables keyed by auth user uuid.
  const uuidTables: Array<[string, string]> = [
    ["conversation_messages", "auth_user_id"],
    ["conversations", "auth_user_id"],
    ["run_debriefs", "auth_user_id"],
    ["plan_adjustments", "auth_user_id"],
    ["workouts", "auth_user_id"],
    ["plans", "auth_user_id"],
    ["wellness_checkins", "auth_user_id"],
    ["user_streaks", "auth_user_id"],
    ["challenge_enrollments", "auth_user_id"],
    ["training_derived_metrics", "auth_user_id"],
    ["ai_insights", "auth_user_id"],
    ["garmin_activity_points", "auth_user_id"],
    ["garmin_activities", "auth_user_id"],
    ["garmin_daily_metrics", "auth_user_id"],
    ["garmin_tokens", "auth_user_id"],
    ["garmin_connections", "auth_user_id"],
    ["beta_signups", "auth_user_id"],
  ];
  for (const [table, column] of uuidTables) {
    await wipe(table, column, authUserId);
  }

  // Some tables also use auth.uid() as a uuid profile_id.
  await wipe("plans", "profile_id", authUserId);
  await wipe("conversations", "profile_id", authUserId);
  await wipe("idempotency_keys", "profile_id", authUserId);
  await wipe("analytics_events", "user_id", authUserId);

  // Web-created profiles use a distinct uuid id that some rows reference.
  const uuidProfileId =
    typeof rawProfileId === "string" && !/^\d+$/.test(rawProfileId) && rawProfileId !== authUserId
      ? rawProfileId
      : null;
  if (uuidProfileId) {
    await wipe("plans", "profile_id", uuidProfileId);
    await wipe("conversations", "profile_id", uuidProfileId);
    await wipe("idempotency_keys", "profile_id", uuidProfileId);
  }

  // Tables keyed by the legacy bigint profile id.
  if (legacyProfileId !== null) {
    const bigintTables: Array<[string, string]> = [
      ["runs", "profile_id"],
      ["garmin_activity_files", "user_id"],
      ["garmin_import_jobs", "user_id"],
      ["garmin_import_jobs", "profile_id"],
      ["user_memory_snapshots", "user_id"],
    ];
    for (const [table, column] of bigintTables) {
      await wipe(table, column, legacyProfileId);
    }
  }

  // Profile row last, after its dependents are gone.
  await wipe("profiles", "auth_user_id", authUserId);

  if (failures.length > 0) {
    console.error("[delete_account] partial failure", { authUserId, failures });
    return jsonResponse(500, {
      error: "Some account data could not be deleted. Please try again.",
      details: failures,
    });
  }

  const { error: deleteUserError } = await admin.auth.admin.deleteUser(authUserId);
  if (deleteUserError) {
    console.error("[delete_account] auth user deletion failed", deleteUserError);
    return jsonResponse(500, { error: "Account data was removed but the account could not be deleted. Please try again." });
  }

  console.log("[delete_account] account deleted", { authUserId });
  return jsonResponse(200, { success: true });
});
