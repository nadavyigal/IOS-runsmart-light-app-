# RunSmart 1.2.6 (46): App Store release

Source: branch `claude/2026-11-19-release-1-2-6`, from `origin/main` 1378db7 (Coach Mode + Live Activity).

Changes in this release branch:
- Coach Mode is on in every Release build (`RunSmartFeatures.coachModeEnabled`). Only accounts with a `coach_profiles` row get the Coach tab. Athletes see "Join a coach" in Profile and on sign-in.
- `CURRENT_PROJECT_VERSION` = 46 on the app, tests and Live Activity extension. `MARKETING_VERSION` stays 1.2.6.

## What's New (draft, paste into App Store Connect)

```
Run with a coach. If your coach uses RunSmart, enter their invite code in Profile to join. Your coach sees your runs and can leave notes on them. You decide if your route maps are shared, and you can leave your coach from Profile.

Follow your run from the Lock Screen and the Dynamic Island. Distance, pace and your pace target update as you run, and you can pause, resume or finish without opening the app.

A new home screen widget shows this week's distance against your plan.
```

## App Review notes (draft; demo accounts still to be created)

```
Coach Mode (new in 1.2.6)
Coaches are invite-only. RunSmart sets up each coach account; there is no way to become a coach inside the app. Athletes join a coach by entering the coach's invite code in Profile > Account > Join a coach.

Demo athlete (already linked to a demo coach):
Email: <REVIEWER_ATHLETE_EMAIL>
Password: <set by founder>

Signed in as this athlete, open Profile > Account > My coach to see the coach, what the coach can see, the route-sharing switch, and the coach's notes. Accounts without a coach see only "Join a coach".

Demo coach (optional, to see the Coach tab):
Email: <REVIEWER_COACH_EMAIL>
Password: <set by founder>

Live Activity: start a run from the Run tab, then lock the phone. The Lock Screen and Dynamic Island show distance and pace, with Pause, Resume and Finish. Location permission is needed to record a run.
```

## App Privacy

The athlete's runs (stats and, if the athlete turns it on, the route map) are now visible to the coach the athlete joined. Check in App Store Connect:
- Location (Precise): still "App Functionality", linked to the user. Not used for tracking.
- Fitness / Health-adjacent run data: linked to the user, App Functionality.
- Sharing with a coach the user picks is user-initiated, so it is not "third-party sharing" under Apple's definitions, but the privacy policy should say it.
- Privacy policy: add a line that run data, and route maps if the athlete allows it, are visible to a coach the athlete chooses to join, until the athlete leaves.
