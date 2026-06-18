# RunSmart — App Store Program

Primary acquisition surface. Use `marketingskills/skills/aso/SKILL.md` for every audit and rewrite.

## Current State

- **App name**: RunSmart
- **Subtitle**: Run coaching that fits today *(28 chars — 2 chars available)*
- **Promotional text**: Build a simple running habit with adaptive plans, GPS run tracking, route context, and private coaching insights.
- **Keywords**: running,5K,training,GPS,coach,Garmin,HealthKit,workout,fitness,run plan *(97 chars — 3 remaining)*
- **Description**: *(full text — see fastlane/metadata/en-US/description.txt)*
  > RunSmart helps beginner and returning runners know what to do today, record their runs, and build a steadier training rhythm. Start with a simple goal, get a practical plan, and use the Today screen to see your next recommended workout, readiness context, route suggestions, and recent progress. Record outdoor runs with GPS, review your run afterward, and keep your plan aligned with what you actually completed. RunSmart also includes optional connected signals from Apple Health and Garmin, private progress sharing, local workout reminders, and a coach chat that can explain your training context in plain language.
  >
  > **✅ Garmin sentence approved 2026-05-27. Replacement: "When connected, RunSmart imports activity data from Garmin and Apple Health to update your training readiness and workout history." — Draft at distribution-os/projects/runsmart/scaffold/drafts/2026-05-27-rs-aso-001/description.txt. Copy to fastlane/metadata/en-US/description.txt to apply.**
- **Release notes**: RunSmart 1.0 includes adaptive training plans, Today recommendations, GPS run recording, post-run reports, route context, Garmin and Apple Health support, private progress sharing, local reminders, and authenticated Coach chat.
- **Bundle ID**: com.runsmart.lite
- **Version**: 1.0 / Build 5
- **Category**: Health & Fitness
- **Age rating**: 4+
- **Privacy URL**: https://www.runsmart-ai.com/privacy
- **Support URL**: https://www.runsmart-ai.com/support
- **Marketing URL**: https://www.runsmart-ai.com

## App Store Status

**Status: Uploaded to App Store Connect — pending review submission (not yet live)**

- Build archived and uploaded 2026-05-19
- Screenshots staged (see below)
- Remaining before submit: confirm privacy questionnaire, confirm category/age fields in portal, enter demo credentials in App Store Connect, select processed build for review

## Screenshots

Staged in `fastlane/screenshots/en-US/`. Two device sizes present.

| Slot | iPhone 17 Pro Max (6.9") | iPhone 17e (6.1") |
|---|---|---|
| 1 | iPhone_17_Pro_Max_01_today.png | iPhone_17e_01_today.png |
| 2 | iPhone_17_Pro_Max_02_plan.png | iPhone_17e_02_plan.png |
| 3 | iPhone_17_Pro_Max_03_run.png | iPhone_17e_03_run.png |
| 4 | iPhone_17_Pro_Max_04_report.png | iPhone_17e_04_report.png |
| 5 | iPhone_17_Pro_Max_05_profile.png | iPhone_17e_05_profile.png |
| sup | iPhone_17_Pro_Max_99_signin.png | — |

Dimensions: 1320×2868 (Pro Max), 1170×2532 (17e). ✅

Screenshot captions / overlay text: See `.agent-os/distribution/screenshot-overlay-copy.md` — all A variants approved 2026-05-27. Ready to render.

## Localization

- English (en-US): fully staged ✅
- Hebrew (he): **in scope** — App Store metadata only (translated listing; app UI stays English). Assets not yet created.
- Other locales: not started

## Web → App Store Attribution

`at=` (affiliate token) and `ct=` (campaign token) parameters are **NOT wired** in any web → App Store links. No SKAdNetwork or AppsFlyer setup present. Wire before any paid or web-driven traffic.

## Tracked Keyword Themes

- ai running coach
- adaptive training plan
- beginner 5k
- marathon training app
- garmin running
- garmin coach
- run coaching app
- intervals training
- HealthKit running

## Quarterly ASO Tasks

- Audit listing against the `aso` skill checklist
- Re-rank tracked keywords; rotate in 2 new candidate keywords
- Refresh screenshots if positioning shifted (add caption overlays as next priority)
- Update "what's new" with every release
- Compare against Runna and Garmin Coach listings

## Review Response Policy

- Reply to every 4/5-star review with a personal note
- Reply to 1/2-star reviews factually, never defensively
- Aggregate review themes monthly; promote to `lessons.md` if cross-product

---

## Garmin Feature Audit

Audit date: 2026-05-27. Source: GarminWellnessViews.swift, MorningCheckinView.swift, ActivityConsolidationService.swift, SupabaseRunSmartServices.swift, QA docs.

| Feature | What it does | Gated? | Safe to claim in App Store? |
|---|---|---|---|
| Garmin activity import | Imports completed runs from Garmin Connect via GarminBridge; updates training history and Today screen | Requires Garmin OAuth connection (user-initiated). Physical-device OAuth smoke still pending | Conditional — safe to say "connect Garmin to import activity"; unsafe to claim as always-on |
| Garmin wellness signals (readiness, body battery, sleep, HRV) | Shows Garmin metrics in wellness panel on Today/Profile. Falls back to "--" when no data | Requires Garmin connection. UI handles missing data gracefully | Yes — claim is accurate and gracefully degrades |
| Garmin morning check-in approval | Shows Garmin readiness data in morning check-in; lets user approve Garmin values as daily check-in | Gated on `hasGarminSignal`; falls back to manual sliders | Yes — conditional feature; fallback always works |
| Garmin activity consolidation | Merges duplicate Garmin runs using same-day distance/time matching | Internal service; no UI gate | Internal — not a claimable user feature |

### Current Description Sentence
"optional connected signals from Apple Health and Garmin"

### Approved Replacement (approved by founder 2026-05-27)
"When connected, RunSmart imports activity data from Garmin and Apple Health to update your training readiness and workout history."

**Status:** Approved. Full updated description at `distribution-os/projects/runsmart/scaffold/drafts/2026-05-27-rs-aso-001/description.txt`. Copy to `fastlane/metadata/en-US/description.txt` in a product session to apply.
