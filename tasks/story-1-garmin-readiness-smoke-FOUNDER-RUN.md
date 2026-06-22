# Story 1 — Founder Physical TestFlight Smoke (Run Sheet)

**Date:** ___________  
**Build tested:** 1.0.3 (__) — TestFlight build ___ or later  
**Device:** iPhone model ______ (no serial/UDID)  
**Tester:** Founder  

> Complete this on a **physical iPhone** with TestFlight build **16 or later** (App Store live build 1.0.3 counts if same binary). Share results back in chat — agent will update `story-1-garmin-readiness-smoke-2026-06-20.md` and mark Story 1 complete.

---

## Smoke checklist

| # | Step | Pass? | Notes |
|---|---|---|---|
| 1 | Install TestFlight / App Store build 16+ on physical iPhone | ☐ | |
| 2 | Launch app fresh (kill + reopen) | ☐ | |
| 3 | Sign in with Apple completes | ☐ | |
| 4 | Onboarding does **not** ask for name or email | ☐ | |
| 5 | Onboarding completes | ☐ | |
| 6 | Plan generated | ☐ | |
| 7 | Run started | ☐ | |
| 8 | Run completed (if feasible) | ☐ | Skip reason if N/A: ______ |
| 9 | Garmin connect attempted (Profile → Devices) | ☐ | Skip reason if N/A: ______ |
| 10 | Garmin sync completed (if connect attempted) | ☐ | |

---

## PostHog verification (project 171597)

After smoke, check PostHog for events from **today** on the tested build:

| Event | Seen? |
|---|---|
| `app_launched` | ☐ |
| `sign_in_completed` | ☐ |
| `onboarding_completed` | ☐ |
| `plan_generated` | ☐ |
| `run_started` | ☐ |
| `run_completed` | ☐ |
| `garmin_connect_tapped` | ☐ (if attempted) |
| `garmin_sync_completed` | ☐ (if attempted) |

**Do not paste:** tokens, emails, device IDs, or screenshots with personal account data.

---

## Share back (paste in chat)

```
Story 1 smoke — YYYY-MM-DD
Build: 1.0.3 (16) TestFlight/App Store
Device: iPhone ___
SIWA: pass/fail
Onboarding no name/email: pass/fail
Plan generated: pass/fail
Run started: pass/fail
Run completed: pass/fail/skip
Garmin connect: pass/fail/skip
PostHog events seen: app_launched, sign_in_completed, ...
Overall: PASS / FAIL / PARTIAL (Garmin deferred → Story 2)
```

---

## Routing after smoke

- **All pass including Garmin:** → Story 6 pre-mortem before production expansion
- **Pass except Garmin:** → Story 2 (Garmin Connection Proof) next
- **Pass except PostHog gaps:** → Story 5 (Analytics evidence) next
- **Fail on SIWA/onboarding/plan/run:** → fix before any Garmin production work
