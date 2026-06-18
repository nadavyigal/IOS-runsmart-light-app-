---
template: welcome
status: draft
trigger: new user created (auth.users insert)
from: RunSmart <noreply@runsmart-ai.com>
experiment: rs-email-001
created: 2026-05-27
---

# Welcome Email

## Subject
Your first plan, ready to look at

## Preview text
RunSmart takes about two minutes to set up.

---

## Body

Hi {{first_name}},

Your RunSmart account is ready. Here's what happens next.

**Open the app and complete your profile.** It takes about two minutes. You'll set a goal, tell us roughly how much you've been running, and choose how you like to be coached. After that, RunSmart generates your first training plan.

The plan adjusts as you go. If you skip a session or have a rough week, it reorganises around what you actually did rather than flagging you as behind.

**A few things to know:**

- The Today screen shows your next recommended session every morning.
- After each run, you'll get a short plain-language summary of what happened and what it means for the week ahead.
- If you connect Garmin or Apple Health, RunSmart will pull your activity data automatically.

[Open RunSmart]({{app_url}})

If anything feels off or you have a question, reply to this email.

Nadav
RunSmart

---

## Plain text fallback

Hi {{first_name}},

Your RunSmart account is ready.

Open the app and complete your profile — it takes about two minutes. After that, RunSmart generates your first training plan.

The plan adjusts as you go. If you skip a session or have a rough week, it reorganises around what you actually did.

A few things to know:
- The Today screen shows your next recommended session every morning.
- After each run, you'll get a short summary of what happened and what it means for the week ahead.
- If you connect Garmin or Apple Health, RunSmart will pull your activity data automatically.

Open RunSmart: {{app_url}}

If anything feels off or you have a question, reply to this email.

Nadav
RunSmart

---

## Copy notes

- Tone: calm, practical, no hype. User just signed up — don't over-explain.
- CTA is a single link. Do not add secondary CTAs.
- "Nadav" signature keeps it personal without being sappy.
- {{first_name}} falls back to "there" if name is null.
- {{app_url}} is the universal link or App Store URL (see email-platform-brief.md).
- Do not mention AI, smart, or adaptive in the first email — show it, don't label it.
