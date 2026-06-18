---
template: 2-day-no-show
status: draft
trigger: cron (daily); fires if user has an active plan but no completed_runs row in last 48 hours AND plan was generated >= 2 days ago
deduplication: once per user per 7-day window (check email_log before sending)
from: RunSmart <noreply@runsmart-ai.com>
experiment: rs-email-001
created: 2026-05-27
---

# 2-Day No-Show Nudge Email

## Subject
Your plan is still there

## Preview text
No pressure — the first session is the hardest one to start.

---

## Body

Hi {{first_name}},

You set up a plan a couple of days ago and haven't logged a run yet. That's completely normal — starting is usually the hardest part.

Your plan hasn't expired. The Today screen still has your next recommended session. It takes the same amount of time it always would have.

If something got in the way — schedule, energy, uncertainty about what to do — open the coach chat and say so. It can adjust the plan or explain what the first session is actually asking you to do.

[Open RunSmart]({{app_url}})

If you've already run and just didn't log it, tap the + button on the Today screen to add it manually.

Nadav
RunSmart

---

## Plain text fallback

Hi {{first_name}},

You set up a plan a couple of days ago and haven't logged a run yet. That's completely normal.

Your plan hasn't expired. The Today screen still has your next recommended session.

If something got in the way, open the coach chat and say so. It can adjust the plan or explain what the first session is actually asking.

Open RunSmart: {{app_url}}

If you've already run and just didn't log it, tap + on the Today screen to add it manually.

Nadav
RunSmart

---

## Copy notes

- Subject is intentionally low-pressure. No exclamation mark, no urgency language.
- "Your plan is still there" is reassuring without being pushy.
- The mention of coach chat is deliberate — gives a low-friction next step for someone who is hesitant.
- The manual log reminder reduces guilt for users who ran but didn't open the app.
- Deduplication window: 7 days. Do not send this more than once per week per user.
- Do NOT send if: user has already logged a run since plan creation, or has unsubscribed.
- Do NOT use "reminder", "forgot", "missed", or "haven't been" phrasing — all place blame.
- Tone: steady, calm, no urgency. The first run is the highest-value activation event; this email's job is to remove friction, not apply pressure.
