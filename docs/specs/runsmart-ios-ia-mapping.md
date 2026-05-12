# RunSmart iOS IA Mapping

Status: Approved Story 1 implementation artifact  
Story: Confirm app shell and information architecture mapping  
Date: 2026-05-12

## Purpose

This document maps the current app shell and known product areas into the future RunSmart iOS structure before any SwiftUI navigation or screen changes are made.

The goal is to preserve existing functionality while giving future stories a small, safe target for moving the app toward a cleaner, lighter, premium native iOS experience.

## Future App Areas

RunSmart iOS should organize the product around runner jobs:

- Today: what to do now.
- Plan: what is coming and why.
- Run: start, track, or log activity.
- Report: what happened and how progress is trending.
- Coach: guidance, explanation, and adjustment support.
- Profile: preferences, account, privacy, and integrations.

## Recommended App Shell

Use five primary bottom tabs:

| Tab | Primary Job | Notes |
| --- | --- | --- |
| Today | Know what to do today | Daily command center and default launch surface. |
| Plan | Follow a training plan | Weekly structure, upcoming sessions, goal progress. |
| Run | Start or log a run | Central action for GPS/manual run workflows. |
| Report | Review recent progress | Recent runs, trends, adherence, recovery history. |
| Profile | Manage preferences | Goals, account, notifications, privacy, integrations. |

Coach should be a contextual action from Today, Plan, Run review, and Report. It should not become a sixth tab unless future usage proves it needs persistent top-level navigation.

## Current To Future Mapping

| Current / Known Area | Future Area | Decision | Rationale | Risk |
| --- | --- | --- | --- | --- |
| Current app launch/root shell | Today | Move/rename later | The first screen should answer the runner's daily question: what should I do today? | Requires careful migration so existing launch behavior is not broken. |
| Score-style assessment screen | Today and Report | Split later | A readiness/score summary belongs on Today; deeper breakdown belongs in Report. | Current score logic may be resume-builder-specific and needs validation before reuse. |
| Tailor/improve-style optimization flow | Coach | Reframe later | If any AI guidance survives migration, it should feel like coaching, not document tailoring. | May be leftover product logic rather than RunSmart functionality. |
| Design/redesign flow | Profile or remove by approved decision | Hold | No obvious running-coach job maps to design/redesign unless it controls themes or presentation. | Do not remove until the user confirms whether it is leftover migration content. |
| Track/applications list flow | Report | Move/rename later | Tracking completed work and history belongs in Report. | Existing implementation appears unrelated to runs and needs product review. |
| Existing Profile screen | Profile | Preserve and simplify later | Account, preferences, privacy, integrations, and goal settings belong here. | Profile can become overloaded if integrations and settings are not grouped. |
| Goal wizard prototype | Plan and Profile | Preserve intent | Goal setup affects training plan and user preferences. | File may not be part of active project; confirm before implementation. |
| AI chat/guidance | Coach | Contextualize | Coach should explain plans, recovery, workouts, and progress in short useful guidance. | Needs guardrails to avoid generic or overconfident advice. |
| Future GPS run tracking | Run | Add in later story | Starting/pausing/finishing runs is a core action. | Requires location permission and real-device background GPS validation. |
| Future manual run logging | Run | Add in later story | Manual logging keeps app useful without GPS or integrations. | Needs simple forms and good empty/error states. |
| Future Apple Health / HealthKit integration | Profile, Today, Report | Prepare only | Permission and connection state belongs in Profile; summaries can feed Today/Report. | Do not implement until privacy strings/capabilities are approved. |
| Future Garmin integration | Profile, Today, Report | Prepare only | Connection state belongs in Profile; imported activity can feed Today/Report. | External API and auth flow are out of scope now. |

## Area Ownership

### Today
- Next workout or recommended action.
- Readiness/recovery summary.
- Short coach cue.
- Recent run highlight.
- Primary action: start run, log run, or view plan.

### Plan
- Goal and current training block.
- Week overview.
- Upcoming workouts.
- Plan adjustment explanations.
- Goal wizard entry or edit goal action.

### Run
- Start GPS run.
- Log manual run.
- Active run state.
- Pause/resume/finish.
- Post-run summary and notes.

### Report
- Recent progress.
- Run history.
- Weekly/monthly trends.
- Plan adherence.
- Readiness and recovery history.

### Coach
- Contextual explanations from Today, Plan, Run review, and Report.
- Recovery and workout guidance.
- Plan adjustment rationale.
- Short, specific, data-aware copy.

### Profile
- Runner preferences.
- Goal settings.
- Account and sign-in.
- Notifications.
- Privacy.
- Future integration connection states.
- Subscription or credits only if still relevant to RunSmart.

## Preserve Existing Functionality Rule

Future implementation stories must map each existing user-visible feature before moving or hiding it:

1. Current location.
2. Future destination.
3. Preserve, move, rename, or deprecate.
4. User impact.
5. QA check.

No feature should be removed simply because it does not fit the new IA. If it appears unrelated to RunSmart, mark it for product decision first.

## Implementation Order

1. Confirm authoritative project and product identity.
2. Create or adjust app shell labels only after mapping is approved.
3. Introduce Today as the default command center.
4. Separate Plan from Report.
5. Add Run entry points without changing GPS behavior.
6. Place Coach contextually.
7. Prepare Profile for integrations without implementing them.

## QA Notes For Future Stories

- Verify existing tabs and flows remain reachable after each navigation change.
- Test small iPhone layout before widening scope.
- Keep dark mode readable because the current app forces dark styling.
- Use manual QA for navigation stories unless unit-testable routing logic is introduced.
- Do not claim TestFlight readiness until bundle id, signing, app name, permissions, and capabilities are confirmed.

## Story 1 Acceptance

- [x] Current and known app areas are mapped to future IA.
- [x] Today, Plan, Run, Report, Coach, and Profile ownership is defined.
- [x] Existing functionality is preserved by rule.
- [x] Garmin and Apple Health are prepared for but not implemented.
- [x] Future implementation order is small and reviewable.
