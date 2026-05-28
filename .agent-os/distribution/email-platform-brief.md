# Email Platform Brief — RunSmart iOS

Status: ready for product session
Last updated: 2026-05-27

---

## Platform Decision

**Resend via Supabase Edge Functions.**

- Resend is already wired on the RunSmart web project (`running-coach` on Vercel).
- `RESEND_API_KEY` is stored in Vercel env vars for the `running-coach` project.
- For iOS lifecycle emails, use the same API key added as a Supabase project secret.
- Free tier: 3,000 emails/month, 100/day — sufficient for launch.
- From address: `RunSmart <noreply@runsmart-ai.com>` (domain verified on Resend via runsmart-ai.com).

---

## Trigger Architecture

Each email is sent from a Supabase Edge Function called by a Postgres trigger or a scheduled job.

| Email | Trigger | Supabase Hook |
|---|---|---|
| welcome.md | New row in `auth.users` | Database webhook → `send-welcome` edge function |
| plan-generated-nudge.md | New row in `training_plans` (or plan status = active) | Database webhook → `send-plan-nudge` edge function |
| 2-day-no-show.md | Scheduled: runs daily; checks users with active plan but no `completed_runs` row in last 2 days | Cron job → `send-no-show-nudge` edge function |

---

## Edge Function Spec (per email)

Each edge function:
1. Receives a payload (user_id, email, first_name from the trigger or cron query)
2. Calls `Resend.emails.send(...)` with the HTML from the draft
3. Logs the send to a `email_log` table (user_id, template, sent_at) to prevent double-sends
4. Returns 200 on success, logs error on failure (does not retry automatically — Resend handles delivery retries)

---

## Environment Setup

In Supabase dashboard → Project Settings → Edge Functions → Secrets:
```
RESEND_API_KEY=<copy from Vercel running-coach project env vars>
RESEND_FROM_EMAIL=RunSmart <noreply@runsmart-ai.com>
```

Note: Do not hardcode the API key. Use `Deno.env.get('RESEND_API_KEY')` in the edge function.

---

## Deduplication

Before sending, check `email_log`:
```sql
SELECT 1 FROM email_log
WHERE user_id = $1 AND template = $2
LIMIT 1;
```
If row exists, skip. This prevents duplicate sends if the trigger fires twice or the cron runs during processing.

---

## CTA Link Pattern

For iOS-only users: use a universal link (`https://runsmart-ai.com/open`) that redirects to the app if installed, or the App Store if not. Alternatively, use the App Store URL directly:
`https://apps.apple.com/app/id<APP_ID>` (fill App ID after App Store submission is approved).

Fallback while app is pre-launch: use `https://runsmart-ai.com` as the CTA URL.

---

## Email Drafts

See `.agent-os/distribution/email-drafts/`:
- `welcome.md` — sent on new user creation
- `plan-generated-nudge.md` — sent when first plan is generated
- `2-day-no-show.md` — sent when user has active plan but no run in 2 days

All three are copy-only drafts. A product session converts them to Supabase Edge Function HTML templates.

---

## Sending in Production

Wire emails in this order:
1. welcome (lowest risk — fires once per user, no conditional logic)
2. plan-generated-nudge (fires once per user on plan creation)
3. 2-day-no-show (fires on schedule — requires cron + deduplication logic)

Do not enable any trigger in production without founder sign-off. Status of each draft is tracked in `experiment-log.md` as rs-email-001.
