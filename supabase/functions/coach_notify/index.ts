// coach_notify (story C7.5). See handler.ts for what it sends and when.
//
// Deploy (Nadav only, docs/coach-v2-batch-b-runbook.md):
//   supabase functions deploy coach_notify --no-verify-jwt --project-ref <ref>
// It checks its own secret header (COACH_NOTIFY_SECRET) instead of a user JWT:
// its callers are the Database Webhooks and the flush cron, never the app.
//
// Secrets (names only): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (set by Supabase),
// COACH_NOTIFY_SECRET, APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { apnsConfigFromEnv, disableTokenIn, type PushTokenStore } from "../_shared/apns.ts";
import { handleCoachNotify } from "./handler.ts";
import { supabaseNotifyStore, supabaseSourceReader } from "./store.ts";

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

  return await handleCoachNotify(req, {
    secret: Deno.env.get("COACH_NOTIFY_SECRET")?.trim() || null,
    flags: admin,
    source: supabaseSourceReader(admin),
    notify: apns
      ? {
        store: supabaseNotifyStore(admin),
        apns,
        disableToken: disableTokenIn(admin as unknown as PushTokenStore),
      }
      : null,
  });
});
