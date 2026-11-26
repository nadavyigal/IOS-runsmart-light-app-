# Coach Experience v2: Batch B runbook (push)

Nadav only. Agents never run any step here: no migration, no deploy, no webhook, no cron, no secret.

Batch B turns on remote push for v2 pairs:
- M2a `20261122100000_push_tokens_and_prefs.sql` (C7.10): device tokens and notification prefs.
- M2b `20261122110000_notification_log_and_deferred.sql` (C7.5): the push log and held pushes.
- `20261122120000_workout_adherence_state.sql` (C7.6): the shared adherence rule and the evening summary counts (functions only).
- Edge Function `coach_notify` (C7.5): sends the run, flag, reply and note pushes, and the collapsed pushes at quiet end.
- Edge Function `coach_evening_summary` (C7.6): the 20:00 coach push with counts.
- Four Database Webhooks and one cron job that call `coach_notify`, and one hourly cron that calls `coach_evening_summary`.

Kill switch for all of it: `runtime_flags.coach_v2_push` (section 7). Rollback: `docs/coach-v2-rollback.md`, Batch B.

> **Live state, 2026-11-26.** Applied and set up in production on the founder's yes:
> M2a, M2b, the C7.6 file, both functions deployed (`--no-verify-jwt`), the four insert
> triggers from `20261126110000_coach_notify_triggers.sql` (these replace the Dashboard
> webhooks in section 4), and the two crons from sections 5 and 5b. The crons and the
> triggers read the endpoint and the secret from Vault: `coach_notify_url`,
> `coach_evening_summary_url` and `coach_notify_secret`. They send nothing while
> `coach_notify_secret` is missing. The only manual step left is the shared secret:
> set `COACH_NOTIFY_SECRET` (section 1) and put the same value in Vault as
> `coach_notify_secret` (section 5), in one go, so neither copy is ever shown.

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
| `COACH_NOTIFY_SECRET` | A random value you make: `openssl rand -hex 32` | `coach_notify` and `coach_evening_summary` check it on every call |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set by Supabase already.

Keep the `COACH_NOTIFY_SECRET` value at hand: the webhooks (section 4) and the vault entry (section 5) need the same value.

Without the four `APNS_*` secrets, `coach_notify` answers 503 `apns_not_configured` and touches nothing. Without `COACH_NOTIFY_SECRET`, it answers 500 and touches nothing.

## 2. Apply M2a, M2b, then the C7.6 file

Same way as Batch A, in this order (M2b's functions read M2a's tables at send time; the C7.6 counts read M2a's prefs):

1. `20261122100000_push_tokens_and_prefs.sql`
2. `20261122110000_notification_log_and_deferred.sql`
3. `20261122120000_workout_adherence_state.sql`

Check:

```sql
select to_regclass('public.push_tokens'), to_regclass('public.notification_prefs'),
       to_regclass('public.coach_notification_log'), to_regclass('public.deferred_pushes');
select proname from pg_proc where proname like 'coach_notify_%' order by 1;
-- expect coach_notify_claim, coach_notify_defer, coach_notify_link_state
select proname from pg_proc
where proname in ('workout_adherence_boundary', 'workout_adherence_state', 'coach_evening_summary_counts')
order by 1;
-- expect all three
```

Then mark the three rows `applied` in `docs/migration-ledger.md` (both repos).

## 3. Deploy `coach_notify`

From the iOS repo root (the function lives in `supabase/functions/coach_notify`):

```bash
supabase functions deploy coach_notify --no-verify-jwt --project-ref <ref>
```

`--no-verify-jwt`: the callers are the webhooks and the cron, not the app. The function checks `x-coach-notify-secret` itself (constant-time compare) and refuses anything else with 401.

Then the evening summary (C7.6), the same way:

```bash
supabase functions deploy coach_evening_summary --no-verify-jwt --project-ref <ref>
```

Its only caller is the hourly cron (section 5b). Same secret, same header, same 401.

## 4. Four Database Webhooks

> Superseded on 2026-11-26 by the insert triggers in `20261126110000_coach_notify_triggers.sql`. Do not also create Dashboard webhooks: every insert would push twice.

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

## 5b. The evening summary cron (every hour, C7.6)

Uses the same vault entry as section 5. Schedule (replace `<ref>`):

```sql
select cron.schedule(
  'coach_evening_summary_hourly',
  '0 * * * *',
  $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/coach_evening_summary',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-coach-notify-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'coach_notify_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);
```

What each run does: sends the summaries held through quiet hours that are now due ("Yesterday: …" after the coach's midnight), then, for every coach whose local time (their `notification_prefs.time_zone`) is in the 20:00 hour, one push "Today: {n} missed · {k} flags open · {m} changed their plan". No push when all three are 0, none with the T5 toggle off, at most one per coach per local day (the log). Every run falls in exactly one local 20:00 hour per zone, half-hour zones and DST days included, so keep it at minute 0 and hourly. A run that fails (cron down for that hour) skips that evening's summary; nothing is sent late.

Check after the first evening:

```sql
select ref_id as day, outcome, count(*)
from public.coach_notification_log
where kind = 'coachEveningSummary' and sent_at > now() - interval '2 days'
group by 1, 2 order by 1, 2;

select count(*) from public.deferred_pushes where kind = 'coachEveningSummary';
```

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
select cron.unschedule('coach_evening_summary_hourly');
```

Then delete the four webhooks in Dashboard → Database → Webhooks.
