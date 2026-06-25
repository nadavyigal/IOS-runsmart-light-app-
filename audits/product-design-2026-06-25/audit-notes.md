# RunSmart iOS Product Design Audit

Date: 2026-06-25
Device: iPhone 17 simulator, dark mode
Mode: DEBUG demo / onboarding replay, plus non-demo sign-in launch
Destination: Local folder

## Audit Scope

This audit reviewed the current RunSmart iOS experience from captured simulator evidence:

- First-run entry: sign-in and onboarding goal selection
- Core authenticated tabs: Today, Plan, Run, Report, Profile
- Key secondary surfaces: Flex Week and Garmin Wellness
- Run workflow: pre-start, location permission, active recording, saved run summary

Screenshots are in `screenshots/`.

## Step List

1. `12-sign-in.jpg` — Sign-in entry point. Health: strong.
2. `13-onboarding-goal.jpg` — Onboarding goal selection. Health: strong.
3. `01-today.jpg` — Today overview and next workout. Health: good with layout risk.
4. `02-plan.jpg` — Weekly plan. Health: good with bottom-content crowding.
5. `03-flex-week.jpg` — Flex Week reason picker. Health: strong with CTA-state risk.
6. `04-run-prestart.jpg` — Run pre-start. Health: strong.
7. `05-location-permission.jpg` — Location permission prompt. Health: strong.
8. `06-run-active.jpg` — Active run recording. Health: good with safety risk.
9. `07-run-saved.jpg` — Post-run saved summary. Health: mixed.
10. `08-report-runs.jpg` — Report / Runs. Health: good with list crowding.
11. `09-report-reports.jpg` — Report / Reports. Health: strong.
12. `10-profile.jpg` — Profile and connected services. Health: good.
13. `11-garmin-wellness.jpg` — Garmin Wellness detail. Health: good with readability risk.

## Strengths

- RunSmart feels visually distinct and premium. The dark, high-contrast visual system, lime action color, rounded cards, and `RS` identity are consistent across the app.
- The app usually makes the next action obvious: Sign in with Apple, Continue, Start Run, Flex Week, and Explain this run all have clear intent.
- Sign-in includes visible HealthKit disclosure on the first screen, which supports trust and App Review clarity.
- Onboarding starts with a concrete running goal instead of abstract setup, which keeps new-user effort low.
- The run pre-start screen is especially clear: GPS readiness, route/pace/time benefits, and the large Start Run button all reinforce the main job.
- The location permission purpose string is specific: route, pace, distance, and benchmark-route progress are named plainly.
- Report / Reports uses understandable cards and scores without feeling overloaded.
- Profile gives Garmin, Garmin Wellness, HealthKit, preferences, and account management a clear home.

## UX Risks

1. Bottom tab bar overlaps or hides content on several screens.
   Evidence: Today, Plan, Report / Runs, Post-run summary, Garmin Wellness.
   Impact: Users can miss lower content, explanatory text, and controls; it also makes dense lists feel cramped.
   Recommendation: Add enough bottom padding/safe-area inset to scrollable content for the full tab bar height plus breathing room. Recheck all tab roots and secondary screens that keep the tab bar visible.

2. Finish ends a run immediately.
   Evidence: Active Run -> Finish immediately produced `RUN SAVED` with a 0.00 km run.
   Impact: A single accidental tap can end and save a run. This is high-friction to recover from during real outdoor use.
   Recommendation: Use a confirmation sheet, hold-to-finish, or slide-to-finish pattern. Keep Pause as a single tap; make Finish more deliberate.

3. Active run keeps the full tab bar visible.
   Evidence: `06-run-active.jpg`.
   Impact: During a run, accidental navigation is possible and the bottom bar competes with Pause, Finish, and Coach.
   Recommendation: Consider hiding tab navigation during active recording or requiring confirmation before leaving the run screen.

