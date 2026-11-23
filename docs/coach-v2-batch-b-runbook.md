# Coach Experience v2: Batch B runbook (push)

Nadav only. Agents never run any step here: no migration, no deploy, no webhook, no cron, no secret.

Batch B turns on remote push for v2 pairs:
- M2a `20261122100000_push_tokens_and_prefs.sql` (C7.10): device tokens and notification prefs.
- M2b `20261122110000_notification_log_and_deferred.sql` (C7.5): the push log and held pushes.
- Edge Function `coach_notify` (C7.5): sends the run, flag, reply and note pushes, and the collapsed pushes at quiet end.
- Four Database Webhooks and one cron job that call `coach_notify`.

Kill switch for all of it: `runtime_flags.coach_v2_push` (section 7). Rollback: `docs/coach-v2-rollback.md`, Batch B.

## 0. Before you start

1. Batch A is applied (ledger: applied 2026-11-23).
2. C7.10 (iOS #248) and C7.5 are merged, and a TestFlight build with them is installed on the pilot devices.
3. Push is enabled on the App ID, and you have the APNs Auth Key (.p8).
4. Extensions `pg_net` and `pg_cron` are on: Dashboard → Database → Extensions. `pg_net` is also what Database Webhooks use.

## 1. Secrets (names only)

Dashboard → Edge Functions → Secrets, or `supabase secrets set --project-ref <ref> NAME=value`.

| Name | What | Used by |
|---|---|---|
| `APNS_KEY_ID` | The Auth Key id (10 characters) | `_shared/apns.ts` |
| `APNS_TEAM_ID` | The Apple Developer team id | `_shared/apns.ts` |
| `APNS_PRIVATE_KEY` | The .p8 file contents (PEM; `\n` escapes are fine) | `_shared/apns.ts` |
| `APNS_BUNDLE_ID` | The app's bundle id (the `apns-topic`) | `_shared/apns.ts` |
| `COACH_NOTIFY_SECRET` | A random value you make: `openssl rand -hex 32` | `coach_notify` checks it on every call |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set by Supabase already.

Keep the `COACH_NOTIFY_SECRET` value at hand: the webhooks (section 4) and the vault entry (section 5) need the same value.

Without the four `APNS_*` secrets, `coach_notify` answers 503 `apns_not_configured` and touches nothing. Without `COACH_NOTIFY_SECRET`, it answers 500 and touches nothing.

## 2. Apply M2a, then M2b

Same way as Batch A, in this order (M2b's functions read M2a's tables at send time):

1. `20261122100000_push_tokens_and_prefs.sql`
2. `20261122110000_notification_log_and_deferred.sql`

Check:

```sql
select to_regclass('public.push_tokens'), to_regclass('public.notification_prefs'),
       to_regclass('public.coach_notification_log'), to_regclass('public.deferred_pushes');
select proname from pg_proc where proname like 'coach_notify_%' order by 1;
-- expect coach_notify_claim, coach_notify_defer, coach_notify_link_state
```

Then mark both rows `applied` in `docs/migration-ledger.md` (both repos).

## 3. Deploy `coach_notify`

From the iOS repo root (the function lives in `supabase/functions/coach_notify`):

```bash
supabase functions deploy coach_notify --no-verify-jwt --project-ref <ref>
```

`--no-verify-jwt`: the callers are the webhooks and the cron, not the app. The function checks `x-coach-notify-secret` itself (constant-time compare) and refuses anything else with 401.

## 4. Four Database Webhooks

Dashboard → Database → Webhooks → Create a new hook. Make four, identical except the name and table:

| Name | Table | Events |
|---|---|---|
| `coach_notify_runs` | `public.runs` | Insert |
| `coach_notify_flags` | `public.athlete_run_flags` | Insert |
| `coach_notify_notes` | `public.coach_feedback` | Insert |
| `coach_notify_replies` | `public.coach_feedback_replies` | Insert |

For each:
- Type of webhook: **Supabase Edge Functions**, function `coach_notify`.
- Method: POST. Timeout: 5000 ms.
- HTTP Headers: `Content-Type: application/json` and `x-coach-notify-secret: <COACH_NOTIFY_SECRET value>`.
- Insert only. Never Update or Delete: an upsert that updates a run must not push again.

What each one sends: runs → coach "{Athlete} finished a {x} km run" (not for imports older than 24 h); flags → coach "{Athlete} flagged something after a run"; replies → coach "{Athlete} replied to your note"; coach_feedback → athlete "{Coach} left you a note" (kind `note` only; welcome notes are never pushed). The function reads each row again by id, so the payload is only a pointer.

## 5. The flush cron (every minute)

Held pushes (quiet hours, and the 4th+ run push to one coach within 10 minutes) go out from this call. It is cheap when nothing is held: one select.

Put the secret in Vault once (SQL editor), so it never sits in the cron command text:

```sql
select vault.create_secret('<COACH_NOTIFY_SECRET value>', 'coach_notify_secret');
```

Then schedule (replace `<ref>`):

```sql
select cron.schedule(
  'coach_notify_flush',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/coach_notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-coach-notify-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'coach_notify_secret')
    ),
    body := '{"action":"flush"}'::jsonb,
    timeout_milliseconds := 10000
  );
  $$
);
```

Why every minute: the burst push is due at the end of a 10-minute window, and quiet end is any minute the user picked. The function sends nothing until a held row is due.

C7.6 (evening summary) adds its own hourly cron for `coach_evening_summary`; it is not part of this step.

## 6. Smoke test (one pilot pair)

1. On the pilot coach's phone: Coach tab, accept the push prompt. On the pilot athlete's phone: My coach, accept the push prompt.
2. Athlete records a short run. Coach gets "{Athlete} finished a … km run" within 2 minutes.
3. Coach writes a note. Athlete gets "{Coach} left you a note".
4. Check the log:

```sql
select kind, outcome, count(*)
from public.coach_notification_log
where sent_at > now() - interval '1 hour'
group by 1, 2 order by 1, 2;

select reason, kind, count(*) from public.deferred_pushes group by 1, 2;

select jobname, status, return_message, start_time
from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'coach_notify_flush')
order by start_time desc limit 5;
```

`outcome = 'no_device'` means the recipient has no live token (push not turned on, or the token was disabled by an APNs 410). `outcome = 'failed'` means APNs refused: check the function logs for `apns_rejected` and Apple's reason.

## 7. Off switch and removal

Stop every push, keep every held row (the first move on a bad day):

```sql
update public.runtime_flags set enabled = false, updated_at = now() where key = 'coach_v2_push';
```

Turn it back on with `enabled = true`. Held rows go out at the next flush, if their link is still active and v2.

Remove the triggers (before a rollback of M2b, see `docs/coach-v2-rollback.md`):

```sql
select cron.unschedule('coach_notify_flush');
```

Then delete the four webhooks in Dashboard → Database → Webhooks.
