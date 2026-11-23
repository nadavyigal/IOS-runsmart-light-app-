# 2026-11-23: coach_message OpenAI model tiers (draft PR, not deployed)

Current Phase: OpenAI model migration before the 2027-01-14 shutdown of gpt-4.1-mini.
Active Story: coach_message reads OPENAI_MODEL_FAST, then OPENAI_MODEL, then gpt-4.1-mini; reasoning effort env; usage logs.
Next Recommended Story: fix flex_week 4 s timeout and 900-token cap (falls back on every model today), then set OPENAI_MODEL_FAST.
Blockers: function not deployed (by design); needs founder yes to merge and deploy.
Last Validation: deno test 22 passed; smoke debrief 5/5 on gpt-4.1-mini, gpt-6-luna, gpt-6.2-sol; flex_week 0/3 live on all.
Last Updated: 2026-11-23

# 2026-11-23: Coach v2 Batch B database applied to production

Current Phase: Coach Experience v2, Phase 1 code complete; Batch A and Batch B migrations applied to prod (3 Batch B files).
Active Story: Ledger update: M2a, M2b and workout_adherence_state applied with prod versions.
Next Recommended Story: Nadav: APNs key and secrets, deploy coach_notify and coach_evening_summary, webhooks, crons; then TF-1.
Blockers: Push stays silent until APNS_* and COACH_NOTIFY_SECRET are set and the functions, webhooks and crons exist.
Last Validation: 3 prod SQL md5s match repo files; internal functions not client-callable; RLS on 4 new tables; counts query runs.
Last Updated: 2026-11-23

# 2026-11-23: Coach v2 C7.6 evening summary with counts (PR, Batch B)

Current Phase: Coach Experience v2, Batch B. C7.6 iOS and web twin PRs open; 20261122120000 written, not applied.
Active Story: C7.6: coach_evening_summary hourly cron, 20:00 counts push, quiet-hours Yesterday, T2 Missed today filter, shared adherence SQL.
Next Recommended Story: Overseer review of C7.6; then Nadav applies Batch B and runs TF-1 with the kill-switch drill.
Blockers: Nadav: Batch B apply (M2a, M2b, C7.6 file), secrets, webhooks, flush and hourly crons, both deploys.
Last Validation: workout_adherence_state SQL PASS + rollback; 126 Deno pass; iOS C7.6 classes pass; drift CLEAN 27.
Last Updated: 2026-11-23

# 2026-11-23: Coach v2 C7.5 push sender, M2b (ready PR, rebased after C7.10 merged)

