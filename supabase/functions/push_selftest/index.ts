// push_selftest (story C7.10 AC7). DEV ONLY: see handler.ts for the two locks.
// Not in any deploy script. Deploy by hand to a dev project, with the four APNS_*
// secrets and PUSH_SELFTEST_ENABLED=true set there.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { apnsConfigFromEnv, disableTokenIn, liveTokensFor, type PushTokenStore } from "../_shared/apns.ts";
import { handleSelftest } from "./handler.ts";

Deno.serve(async (req) => {
  const enabled = Deno.env.get("PUSH_SELFTEST_ENABLED") === "true";
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (enabled && (!supabaseUrl || !serviceRoleKey)) {
    return new Response(JSON.stringify({ error: "server_configuration_missing" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const admin = enabled
    ? createClient(supabaseUrl!, serviceRoleKey!, { auth: { autoRefreshToken: false, persistSession: false } })
    : null;
  const store = admin as unknown as PushTokenStore;

  return await handleSelftest(req, {
    enabled,
    config: apnsConfigFromEnv(),
    userIdFor: async (accessToken) => {
      const { data, error } = await admin!.auth.getUser(accessToken);
      return error || !data?.user ? null : data.user.id;
    },
    liveTokens: (userId) => liveTokensFor(store, userId),
    disableToken: disableTokenIn(store),
  });
});