4. Post-run summary overstates completion for a zero-distance run.
   Evidence: `07-run-saved.jpg` shows `0.00 km`, `1 pts`, and positive coaching copy.
   Impact: Users may distrust reports if a permission/test/accidental run receives celebratory analysis.
   Recommendation: Add a minimum-valid-run state. For very short or zero-distance runs, explain that it was saved but may not count toward training analysis unless the user confirms.

5. Flex Week Continue appears active before a reason is clearly selected.
   Evidence: `03-flex-week.jpg`.
   Impact: Users may tap Continue without understanding whether a default reason is selected or whether they must choose one.
   Recommendation: Make selected state unmistakable, disable Continue until selection, or label the default choice as selected.

6. Profile connected-service statuses are semantically uneven.
   Evidence: `10-profile.jpg`.
   Impact: Green dots for Connected/On and grey dot for View mix status and action in the same visual pattern.
   Recommendation: Separate connection status from action labels, for example `Connected` plus a chevron/action, or make `View` a clear action without a status dot.

7. Garmin Wellness truncates high-value explanation text.
   Evidence: `11-garmin-wellness.jpg` readiness copy cuts off after "controlled temp...".
   Impact: Health guidance loses nuance exactly where users need confidence.
   Recommendation: Allow the top metric rows to expand vertically or move longer interpretation into a secondary line/detail.

## Accessibility Risks

1. Text contrast may be weak for secondary labels on dark cards.
   Evidence: Today, Profile, Garmin Wellness, Post-run summary.
   Visible risk: Small grey/purple labels and metadata are low-emphasis and may miss WCAG contrast, especially on blurred material cards.
   Needs verification: Run contrast checks against actual rendered colors and dynamic backgrounds.

2. Color carries too much status meaning in places.
   Evidence: Profile service dots, run readiness/status colors, report scores.
   Visible risk: Connected, View, On, score quality, and readiness depend heavily on colored dots/badges.
   Recommendation: Keep text labels next to color states and avoid relying on dot color alone.

3. Bottom overlap may become worse with Dynamic Type.
   Evidence: Multiple screens already collide with the tab bar at default size.
   Needs verification: Test larger Dynamic Type sizes and Bold Text.

4. Dense bottom controls during active run need touch-target verification.
   Evidence: Pause, Finish, Coach sit just above persistent tab navigation.
   Needs verification: Confirm targets meet comfortable outdoor-use size and spacing, including one-handed use.

5. VoiceOver ordering was not verified.
   Evidence limit: Runtime snapshots show labels for many controls, but this audit did not run VoiceOver.
   Recommendation: Test reading order for tab screens, segmented controls, permission-adjacent flows, and active run controls.

## Recommendations

1. Fix scrollable bottom padding globally around the custom tab bar.
2. Add a deliberate guard for ending a run.
3. Hide or protect tab navigation while actively recording.
4. Add short/invalid-run handling before analysis language.
5. Tighten Flex Week selection and Continue states.
6. Separate connected-service status from action labels.
7. Recheck text contrast and Dynamic Type on the dark card system.

## Evidence Limits

- This audit used screenshots and UI snapshots, not full VoiceOver, Dynamic Type, physical-device, battery, outdoor GPS, or real Garmin/HealthKit data testing.
- Sign in with Apple was not completed; the sign-in screen was captured only.
- Onboarding was captured through the DEBUG onboarding replay path.
- Demo data may differ from live production data density and error states.
- The app was tested on one simulator size. Smaller phones and larger accessibility sizes still need direct review.

## Verification

- Debug simulator build and launch passed through XcodeBuildMCP.
- Demo-mode navigation worked across Today, Plan, Run, Report, Profile, Flex Week, and Garmin Wellness.
- Non-demo launch reached Sign in.
- Onboarding replay launch reached the Goal step.
- One known build warning appeared: `HKWorkout` initializer deprecation in `HealthKitSyncService.swift`.
