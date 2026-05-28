---
template: plan-generated-nudge
status: draft
trigger: training_plans row inserted or status set to active (first plan only)
from: RunSmart <noreply@runsmart-ai.com>
experiment: rs-email-001
created: 2026-05-27
---

# Plan Generated Nudge Email

## Subject
Here's the plan — and a quick sanity check

## Preview text
Take 60 seconds to look it over before your first session.

---

## Body

Hi {{first_name}},

Your training plan is ready.

Before your first session, it's worth spending 60 seconds looking at the first two weeks. The plan is built around your goal and the number of days you said you can run. If something looks off — too much, too little, wrong days — open the coach chat and tell it. That's what it's for.

**What to check:**

- Does the first week feel doable given your current routine?
- Are the session days roughly right for your week?
- Is the long run distance reasonable for where you are now?

The plan will adjust over time, but starting with the right baseline makes a difference.

[Review your plan]({{app_url}})

One more thing: log your first run, even if it's short. The post-run summary after your first session is the clearest way to see how the coaching loop works.

Nadav
RunSmart

---

## Plain text fallback

Hi {{first_name}},

Your training plan is ready.

Before your first session, spend 60 seconds looking at the first two weeks. If something looks off — too much, too little, wrong days — open the coach chat and tell it.

What to check:
- Does the first week feel doable?
- Are the session days roughly right for your week?
- Is the long run distance reasonable for where you are now?

Review your plan: {{app_url}}

One more thing: log your first run, even if it's short. The post-run summary after your first session is the clearest way to see how the coaching loop works.

Nadav
RunSmart

---

## Copy notes

- Fires once per user, on first plan creation only. Not on every regeneration.
- The "sanity check" framing sets expectations correctly — the user should feel empowered to question the plan, not locked in.
- CTA goes to the plan view, not the home screen.
- Ends with a secondary nudge to log the first run (the key activation event) without making it feel like a demand.
- Tone: collegial, practical. The user just completed onboarding — energy is high but fragile. Don't oversell.