Current Phase: Coach Experience v2, Batch B. C7.10 merged; C7.5 iOS #250 and web #180 ready, rebased on main; M2b written, not applied.
Active Story: C7.5: coach_notify (runs, flags, notes, replies), _shared/notify.ts, quiet hours, dedupe, burst collapse, M2b log and deferred tables.
Next Recommended Story: Founder yes to merge C7.5 (#250, #180); then C7.6 evening summary on notify.ts.
Blockers: Nadav: Batch B apply (M2a, M2b), APNs and COACH_NOTIFY_SECRET secrets, four webhooks, flush cron, coach_notify deploy.
Last Validation: After rebase: M2b + M2a SQL PASS; 105 Deno pass (45 new); RemotePush iOS 61 run, 0 failed; drift CLEAN 26.
Last Updated: 2026-11-23

# 2026-11-23: Coach v2 C7.14 notification settings, coach and athlete (ready PR)

Current Phase: Coach Experience v2, Batch B. C7.14 PR #247 ready; no migration. C7.10 merged; turnOn wired to its T6/P10 flow.
Active Story: C7.14: coach T5 (Coach tab menu) and athlete (My coach) toggles, quiet hours, permission line, v2-gated.
Next Recommended Story: Overseer merge of C7.14; then C7.5 push sender and C7.6 evening summary.
Blockers: Sally light copy review of the athlete section header; APNs setup for device tests.
Last Validation: 20 coach test classes 327 passed, 0 failed (iPhone 17 Pro, iOS 26.5); 12 fixture screenshots (default, XXL, AX3, RTL, denied).
Last Updated: 2026-11-23

# 2026-11-23: Coach v2 C7.10 remote push foundation, M2a (draft PR)

Current Phase: Coach Experience v2, Batch B start. C7.10 PRs open in iOS and web twin; M2a written, not applied; APNs secrets not set.
Active Story: C7.10: push_tokens + notification_prefs (M2a), _shared/apns.ts, dev-only push_selftest, T6/P10 prompts, tap router, sign-out unregister.
Next Recommended Story: Overseer review of C7.10; then C7.5 push sender (M2b) on top of apns.ts.
Blockers: Nadav: APNs .p8 key, Push capability on the App ID (signed builds need it), APNS_* secrets, apply M2a in Batch B.
Last Validation: Review fixes: shared APNs signer, sign-out drops device token on failure; 61 Deno pass; full iOS suite passes; drift CLEAN 25.
Last Updated: 2026-11-23

# 2026-11-23: Coach v2 Batch A applied to production

Current Phase: Coach Experience v2, R1 Batch A applied to prod (7 files); Batch B track in review (C7.10 #248, C7.14 #247).
Active Story: Ledger update: Batch A rows applied with prod versions, pre-v2 rows verified, M13 not needed, prod-only drift logged.
Next Recommended Story: Merge C7.10 then C7.14; add athlete_display_name_placeholder to both repos; add a pilot coach, then TF-1a.
Blockers: v2 stays off until Nadav adds a row to coach_v2_pilot_coaches or testers run TestFlight builds; APNs setup for push.
Last Validation: 7 prod SQL md5s match repo files; old suites pass on full schema locally; advisors show no new findings; drift CLEAN 24.
Last Updated: 2026-11-23

# 2026-11-22: Coach v2 C7.16 beginner milestones and one-tap praise (draft PR)

Current Phase: Coach Experience v2, R1 last story. C7.16 draft PR open in iOS only; no migration (STEP 1 check), so no web twin.
Active Story: C7.16: First run, First full week, Longest run, Quiet 3 days tags on Coach Today; 👏 🔥 Great job reactions via coach feedback.
Next Recommended Story: Overseer review of C7.16; then Nadav applies Batch A and runs TF-1a on a phone.
Blockers: Nadav applies Batch A (M0, M0b, M5a, M1a, M3, M4, M1b, M5b) before v2 shows anything; none for this PR.
Last Validation: 9 coach test classes 210 passed, 0 failed (iPhone 17, iOS 26.5); 3 milestone screenshots; overseer review: no blockers. After C7.7 merge: 11 coach test classes 222 passed, 0 failed; drift CLEAN 24 files.
Last Updated: 2026-11-23

# 2026-11-23: Coach v2 C7.7 athlete replies to a coach note (ready PR, C7.11 catch-up)

Current Phase: Coach Experience v2, R1 Batch A, C7.7. iOS #245 and web #176 ready; main merged after C7.11; M4 not applied.
Active Story: C7.7 catch-up: CI rows list M5b, reply read in C7.11 parity test, removal case in replies test, ledger M5b merged.
Next Recommended Story: Overseer merges C7.7 (iOS #245, then web #176); then C7.16 milestones.
Blockers: Nadav applies Batch A (M0, M5a, M1a, M3, M1b, M5b, M4) after the Grok Bot audit and the 1.2.6 regression.
Last Validation: SQL coach_feedback_replies, kill_switch, coach_link_end (with and without M4) PASS; drift CLEAN 24 files; coach Swift classes.
Last Updated: 2026-11-23

# 2026-11-22: Coach v2 C7.11 coach removes an athlete, M5b (draft PR)

Current Phase: Coach Experience v2, R1 wave 4, lane B. C7.11 in draft PRs (iOS + web twin); M5b written, not applied.
Active Story: C7.11: Remove {Athlete}, end_coach_link shared with leave_coach, one-time athlete line, left/removed events.
Next Recommended Story: C7.16 milestones (lane B) after C7.1/C7.2; Batch A apply after the Grok Bot audit.
Blockers: Nadav applies Batch A incl. M5b; Sally light copy review of the remove sheet lines.
Last Validation: After C7.4 catch-up: SQL coach_link_end, kill_switch, athlete_run_flags, 1.5 leave_coach PASS; 20 coach classes 300 passed, 0 failed.
Last Updated: 2026-11-22

# 2026-11-22: Coach v2 C7.4 pain / something off flag (draft PR)

Current Phase: Coach Experience v2, R1 wave 4, lane A. C7.4 draft PR open in iOS and web; M1b not applied.
Active Story: C7.4: M1b flags table and RPCs, new_flags in roster summary, P7 flag row, pain group on Coach Today.
Next Recommended Story: Overseer review of C7.4; lane B wires CoachFlagBlock into day detail; then C7.7 (lane A).
Blockers: Nadav applies Batch A (M0, M5a, M1a, M3, M1b) after the Grok Bot audit and the 1.2.6 regression.
Last Validation: SQL athlete_run_flags, kill_switch, coach_last_seen, athlete_run_sharing PASS; iOS full suite 1298 passed, 0 failed, 2 skipped.
Last Updated: 2026-11-22

# 2026-11-22: Coach v2 C7.3 AC4 coach day detail shows effort and note (draft PR)

Current Phase: Coach Experience v2, R1 wave 4, lane B. C7.3 AC4 follow-up in a draft PR; SwiftUI only, no migration.
Active Story: C7.3 AC4: coach day detail shows "Effort 7/10" and the athlete's quoted note under Actual, flag-gated.
Next Recommended Story: C7.11 coach removes an athlete (lane B, M5b), after this PR merges.
Blockers: None for this PR. Batch A (M0, M5a, M1a, M3) still waits for Nadav; effort and notes show only after M1a.
Last Validation: 17 coach test classes 259 passed, 0 failed, 1 skipped (iPhone 17, iOS 26.5); 6 fixture screenshots. Full suite not run (23 min).
Last Updated: 2026-11-22

# 2026-11-22: Coach v2 C7.2 "New since last visit" markers and coach events merged

Current Phase: Coach Experience v2, R1 wave 3, lane B. C7.2 merged in iOS and web with founder yes; M3 not applied.
Active Story: C7.2: M3 seen and events tables, four RPCs, New to review group, "{n} new" markers, outbox, analytics.
Next Recommended Story: C7.11 (lane B); it logs left/removed events into M3.
Blockers: Nadav applies Batch A (M0, M5a, M1a, M3) after the Grok Bot audit and the 1.2.6 regression.
Last Validation: SQL 5 suites pass on local Postgres; iOS full suite 1255 passed, 0 failed, 1 skipped (iPhone 17, iOS 26.5).
Last Updated: 2026-11-22

# 2026-11-22: Coach v2 C7.3 RPE and note sharing merged

Current Phase: Coach Experience v2, R1 wave 3, lane A. C7.3 merged in iOS and web with founder yes; M1a not applied.
Active Story: C7.3 sync RPE and notes to the coach behind consent v2, hide toggle, 14-day RPE backfill, bidi helpers.
Next Recommended Story: C7.4 (lane A); lane B wires "Effort 7/10" and the note into coach day detail.
Blockers: Nadav applies Batch A (gate, M5a, M1a) after the Grok Bot audit and the 1.2.6 regression.
Last Validation: iOS full suite 1255/0 (2 skips); SQL athlete_run_sharing, kill_switch, consent, coach_read PASS; Deno 6/6.
Last Updated: 2026-11-22

# 2026-11-22: Coach v2 C7.1 Coach Today with 7-day dots merged

Current Phase: Coach Experience v2, wave 2 (lane B). C7.1 merged with founder yes; SwiftUI only, no migration, no new RPC.
Active Story: C7.1 built: dots, groups, chips, no re-sort pill, states, VoiceOver, RTL; passed overseer review.
Next Recommended Story: Wave 3: C7.2 "New since last visit" (lane B, writes M3) and C7.3 (lane A, writes M1a).
Blockers: None for lane B; C7.2 needs Batch A M3 written, not applied.
Last Validation: Full suite 1209 passed, 0 failed on iPhone 17 simulator (iOS 26.5); 40 new C7.1 tests.
Last Updated: 2026-11-22

# 2026-11-22: Coach v2 C7.8 consent v2 and one-time notice merged

Current Phase: Coach Experience v2, R1 wave 2, lane A. C7.8 merged in iOS and web with founder yes; M5a not applied.
Active Story: C7.8 consent v2: M5a migration, ack and status RPCs, P8 and P9 sheets, leave sheet lines, analytics.
Next Recommended Story: C7.3 (lane A), gated by coach_v2_sharing_allowed.
Blockers: Nadav applies Batch A (gate, then M5a) after the Grok Bot audit and the 1.2.6 regression.
Last Validation: SQL 8 suites pass on local Postgres; iOS targeted 104/0; full suite 1187/0 before simulator died at 24 min.
Last Updated: 2026-11-22

# 2026-11-22: Coach v2 C7.0 gate, kill switch and pilot allowlist merged

Current Phase: Coach Experience v2, wave 1 (Gate lane). C7.0 merged in iOS and web with founder yes; M0 not applied.
Active Story: C7.0 passed overseer review after round 1 (capability report, no report before flags read).
Next Recommended Story: Wave 2 after C7.0 merges: C7.8 (lane A), C7.1 (lane B), C7.10 (lane C).
Blockers: Nadav applies M0 in Batch A after the Grok Bot audit and 1.2.6 regression.
Last Validation: iOS full suite 1169/0 (1 skip) on iOS 26.5 after round 1; SQL and Deno unchanged and passing.
Last Updated: 2026-11-22

# 2026-11-21: Coach v2 C0.2 migration ledger, drift script, metrics doc

Current Phase: Coach Experience v2, R0 ground truth. C0.2 docs-only draft PR open; no product code or SQL.
Active Story: C0.2 done: ledger, drift script (17 files, 0 drift), metrics doc. Reviewed; merging with founder yes.
Next Recommended Story: C7.0 gate plus kill switch (PR #234, reviewed), then wave 2: C7.8 and C7.1.
Blockers: N2: 6 v1 coach migrations (20261118100000 to 180000) possibly unapplied in prod.
Last Validation: drift script exit 0 on both origin/main trees; scratch-copy test exits 1; 0 em dashes in new docs.
Last Updated: 2026-11-21

# 2026-11-20: Coach Experience v2 refined plan (C0.1)

Current Phase: 1.2.6 (46) in App Review; Coach v2 refined plan written as a docs-only draft PR.
Active Story: C0.1 refined plan; N1 decided B (dark App Store build, per-coach allowlist table). Waiting for plan approval.
Next Recommended Story: C0.2 migration mirror check plus C7.0 gate, kill switch and pilot-coach allowlist, after plan approval.
Blockers: Founder plan approval; confirm 6 v1 coach migrations applied in production; APNs setup.
Last Validation: Docs only. Claims checked against origin/main 4a016b4 by code read; no build or tests run.
Last Updated: 2026-11-20

# 2026-11-23: Debrief event and debug compare (#240, base main)

Current Phase: debrief stack: #232 and #237 merged to main; #240 retargeted to main, last of the stack.
Active Story: #240 `run_debrief_generated` with trigger, no event on cancel, live-only compare; CodeRabbit finding fixed (cancelled attempt skips event).
Next Recommended Story: Nadav merges #240 when CI is green; then PostHog flag `runsmart-on-device-debrief` and the device test.
Blockers: CI needs a macOS runner (one run was cancelled for GitHub capacity).
Last Validation: 2026-11-23 debrief tests 35/0 local; earlier full suite 1310 passed, 0 failed, 2 skipped.
Last Updated: 2026-11-23

# 2026-11-22: On-device debrief, opt-in Settings toggle (draft PR, stacked on #232)

Current Phase: 1.2.6 (46) live; Apple membership plan PR 2. Founder chose a Settings toggle on 2026-11-22.
Active Story: `OnDeviceDebriefGenerator` (Foundation Models, English only, off by default); toggle "Post-run summary on this iPhone" in Run preferences.
Next Recommended Story: PR 3, `run_debrief_generated` PostHog event and debug compare mode; then founder rates 10 real runs.
Blockers: toggle not seen on screen yet: needs a signed-in English iPhone with Apple Intelligence on.
Last Validation: 2026-11-22 full suite 1158 passed, 0 failed, 1 skip; OnDeviceDebriefTests he 9/0, en 8/0 + 1 skip; iPhone 17 iOS 26.5 sim.
Last Updated: 2026-11-22

# 2026-11-21: Debrief generator protocol (draft PR, no behavior change)

Current Phase: 1.2.6 (46) live on the App Store; Apple membership plan PR 1 of the on-device debrief experiment.
Active Story: `RunDebriefGenerating` protocol and `RunDebriefPipeline`; cloud debrief moved into `CloudRunDebriefGenerator`, same order and fallback.
Next Recommended Story: PR 2, on-device generator as a small opt-in (English, eligible devices); needs Nadav's call on the opt-in surface.
Blockers: none for this PR; draft only, Nadav merges.
Last Validation: 2026-11-21 full suite 1150 passed, 0 failed, 1 opt-in skip; new RunDebriefPipelineTests 5/0; iPhone 17 iOS 26.5 sim.
Last Updated: 2026-11-21

# 2026-11-20: RunSmart 1.2.6 (46) submitted to App Review

Current Phase: 1.2.6 (46) Waiting for Review; auto-release to all users on approval. PR #227 merged (8f181b1).
Active Story: None; waiting on Apple review.
Next Recommended Story: Add human-coach line to web privacy policy; after approval, revoke reviewer coach link 3a4130fd.
Blockers: None for review. Age rating Location Sharing answers due 2027-01-15.
Last Validation: full suite 1145/0; archive 46 backend check passed; ASC shows 1.2.6 Waiting for Review.
Last Updated: 2026-11-20

# 2026-11-19: Release 1.2.6 (46) to App Store review

Current Phase: Release 1.2.6 (46): Coach Mode on for all Release builds, plus Live Activity and weekly widget.
Active Story: ASC 1.2.6 draft filled with build 46, What's New, review notes; not submitted.
Next Recommended Story: Founder creates reviewer coach and athlete accounts, approves the coach_profiles insert, then Submit for Review.
Blockers: Reviewer linked to pilot coach (done). Privacy policy line, PR #227 merge and Submit need founder.
Last Validation: full suite 1145/0 (1 opt-in skip); CoachModeTests 19/0 after review fix; archive 46 passed backend check.
Last Updated: 2026-11-19

# 2026-11-19: Live Activity, Codex review fixes on main

Current Phase: Live Activity upgrade merged (#220 to #225); this PR fixes three open Codex findings.
Active Story: Widget weekly km refreshes on run changes and counts merged runs once; debrief link opens the run's report.
Next Recommended Story: Founder device test of docs/qa/live-activity-device-checklist.md.
Blockers: App Group portal setup before any device build; physical-iPhone checklist.
Last Validation: full suite 1145 passed, 0 failed; simulator: finished card after Done opens that run's report.
Last Updated: 2026-11-19

# 2026-11-19: Guided workout pace on Live Activities

Current Phase: Live Activity follow-up after PRs #220–#224.
Active Story: The existing Live Activity compares pace with the current guide step’s target and shows neutral pace when that step has no target.
Apple Developer: Verified App Group `group.com.runsmart.lite` on team `8VC4R5M425` for both the app and Live Activity extension.
Last Validation: 29 Live Activity coordinator tests passed on the iPhone 17 Pro simulator, including work, recovery, and guide-completion transitions.
Next Recommended Story: Regenerate provisioning profiles for both identifiers and run the physical-iPhone checklist on a Dynamic Island device.

# 2026-11-19: Live Activity PRs reviewed and fixed (parallel track)

Current Phase: Live Activity upgrade; stacked draft PRs #220 to #224 reviewed (two models on #221), all findings fixed.
Active Story: Founder device test of docs/qa/live-activity-device-checklist.md, then review #220 first.
Next Recommended Story: Follow-up: interval workouts should compare pace with the current guide step's target.
Blockers: App Group portal setup before any device build; physical-iPhone checklist; #220 needs current-head review.
Last Validation: full suite 1138 passed, 0 failed (iPhone 17 simulator).
Last Updated: 2026-11-19

# 2026-11-19: Live Activity PR 5, in-app switch (parallel track)

Current Phase: Live Activity upgrade done in code; stacked draft PRs #220 to #224 await founder device test. Coach Mode pilot unchanged.
Active Story: PR 5 in-app Live Activity switch in Run preferences, plus the full device checklist.
Next Recommended Story: Founder runs docs/qa/live-activity-device-checklist.md on an iPhone, then reviews #220 first.
Blockers: App Group portal setup; Tier 2 reviews for #221 (entitlements) before merge; physical-iPhone checks.
Last Validation: full suite 1136 passed, 0 failed (iPhone 17 simulator).
Last Updated: 2026-11-19

# 2026-11-19: Live Activity PR 4, small weekly widget (parallel track)

Current Phase: Live Activity upgrade, stacked draft PRs #220, #221, #222; PR 4 widget now. Coach Mode pilot unchanged.
Active Story: PR 4 small home-screen widget: weekly km ring from App Group snapshot, Run in progress while live.
Next Recommended Story: PR 5, in-app Live Activity on/off switch and polish.
Blockers: App Group must be enabled in the developer portal before a device build; device checklist pending.
Last Validation: full suite 1134 passed, 0 failed; simulator: widget reads the App Group snapshot.
Last Updated: 2026-11-19

# 2026-11-19: Live Activity PR 3, hybrid B/A layout (parallel track)

Current Phase: Live Activity upgrade, stacked draft PRs #220 (fixes) and #221 (App Group); PR 3 layout now. Coach Mode pilot unchanged.
Active Story: PR 3 hybrid layout: target-pace run shows pace vs target and goal ring; free run shows time and distance.
Next Recommended Story: PR 4, small home-screen widget with weekly km ring from the App Group snapshot.
Blockers: Lock Screen buttons and background GPS still need a physical iPhone; simulator checks passed.
Last Validation: full suite 1129 passed, 0 failed; simulator: island Pause/Resume work, both layouts render.
Last Updated: 2026-11-19

# 2026-11-19: Live Activity PR 1, App Group and widget snapshot (parallel track)

Current Phase: Live Activity upgrade, stacked draft PRs; PR 2 fixes open as #220. Coach Mode pilot below unchanged.
Active Story: PR 1 App Group group.com.runsmart.lite and weekly widget snapshot, no UI.
Next Recommended Story: PR 3, hybrid B/A Live Activity layout (target pace run vs free run).
Blockers: App Group must be enabled for both bundle IDs in the developer portal before a device build.
Last Validation: full unit suite on iPhone 17 Pro simulator, 1125 passed, 0 failed.
Last Updated: 2026-11-19

# 2026-11-19: Live Activity PR 2, fixes with no visual change (parallel track)

Current Phase: Live Activity upgrade; founder chose hybrid B/A; PR 2 (fixes) built first. Coach Mode pilot below unchanged.
Active Story: PR 2 Live Activity fixes: intents in app target, app-shell coordinator, crash adoption, throttle, stale state.
Next Recommended Story: PR 1, App Group and shared snapshot store; then PR 3, 4, 5 stacked.
Blockers: Lock Screen buttons, background GPS, force-quit need a physical iPhone (docs/qa/live-activity-device-checklist.md).
Last Validation: full unit suite on iPhone 17 Pro simulator, 1120 passed, 0 failed; 21 new Live Activity tests; review fix applied.
Last Updated: 2026-11-19

# 2026-11-19: Coach Mode pilot TestFlight build 1.2.6 (44)

Current Phase: Coach Mode pilot launch; flag on in TestFlight (#217 merged), migrations on production.
Active Story: Upload 1.2.6 (44) to TestFlight for the two-phone pilot test.
Next Recommended Story: Flag the coach account, install on two phones, run tasks/coach-pilot-testing.md.
Blockers: None in code; web-repo migration mirror still open.
Last Validation: archive 1.2.6 (44) verified against production backend; full unit suite 1099 passed.
Last Updated: 2026-11-19

# 2026-11-19: Coach Mode pilot, on in TestFlight builds

Current Phase: Coach Mode pilot launch; all 21 stories merged and all Coach Mode migrations on production (checked 2026-11-19).
Active Story: Coach Mode turns on in TestFlight builds, stays off in the App Store build; two-phone guide in tasks/coach-pilot-testing.md.
Next Recommended Story: Upload a TestFlight build, flag the coach account, run the two-phone test script.
Blockers: TestFlight upload needs founder yes; migrations still to mirror to the web repo.
Last Validation: full unit suite on iPhone 17 simulator, 1099 passed, 0 failed.
Last Updated: 2026-11-19

# 2026-11-18: Coach Mode pre-pilot stories all merged

Current Phase: Coach Mode pilot; all 21 pre-pilot stories merged (6.3 #212, 3.4 #213, follow-up #210).
Active Story: None. Six migrations wait for founder apply and web-repo mirror, listed in tasks/coach-mode-status.md.
Next Recommended Story: Founder applies migrations 20261118100000 to 20261118180000 in order, then pilot QA on device.
Blockers: Migrations not applied.
Last Validation: Full unit suite 1097 passed, 0 failed on #210 after merging main with 6.3 and 3.4.
Last Updated: 2026-11-18

# 2026-11-18: 3.2 follow-up, Plan scrolls to standalone week notes (#210)

Current Phase: Coach Mode pilot; #210 merged with main after #211, no migration.
Active Story: Plan scrolls to a week note whose week has no workouts; cancellation-aware read test. This Week target dropped, #211 owns it.
Next Recommended Story: Founder merges #210; then #212 (6.3) and #213 (3.4).
Blockers: None.
Last Validation: iPhone 17 simulator, full unit suite 1086 passed, 0 failed, including testACancelledViewTaskThenReopenStillRetriesTheRead.

# 2026-11-18: Coach Mode story 3.4, coach welcome note

Current Phase: Coach Mode pilot, story 3.4 on `feat/coach-welcome-note`.
Active Story: Default welcome editor, unread per-athlete overrides, signed welcome card on Today; rejoining athletes get a fresh welcome.
Next Recommended Story: Review the PR, mirror the migration to the web repo, and apply it after review.
Blockers: Founder review and migration application pending.
Last Validation: iPhone 17 full unit suite, 1,093 passed, 0 failed, after code-reviewer fixes (rejoin, name cap, per-athlete template). SQL suite runs in CI.

# 2026-11-18: Coach Mode story 6.3, athlete hides one run's map

Current Phase: Coach Mode pilot, story 6.3 on `feat/hide-run-map` (#212); migration `20261118170000_set_run_route_hidden.sql` waits for founder apply.
Active Story: Per-run "Hide map from {Coach}" on post-run and run detail; hide before upload withholds the route; owner RPC flips shared and hidden.
Next Recommended Story: Founder merges #212, applies the migration and mirrors it to the web repo; then 3.4 (#213).
Blockers: Migration not applied; until it is, hiding an uploaded map fails and stays queued.
Last Validation: iPhone 17 simulator, full unit suite 1089 passed, 0 failed; code-reviewer approved; SQL suite runs in CI.

# 2026-11-18: Two-model sensitive PR review

Current Phase: Review workflow simplification requested by the founder.
Active Story: Keep path classification and PR checks; remove the manual Sensitive gate. Sensitive PRs use two independent distinct-model reviews and passing checks.
Blockers: None. Two-model reviews are recorded on the PR; Agentic OS policy is merged and the Steward automation is updated.
Last Validation: Workflow syntax and hosted checks are recorded on the PR.
Last Updated: 2026-11-18

# 2026-11-18: CI, Supabase matrix port clash

Current Phase: Coach Mode pilot; CI fix on `ci/sql-port-clash`, workflow only, no SQL.
Active Story: Preserve existing reserved ports and reserve Supabase CLI ports 54320-54329 so outbound connections never take 54322 before Postgres binds; log port owners on failure.
Next Recommended Story: Founder merges this, then re-runs SQL checks on #212 and #213.
Blockers: None.
Last Validation: Two consecutive PR runs with every Supabase migrations matrix job green (see PR).
Last Updated: 2026-11-18

# 2026-11-18: Coach Mode story 3.3, coach visible on Today and the Plan

Current Phase: Coach Mode pilot, story 3.3 on `feat/coached-by-today-plan`; migration `get_my_coach()` waits for founder apply.
Active Story: "Coached by" strip and unread coach cards on Today; coach plan title on Plan; one CoachPresence gate; hooks for 3.4/4.3/5.2/5.4.
Next Recommended Story: Founder merges #210 and this PR, applies get_my_coach.sql and mirrors it to the web repo; then 3.4.
Blockers: Migration not applied; until it is, the Plan keeps the solo title under the strip.
Last Validation: iPhone 17 simulator, full unit suite 1086 passed, 0 failed, after Codex and CodeRabbit fixes incl. one Plan scroll target per week.
Last Updated: 2026-11-18

# 2026-11-18: Coach Mode story 2.4, athlete detail

Current Phase: Coach Mode pilot foundation, story 2.4 on `feat/coach-athlete-detail`, stacked on 2.3 (#204).
Active Story: Coach opens an athlete: two-week strip, day detail with planned vs actual, matched-by-date, revoked and no-plan states. Read-only.
Next Recommended Story: Founder merges #204 then this PR; then 3.1 coach feedback.
Blockers: Stacked on #204; retarget to main after #204 merges.
Last Validation: iPhone 17 simulator, 29 coach tests passed (detail, adherence, read service, plan setup); screens rendered from sample data.
Last Updated: 2026-11-18

# 2026-11-18: Coach Mode story 2.3, athlete list review fixes

Current Phase: Coach Mode pilot foundation, story 2.3 (PR #204) review fixes.
Active Story: Rest days no longer count as planned or missed; roster sorts by status group first, so Needs attention ordering is stable.
Next Recommended Story: Founder merges #204, then 2.4 athlete detail. Race-date Gregorian fix is merged in #205.
Blockers: Current-head review and CI are being refreshed after merging #205 into this branch.
Last Validation: iPhone 17 simulator, WorkoutAdherenceTests and CoachReadServiceTests, 14 passed / 0 failed, including two new tests.
Last Updated: 2026-11-18

# 2026-11-18: Group race date written as Gregorian (follow-up to #197)

Current Phase: Coach Mode pilot foundation, follow-up fix to story 1.7.
Active Story: Group Plan race date now serializes and parses with a Gregorian calendar, whatever calendar the coach's phone uses.
Next Recommended Story: Founder merges this and #204, then 2.4 athlete detail.
Blockers: None. No migration.
Last Validation: iPhone 17 simulator, CoachPlanSetupTests and GroupPlanJoinTests 25 passed; the new test fails on the old code.
Last Updated: 2026-11-18

# 2026-11-17: Coach Mode story 1.8, group plan on join

Current Phase: Coach Mode pilot foundation.
Active Story: When an athlete taps Share for a Group Plan coach, they confirm the group plan, their phone generates it, and only then does `join_coach` run. Individual Plans still join on Share. Migration `20261117160000_lookup_invite_group_plan.sql` replaces `lookup_invite(text)` so it also returns `plan_mode` and, for a group coach, the group settings. `join_coach` is unchanged. Not applied to production. Nadav applies it. Copy the same file to `Running-coach-/v0/supabase/migrations/`.
A race more than 16 weeks out asks the generator for 16 weeks and starts the plan on the race date minus 16 weeks (the final 16 weeks). Before that date, Today keeps the existing empty-workout state. If the plan is saved and `join_coach` then fails, Retry joins again and does not generate again. Cancel leaves that new plan in place and the athlete unlinked.
Next Recommended Story: 2.2 or 6.4, not this branch.
Blockers: migration not applied. Group confirm stays hidden until it is, because an older `lookup_invite` has no `plan_mode` and the app keeps Story 1.3's immediate join.
Last Validation: iPhone 17 Pro simulator, GroupPlanJoinTests 15 passed, plus CoachLinkTests and CoachPlanSetupTests, 47 passed / 0 failed. SQL suite is in PR checks. It was not run locally: Docker would not start.
Last Updated: 2026-11-17

# 2026-11-15: Coach Mode adherence follow-up

Current Phase: Coach Mode pilot foundation.
Active Story: Make the workout completion and run association atomic, retain only one retry with the matching run and its actuals, and rank new HealthKit runs as a batch.
Next Recommended Story: Verify a real in-app run and a third-party HealthKit run produce the expected row links before implementing the Coach adherence view.
Blockers: `20261117120000_complete_run_workout.sql` must be mirrored in the web repo and applied before the updated iOS client is released. The new client uses the owner-scoped RPC for completion writes. Stage the DB migration first, validate the exact pilot build, and keep pilot participants on that build so older clients do not replay split writes. Upgrade recovery completes persisted links to incomplete active workouts using actuals from the linked run, including links older than the normal 30-day heuristic window. Legacy split payloads without a proven run association are never replayed.
Last Validation: Throwaway Postgres 17.6 passed the original workout-link test and the new atomic completion test. iOS and physical workout checks are tracked in tasks/todo.md.

# 2026-11-15: Coach Mode story 1.3, athlete joins a coach with consent

Current Phase: unchanged; Coach Mode (human coaches) epic 1, branch `feat/join-coach-consent`.
Active Story: migration `20261115091000_coach_athlete_links.sql` (table `coach_athlete_links`, RPCs `lookup_invite` returning invite id, `join_coach(code, expected_invite_id, expected_coach_id, expected_athlete_id)`, `my_coach_link`). Settings → "Join a coach" (only when not linked) leads to the code field and the consent screen. A signed-out person uses "Join a coach" on the sign-in screen, which stays on sign-in; after sign-in and any required onboarding they get an empty code field. There is no guest code entry. Share joins only the invite and coach on the consent screen for the athlete who saw it. The server returns the persisted link ID and consent timestamp. If the code now names someone else, the app shows "This code now belongs to {name}", drops the previous consent, and waits for a new Share tap. Not now does not join. Not applied to production. Nadav applies this migration himself. Do not apply an older copy. Do not mirror it to the web repo yet.
Follow-up before any pilot: Story 1.5 MUST ship athlete "Leave coach" plus a revoke RPC before the pilot. Leaving cuts off all coach access. The consent sentence "You can leave anytime in Settings" stays. Join is not held for this.
Next Recommended Story: After the founder merges 1.3, prioritize 1.5 (Leave coach) before the pilot. 1.4 adds invite links. Coached-by header is 3.3.
Blockers: migration not applied to production yet.
Last Validation: 2026-11-15, SQL coach_athlete_links.sql PASS on throwaway Postgres 17.6 after applying the current migration twice. Includes wrong-athlete rejection and equality of the persisted link identity and consent time in both RPCs.
Last Updated: 2026-11-15

# 2026-11-14: Coach Mode story 1.2, coach role and invite code

Current Phase: unchanged; Coach Mode (human coaches) epic 1, branch `feat/coach-role-invite`.
Active Story: migration `20261114210000_coach_role_and_invites.sql` (tables `coach_profiles`, `coach_invites`, RPC `get_or_create_my_invite()`), a Coach tab for flagged coaches only, and the invite section (code, link, Copy, Share). Not applied to production; Nadav applies after review. The web repo `Running-coach-` needs the same file in `v0/supabase/migrations/`. Flag a coach with `insert into coach_profiles (user_id, display_name) values ('<uuid>', 'Dana');`. "Coach" here is the human coach, unrelated to the AI coach (`coach_message`, `coaching_style`).
Next Recommended Story: 1.3 (athlete joins with consent, `coach_athlete_links`), then 1.4 (invite link opens the app).
Blockers: migration not applied to production yet.
Last Validation: SQL two-user test `supabase/tests/coach_invites.sql` passes on a throwaway Postgres 17.6 after applying the migration twice; `CoachModeTests` plus `EmailSignInTests` pass on the iPhone 17 Pro simulator.
Last Updated: 2026-11-14

# 2026-11-14: Workout completion save (story 0.1)

Current Phase: unchanged.
Active Story: completed runs mark the planned workout done. `actual_pace` is sent as integer seconds/km (no migration). Failed updates are queued and retried on launch and foreground, dropped after 5 attempts.
Next Recommended Story: Story 0.2 (match logic / `runs.workout_id` / backfill). Not this PR.
Blockers: none. Post-release check: `select count(*) from workouts where completed = true and completed_at > '<release date>';`
Last Validation: 2026-11-14, iPhone 17 simulator, the six workout-completion tests passed (`TEST SUCCEEDED`).
Last Updated: 2026-11-14

# 2026-11-13: Two Swift 6 errors-in-waiting fixed

Current Phase: unchanged; audit item 1 decided by the founder.
Active Story: RunSessionCheckpoint is nonisolated (encoded on the checkpoint queue); StravaUploadCoordinator resolves main-actor singletons inside init, not in default arguments.
Next Recommended Story: the 8 remaining main-actor warnings (LocalRunCueService, analytics, training load, route snapshot).
Blockers: none.
Last Validation: 2026-11-13 iPhone 17 iOS 26.5 full suite 862 passed, 1 skipped, 0 failed; app warnings 22 to 8, none Swift 6 errors.
Last Updated: 2026-11-13

# 2026-11-11: Repo audit, unused views removed

Current Phase: unchanged; repo hygiene pass on `claude/2026-11-11-ios-repo-audit`.
Active Story: delete 4 unreachable views, move 2 reports out of the Xcode project bundle, list the rest for review.
Next Recommended Story: founder review of docs/audits/2026-11-11-repo-audit.md, item 1 (two Swift 6 concurrency errors) first.
Blockers: none. PR #179 Tier 1, code-reviewer APPROVED, awaiting founder merge.
Last Validation: 2026-11-11 iPhone 17 iOS 26.5 full suite 862 passed, 1 skipped, 0 failed before and after.
Last Updated: 2026-11-11

## 2026-11-18 Story 3.2 follow-up, Plan scroll and read test
- Current Phase: Coach Mode Phase 3; 3.2 merged (#208), follow-up #210 open
- Active Story: Plan scrolls to any week note; cancellation-aware read test
- Next Recommended Story: 3.3 Today card and Coached-by header
- Blockers: #209 (6.2) waits for founder merge yes; migrations not applied
- Last Validation: full suite 1065 passed, 0 failed on iPhone 17 simulator
- Last Updated: 2026-11-18

## 2026-11-18 Story 6.2 coach sees route map
- Current Phase: Coach Mode Phase 6, coach route map (6.2) in review
- Active Story: 6.2 coach_get_run_route RPC and C6 map block with four states
- Next Recommended Story: 6.3 athlete hides one run's map, after 6.2 merges
- Blockers: migration 20261118140000 not applied; founder applies after review
- Last Validation: full suite 1049 passed, 0 failed; coach_run_route SQL suite runs in CI
## 2026-11-18 Story 3.2 athlete sees coach feedback
- Current Phase: Coach Mode Phase 3, athlete feedback (3.2) in review
- Active Story: 3.2 notes pinned on runs and weeks, Today badge, pending review line, My coach list
- Next Recommended Story: 3.3 Today card and Coached-by header, after 3.2 merges
- Blockers: migrations 20261118100000 and 20261118120000 not applied; founder applies after review
- Last Validation: full suite 1063 passed, 0 failed; athlete_feedback_read SQL suite runs in CI
- Last Updated: 2026-11-18

## 2026-11-18 Story 3.1 coach feedback write
- Current Phase: Coach Mode Phase 3, coach feedback (3.1) in review
- Active Story: 3.1 coach writes feedback on a run or a week, with drafts and offline queue
- Next Recommended Story: 3.2 athlete sees coach feedback, after the 3.1 PR merges and the migration is applied
- Blockers: migration 20261118100000_coach_feedback not applied; founder applies after review
- Last Validation: full suite 1043 passed, 0 failed; SQL suite with revision checks runs in CI
- Last Updated: 2026-11-18

## 2026-11-18 Story 2.4 review fix (#206)
- Current Phase: Coach Mode Phase 2, athlete detail (2.4) in review
- Active Story: 2.4 fix, no-plan athletes keep their recorded runs visible as extra runs
- Next Recommended Story: 3.1 coach feedback, after #206 merges
- Blockers: none; founder merges #206
- Last Validation: full suite 1043 passed, 0 failed; SQL suite with revision checks runs in CI
- Last Updated: 2026-11-18

## 2026-11-14 — Story 0.2: runs link to their workout (PR open, not merged)

**Status:** In review on `feat/run-workout-link`. **Active Story:** coach-mode 0.2. **Next:** Nadav applies `supabase/migrations/20261114130000_runs_workout_link.sql` after review (and copies it to the web repo `Running-coach-/v0/supabase/migrations/`), then merge.
Live schema check (production `dxqglotcyirxzyqaxqln`, read-only): `runs.workout_id` did not exist, so the migration adds it (uuid, nullable, FK to `workouts.id` ON DELETE SET NULL, guarded and idempotent) and a partial unique index `runs_workout_id_unique`. After a match, `completeBestMatchingWorkout` sets `runs.workout_id` by `(auth_user_id, source_provider, source_activity_id)` only while the run has none; a queued or not-yet-synced link retries from `RunWorkoutLinkOutbox`. Health, Garmin and in-app runs share that path. A per-account, once-per-install 30-day backfill logs matched/unmatched first (debug dry-run: `-runsmart.debug.runWorkoutBackfillDryRun YES`). Match thresholds unchanged.
**Review fixes (2026-11-15):** migration now has a `runs_enforce_workout_owner` trigger (a run may only link a workout its owner owns), tested in a throwaway Postgres (`supabase/tests/runs_workout_link*.sql`); the link retry queue has a one-pass gate; the backfill skips hidden runs.
**Last Validation:** full suite, iPhone 17 Pro simulator: 888 passed / 0 failed / 1 skipped (21 new tests in `RunWorkoutLinkTests`); SQL test PASS. The link write itself is not covered by a unit test (needs the migrated database).
**Last Updated:** 2026-11-14

## 2026-11-07 — Build 41 Watch round trip passed; PR165 review findings fixed

**Status:** In review. **Current Phase:** Watch release candidate. **Active Story:** PR #165 review fixes and merge of `main` (public 1.2.4). **Last Completed Story:** physical Watch round trip on 1.2.3 (41). **Next Recommended Story:** un-draft PR #165 after a green suite, then cut the 1.2.5 candidate with the Watch app. **Blockers:** none known.

**Physical Watch QA on build 41: PASS, by owner report.** The founder reported on 2026-11-07 that the external tester confirmed both checks: the planned workout appears on the Apple Watch, and the completed run saves back to the iPhone. App Store Connect, read live the same day, shows the tester's iPhone account on 1.2.3 (41) with 14 sessions, no crashes and no TestFlight feedback entries. This closes the "final candidate Watch round trip remains pending" item from 2026-11-02.

**Review findings fixed (8 open threads at head `7d2f9fd`).** Recovery ownership is now bound at the first failed Health import and never adopted by the account that later resolves the lookup; `HealthKitDeferredCompletion.process` rejects ownerless recoveries (Codex P2, CodeRabbit Major). Ownerless records from older builds stay inert rather than guessing an owner. An empty plan workout list keeps deferred completion pending. An unchanged Health route keeps its stored point IDs, so it no longer re-uploads and clears the route match on every sync. The daily wellness snapshot is saved before a failed workout read returns. The exact-ID completion path reloads the run and skips a hidden or removed one. Health-driven plan completion refreshes Apple Watch exports before the plan notification. The tester's email and name were replaced with "the external tester" in five public files; earlier commits still hold them in history.

**Last Validation:** 2026-11-07, merged result (`2c232a0`, branch plus `origin/main`): full suite on iPhone 17 Pro simulator, **863 tests: 862 passed / 0 failed / 1 skipped** (the existing opt-in map-render skip), `TEST SUCCEEDED`. All 5 new and 3 updated recovery/merge tests pass. A second-model review then found that `refreshAppleWorkoutExports` did not recheck the account after its plan fetch, now reached on every Health sync; fixed with a recheck, full suite rerun: same 862 / 0 / 1, `TEST SUCCEEDED`. Version stays 1.2.3 (41) on this branch; `origin/main` still carries 1.2.2 (40) although 1.2.4 (42) is live, so the next candidate must be 1.2.5 (43) or higher.
**Last Updated: 2026-11-07**

## 2026-11-02 — Watch beta accepted by tester; integrated candidate 1.2.3 (41)

Owner reports the external tester completed beta38 tests and all looked good; accepted as tester-reported paired-device evidence. Correct tester the external tester installed on iPhone15ProMax/iOS27.0.1. Reconciled PR165 with main3c2d679 without rewriting history; retained both records and current iPhone features. Reproduced failed→successful unassociated Health lookup losing completion. Deferred recovery persists owner/target, survives transient failure/relaunch, yields to exact Health identity and cannot rematch replacements or replay reports. Independent QA's account-switch/new-exact-ID races fixed with regressions. Final simulator suite: **841 passed /0failed /1existing opt-in map-render skip**,33Watch tests pass. Version1.2.3(41) allocated after live ASC latest40 complete. Source4f20bc0 pushed to PR165; main now mergeable. Signed archive/signatures/versions/HealthKit/privacy/dSYMs and actual-artifact backend HTTP200 pass. Owner approved signing; exported IPA distribution signatures/debugging disabled/dSYMs and actual IPA backend HTTP200 pass. Upload/processing succeeded; build UUIDc554c551-d5d0-4b50-8ffd-6da19b4ea9da attached to Apple Watch Beta. What to Test saved; automatic notification enabled; beta review submitted and live group table verifies Waiting for Review. No public submission/release; final candidate Watch round trip remains pending. See docs/qa/releases/1.2.3-watch-candidate/ and docs/plans/2026-11-02-watch-release-candidate.md. Clean temporary clone protects original worktrees: /private/tmp/runsmart-watch-release-20261102.

## 2026-11-05 — T7 coach tones merged (PR #176); PR #174 merged

**Status:** PR #174 (1.2.2 release source) merged into `main` on founder's yes, so `main` now matches the live 1.2.2 build. T7 merged into `main` through PR #176 on founder's yes. Founder chose to skip the pre-merge device listening test and check the tones in production. No version bump, no archive, no upload.
**Current Phase:** One tone list (Motivating, Calm, Technical), a saved choice, and that choice on offline cue wording, speech rate and pitch. The AI cue request sends `coachingStyle`.
**Active Story:** none. T7 is in `main`, waiting for the next release build.
**Last Completed Story:** T7 code plus a review fix: sign-out and demo mode now reset the spoken tone, so a previous account's tone is not kept on the phone. `.gitignore` line for `.track-status.md` left uncommitted (tooling, not T7).
**Next Recommended Story:** Optional: a Play button on the Coaching Tone preview so the runner can hear each tone without running. Founder listening test on a physical iPhone after the next archive (build number above 40). Separately approve or reject `docs/qa/2026-10-31-voice-web-change.md` before the web route is edited.
**Blockers:** No device listening evidence. `VOICE_COACH_ENABLED` in production unverified. Web route change not applied, so the server ignores `coachingStyle`. Codex review out of credits.
**Last Validation:** 2026-11-05, full `xcodebuild test` on T7 merged with `main` (incl. #174), iPhone 17 Pro simulator, iOS 26.5: TEST SUCCEEDED, 825 passed, 0 failed, 1 skipped (`RunSharePosterRenderTests.testMapPostersRenderAtExportSize`, needs `TEST_RUNNER_RUN_SHARE_RENDER_DIR`). Not checked on a device.
**Last Updated:** 2026-11-05

## 2026-11-04 — 1.2.2 is live on the App Store

**Status:** 1.2.2 is public on the App Store since 2026-10-30 15:13 UTC (Apple lookup API, id 6768297840, polled 3 times with varying URLs on 2026-11-04, all agree). The public lookup does not show the build number. PR #174 records 1.2.2 (40) as the build selected in the ASC 1.2.2 draft, so the live build is most likely 40. Not checked in App Store Connect.
**Current Phase:** 1.2.2 live. Main does not hold the release source yet: it sits on `codex/release-1-2-2`, PR #174 (draft, 2 commits ahead of main).
**Active Story:** none. This entry only records the release.
**Last Completed Story:** 1.2.2 shipped (build most likely 40, see Status): satellite run sharing (PRs #171, #172), plan recovery and plan-failure analytics (PR #173), stats-only fallback when MapKit cannot load. Apple Watch PR #165 is not in this release.
**Next Recommended Story:** merge PR #174 so main matches the live build. Its progress entry also goes at the top of this file, so keep both entries when resolving. Then confirm in App Store Connect that the live build is 40.
**Blockers:** none.
**Last Validation:** 2026-11-04: Apple lookup API, 3 of 3 polls returned version 1.2.2, release date 2026-10-30T15:13:05Z. Docs only, no tests run.
**Last Updated:** 2026-11-04

Older entries: [tasks/archive/progress-to-2026-10-29.md](archive/progress-to-2026-10-29.md).

# 2026-11-17: Coach Mode story 2.2, coach reads linked athletes

Current Phase: Coach Mode. Branch `feat/coach-read-rpcs`.
Active Story: migration `20261117164500_coach_read_rpcs.sql` (`is_active_coach_of`, `athlete_display_name`, `coach_list_athletes`, `coach_get_athlete_plan`, `coach_get_athletes_workouts`, `coach_get_athletes_runs`) and `CoachReadService`. No UI. RLS on existing tables is unchanged. Not applied to production. The web repo needs the same migration file.
Next Recommended Story: 2.3, the athlete list, after this migration is applied.
Blockers: migration not applied. Run dates are the UTC date of `runs.completed_at`.
Last Validation: `CoachReadServiceTests` 7 passed on the iPhone 17 Pro simulator. SQL suite is `supabase/tests/coach_read.sql`; local Docker did not start, so that suite is left to CI.
Last Updated: 2026-11-17
