# RunSmart 1.2.6 (46): App Store release

Source: branch `claude/2026-11-19-release-1-2-6`, from `origin/main` 1378db7 (Coach Mode + Live Activity).

Changes in this release branch:
- Coach Mode is on in every Release build (`RunSmartFeatures.coachModeEnabled`). Only accounts with a `coach_profiles` row get the Coach tab. Athletes see "Join a coach" in Profile and on sign-in.
- `CURRENT_PROJECT_VERSION` = 46 on the app, tests and Live Activity extension. `MARKETING_VERSION` stays 1.2.6.

## Build evidence (2026-11-20)

- Archive: `~/Library/Developer/Xcode/Archives/2026-11-19/RunSmart-1.2.6-46.xcarchive`, from commit bd281ab.
- App and `RunSmartRunLiveActivityExtension.appex` both 1.2.6 (46). Extension embedded. Both carry `group.com.runsmart.lite`. `NSSupportsLiveActivities` = true. PostHog key non-empty. `codesign --verify --deep --strict` ok.
- `scripts/verify-release-backend.py`: passed, Auth settings HTTP 200, Apple and email enabled.
- Export with `ExportOptionsAppStoreUpload.plist`: signed with Apple Distribution (8VC4R5M425), "Upload succeeded". The first attempt hung after creating its upload record and was killed; the retry succeeded.
- Apple warning only: iOS 27 SDK required from April 2027.

## App Store Connect state (2026-11-20)

- Version 1.2.6 created (Prepare for Submission). Build 46 attached. What's New and App Review notes saved and re-read after reload. Not submitted.
- Build 46 email: only ITMS-90725 (iOS 27 SDK from April 2027). Not blocking.
- Sign-In Information keeps the existing dedicated reviewer account (`runsmartteam@`), not a personal account.
- App Privacy: no change needed. Location, Fitness, Health and Other User Content are already declared for App Functionality and linked to the user. Showing data to a coach the user joined is user-directed, not tracking.
- Privacy policy (runsmart-ai.com/privacy, updated 2026-11-02) mentions only the AI coach. Proposed line: "If you join a human coach with an invite code, that coach can see your runs and coach notes, and your route maps if you turn route sharing on. The coach keeps this access until you leave the coach in Profile."
- Age rating banner: answers on "Location Sharing" are due by 2027-01-15. Coach Mode shares route maps with a coach, so answer it with Coach Mode in mind.

## Reviewer coach link (needs founder yes; production writes)

The review notes say the reviewer athlete is already linked to a demo coach. Before Submit:
1. Founder creates a coach account in the app (suggested `runsmartteam+coach@`) and sets a display name such as "RunSmart Demo Coach".
2. Run in Supabase SQL (production):

```sql
-- ids
select id, email from auth.users where email in ('<coach email>', '<reviewer athlete email>');
-- make the coach
insert into coach_profiles (user_id, display_name) values ('<coach id>', 'RunSmart Demo Coach');
-- link the reviewer athlete (same shape join_coach writes)
insert into coach_athlete_links (coach_id, athlete_id, status, consented_at)
values ('<coach id>', '<athlete id>', 'active', now());
```

Undo: `update coach_athlete_links set status='revoked', revoked_at=now() where athlete_id='<athlete id>' and status='active'; delete from coach_profiles where user_id='<coach id>';`

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
