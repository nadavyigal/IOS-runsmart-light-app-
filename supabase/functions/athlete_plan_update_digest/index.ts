// athlete_plan_update_digest (story C8.16). See digest.ts for what it sends and when.
//
// Deploy (Nadav only):
//   supabase functions deploy athlete_plan_update_digest --no-verify-jwt --project-ref <ref>
// It checks its own secret header (COACH_NOTIFY_SECRET, shared with coach_notify)
// instead of a user JWT: its only caller is the 2-minute cron, never the app.
//
// Secrets (names only): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (set by Supabase),
// COACH_NOTIFY_SECRET, APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { apnsConfigFromEnv, disableTokenIn, type PushTokenStore } from "../_shared/apns.ts";
import { handlePlanUpdateDigest } from "./handler.ts";
import { supabaseDigestStore } from "./store.ts";

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "server_configuration_missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const apns = apnsConfigFromEnv();

  return await handlePlanUpdateDigest(req, {
    secret: Deno.env.get("COACH_NOTIFY_SECRET")?.trim() || null,
    flags: admin,
    digest: apns
      ? {
        store: supabaseDigestStore(admin),
        apns,
        disableToken: disableTokenIn(admin as unknown as PushTokenStore),
      }
      : null,
  });
});
