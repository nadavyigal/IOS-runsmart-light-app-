# Garmin worker HTTP 500 and Garmin credential rotation (2026-11-22)

Report only. Nothing was changed in production.

## 1. `garmin-worker-drain` returns HTTP 500

### What happens
- Cron job `garmin-worker-drain` (jobid 1, `*/5 * * * *`) runs `SELECT public.invoke_garmin_worker();`.
- The function reads `garmin_worker_url` and `garmin_worker_cron_secret` from `public.app_secrets`
  and POSTs to `https://www.runsmart-ai.com/api/...` (Vercel project `running-coach`).
- The worker answers HTTP 500 with:
  `{"success":false,"error":"Failed to claim Garmin import jobs: Unregistered API key"}`
- `net._http_response` keeps about 6 hours: 72 of 72 calls failed, 0 succeeded (2026-11-22 11:50 to 17:45 UTC).
- Queue right now: 0 queued Garmin import jobs, so no user is waiting. Any new import would never drain.

### Cause
The cron secret and the URL are fine (the worker runs and gets as far as the database call).
It fails at `supabase.rpc('claim_garmin_import_jobs')` in `v0/lib/integrations/garmin/service.ts:541`,
which uses `createAdminClient()` (`v0/lib/supabase/admin.ts`) with `SUPABASE_SERVICE_ROLE_KEY`.

"Unregistered API key" is Supabase saying that key is not a key of project `dxqglotcyirxzyqaxqln` (Run-Smart):
- Run-Smart legacy keys are still enabled; the JWT secret has not rotated in a year.
- Run-Smart has a publishable key but **no secret key** (`sb_secret_...`) yet.
- `running-coach` `SUPABASE_SERVICE_ROLE_KEY` (All Environments) was added 12/25/25 and never changed.

So the stored value is most likely a key from another project, or an `sb_secret_` key that was later deleted.
The value was not read during this check.

### Fix (recommended): give the worker a real Run-Smart secret key
1. Supabase Run-Smart > Settings > API Keys > **New secret key**, name it `vercel_running_coach`.
2. Vercel `running-coach` > Environment Variables > `SUPABASE_SERVICE_ROLE_KEY` (All Environments) > Edit:
   paste the new `sb_secret_...` value, type **Secret**, Save.
3. Redeploy production (build cache off).
4. Verify (Run-Smart SQL editor), after the next 5-minute tick:
   ```sql
   select status_code, created, left(content::text, 120)
   from net._http_response order by created desc limit 3;
   ```
   Expect 200. A body like `{"success":true,...}` means the worker claimed jobs (or found none).
5. This also moves the RunSmart server off the legacy `service_role` key, which Supabase retires at the end of 2026.

### Fallback: pause the cron job
`supabase/migrations/20261122180000_pause_garmin_worker_drain.sql` unschedules the job. The file has the undo line.
Use it only if the fix has to wait. Mirror it to the web repo `migrations` folder if you apply it.

### Side finding
`v0/app/api/devices/garmin/oauth-state.ts:16` falls back to the fixed string
`'dev-encryption-key-change-in-production'` when `ENCRYPTION_KEY` is missing. In production
that would make OAuth state predictable. Safer: throw when `ENCRYPTION_KEY` is missing outside development.

## 2. Garmin credential rotation plan (not done)

Vercel `running-coach` values not rotated since Feb/Apr 2026:
`GARMIN_CLIENT_ID`, `GARMIN_CLIENT_SECRET`, `GARMIN_WEBHOOK_SECRET`, `ENCRYPTION_KEY`.

Order matters. Do one at a time, verify, then the next.

| Step | Credential | How | User impact | Verify |
|---|---|---|---|---|
| 1 | `GARMIN_WEBHOOK_SECRET` | Generate a new random value. Update it in the Garmin developer portal webhook settings and in Vercel at the same time, then redeploy | Webhooks fail for the minutes between the two changes | Next Garmin webhook gets 200 in Vercel logs |
| 2 | `GARMIN_CLIENT_SECRET` (and `GARMIN_CLIENT_ID` only if Garmin issues a new app) | Garmin Connect Developer Program portal: regenerate the consumer secret. Update Vercel, redeploy | Token refresh fails until Vercel has the new secret; existing user tokens stay valid | `/api/devices/garmin/diagnose` shows configured; a test account reconnects and syncs |
| 3 | `ENCRYPTION_KEY` | Needs code first: support `ENCRYPTION_KEY_PREVIOUS` in `token-crypto.ts` (decrypt with old, encrypt with new), deploy, then swap the value, then re-encrypt stored tokens or let them re-encrypt on next refresh | Without the code change every connected user must reconnect Garmin | Connected test user still syncs after the swap |
| 4 | `SUPABASE_SERVICE_ROLE_KEY` | Covered by the fix in section 1 | None | Worker returns 200 |

Before step 3, fix the `oauth-state.ts` fallback (side finding above).

Context from the web repo `docs/garmin-application/GARMIN-STATUS.md` (last updated 2026-07-02, not re-checked live):
Garmin is deactivating the current Evaluation-tier app and asked for two new apps (internal test, commercial).
New connections are gated off by `GARMIN_CONNECT_ENABLED`. When the new apps arrive they come with new
client IDs and secrets, so step 2 happens naturally then. Do steps 1, 3 and 4 regardless: the webhook
secret, the token encryption key and the Supabase key protect data that already exists.
