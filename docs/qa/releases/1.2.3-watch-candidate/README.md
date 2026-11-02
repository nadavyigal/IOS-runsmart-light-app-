# RunSmart 1.2.3 (41) — Apple Watch candidate

Owner approved candidate preparation on 2 November 2026 after reporting Yaniv finished the beta tests and all looked good. This is tester-reported acceptance of 1.2.1 (38); individual device subcases were not independently observed. Correct TestFlight recipient: yanivshm@gmail.com. ASC confirms iPhone 15 Pro Max / iOS 27.0.1 installation. Earlier iPad installation belongs to the old email and is not the Watch acceptance evidence.

## Source and validation

PR165 is reconciled with origin/main 3c2d679 by merging, without rewriting published history. Sharing, saved-route benchmarks, plan recovery and analytics corrections are retained. Conflict resolution preserved both project histories; project version settings intentionally move to 1.2.3 (41). ASC inventory checked 2 November: latest upload 1.2.2 (40), complete; no newer upload shown.

Health recovery now queues the failed-to-successful unassociated lookup transition, persists the originating account and selected workout before completion, and retries the same target after backend failure/relaunch. It stops on a confirmed no-match, removed/completed target or successful completion. Missing plan data stays pending. Exact WorkoutKit identity overrides deferred heuristics. Hidden/deleted runs, account changes and concurrent state changes cannot advance stale recovery. No new database field, backend service, provider setting or dependency.

Regression red: the recovered unassociated import produced zero completion attempts. Focused suite before final race hardening: 31/31 passed. Final full suite: 841 passed, zero failures, one existing opt-in map-render test skipped (requires TEST_RUNNER_RUN_SHARE_RENDER_DIR and network). All 33 AppleWorkoutTests pass in the final suite. Xcode 26.5, iPhone 17 Pro simulator / iOS 26.5. Independent read-only QA found account/identity races; both corrected and re-reviewed with no remaining concrete finding. No iOS 26.3 runtime is installed.

Archive/export, actual-artifact live backend verification and final distribution state are pending. Source/artifact receipts will be added after verification. This is not yet a public release or a new paired-device pass.

## Short candidate validation

Install 1.2.3 (41) on the iPhone paired with the Watch. Use the existing RunSmart account; no separate RunSmart watchOS app is needed.

1. Send a future incomplete supported interval session. Verify one Watch workout with the expected warmup, repetitions, recovery/cooldown and configured alerts.
2. Start, finish and save on Watch without the phone. Reconnect, allow Apple Health sync, then use RunSmart Connections → Apple Health → Sync Now.
3. Confirm exactly one accurate run and exactly one intended planned-workout completion. Compare distance and moving time.
4. Repeat Sync Now and reopen RunSmart: no duplicate run or completion.

Report any failed step with phone/Watch models and OS, expected/actual behavior and build41. This short check must use the integrated candidate; prior build38 success does not validate the changed binary. Full permission/edit matrix is not claimed by automation.

Limits remain: manual/foreground Health sync, latest100 workouts/180days, no Health-deletion propagation, no custom live Watch coaching, Garmin/Strava disabled. Public App Store submission remains a separate release decision.
