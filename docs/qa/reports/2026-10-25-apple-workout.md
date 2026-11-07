# Apple Workout integration — QA and release gate

## Candidate
Branch `codex/apple-watch-workoutkit`, isolated checkout `/Users/nadavyigal/Developer/runsmart-apple-watch`, base `61b7cfb` (latest origin/main inspected October 25). Current 1.2.0 (37) submission is unaffected. No version, signing, production configuration, upload or submission change.

## Implemented contracts
- Supported complete running guides map to an outdoor WorkoutKit custom workout with the same warm-up, work/recovery order, cooldown, goals and explicit pace bands.
- Send checks runtime support, independent authorization, date, scheduler limit and schedule readback. Repeat send replaces the same UUID. FIFO gate keeps plan edits/removals from being lost during authorization.
- Successful full active-plan reads reconcile existing exports after edits, moves, removal, Flex Week and regeneration. Failed reads retain exports. A replacement that is not confirmed surfaces an issue; runner can resend. Delivery onto the Watch is not inferred from scheduler confirmation.
- Health reads distinguish query failure from no visible data; read-only permission is usable. Permission UI does not pretend to observe individual read choices.
- Stable Health UUID import refreshes late route/HR, keeps richer previous data and runner edits, respects hidden runs and locally retained RunSmart exports. All available route segments are read.
- Exact WorkoutKit plan ID survives mapping/storage/consolidation and is matched only to the active plan's incomplete item. A failed association lookup defers completion. Exact imported IDs retry on later explicit sync; no heuristic replay for existing runs.
- Completion reads fresh plan state and conditionally updates incomplete rows. Batch history reconciliation retains the existing newest-only report/debrief behavior.

## Automated verification
Final candidate: **736 XCTest + 3 Swift Testing tests passed (739 total), zero failures**, iPhone 17 / iOS 26.5, x86_64 simulator. Includes 14 new Apple Workout regressions covering real WorkoutKit wrappers, intervals/alerts, unsupported/incomplete/completed items, denial/capacity/confirmation, repeat send, edit/move/remove/regenerate, concurrent authorization/removal, exact completion, consolidation, late data, backward decoding and a non-Gregorian phone calendar. Independent static QA findings were corrected before the final run. `git diff --check` passes.

Command: `xcodebuild test -project 'IOS RunSmart app.xcodeproj' -scheme 'IOS RunSmart app' -destination 'platform=iOS Simulator,id=9E2E82B6-DC56-4162-846F-B96AE74867E7' -derivedDataPath /private/tmp/runsmart-watch-dd -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=YES`.

Simulator demo smoke: launch/navigation inspected; completed-session detail hides Send; upcoming-session detail exposes Send; Apple's actual scheduling prompt appeared; selecting Deny returned the actionable Settings message while Start This Workout remained available. Accessibility tree verified the status text. This does not prove Watch delivery. Small-iPhone/Dynamic Type/VoiceOver and physical read-only Health were not run.

Initial red build confirmed missing factory/merge contracts. Implementation compilation exposed explicit HealthKit import and actor-isolated default initializer requirements; corrected. Unsigned test hosts launched without executing tests; normal ad hoc simulator signing fixed this. The first real focused run passed 10/13 and exposed normalized DateComponents equality; corrected, then full suite 738/738 passed. Final calendar/duplicate-confirmation hardening added one test; final suite is 739/739. These lessons are recorded in tasks/lessons.md.

## Physical iPhone + paired Apple Watch gate — NOT RUN
1. Allow Workout scheduling; send a future interval workout. Verify goals, interval order, recovery and pace alerts in Watch Workout. Repeat send: one item.
2. Complete it phone-free, sync Watch to iPhone, then use Connections → Apple Health → Sync Now. Verify exactly one run, accurate distance/moving time, HR/route only when readable, and exactly one intended plan completion.
3. Repeat sync and reconnect/relaunch: no duplicate or second completion. Retry after an offline completion attempt.
4. Delay route transfer until after first import; sync again: route enriches same run. Deny route/HR read later: previously stored information is retained until user deletes it in RunSmart.
5. Read-only Health: import works with workout write denied. All reads denied/no data: honest empty state. Query failure: retry message, no successful sync claim. Scheduling denied/restricted/unsupported: useful error, phone run still available.
6. Export a phone run to Health; sync while local copy exists: no second run. Reinstall recovery remains the existing Health-import behavior.
7. Edit/reschedule an exported session: one updated item. Remove/regenerate/cancel: old export removed after a successful authoritative plan refresh; old completed run never matches a replacement UUID.
8. Mutate the plan while the scheduling permission sheet is open: queue resolves to latest plan, no stale item left behind. Exercise scheduler capacity and unconfirmed replacement/resend.
9. Small iPhone, large text and VoiceOver: Send/status copy remains usable.

## TestFlight readiness
**Not ready for release until the paired-device matrix passes.** No archive/export/upload was requested or performed. Existing Health permission strings cover this data flow; no watchOS target or new health data type was added. Read privacy wording and release notes again before a carrying release.

## Deliberate limits
Foreground/manual import (180-day lookback, 100 most recent workouts); no background delivery or Health-deletion propagation added. WorkoutKit handles Apple's session execution, not RunSmart live voice coaching. Exact plan identity is retained locally; no backend schema migration. A run associated with another app’s WorkoutKit plan imports normally but does not heuristically complete a RunSmart session; this also prevents stale plan IDs from matching replacements after reinstall. An unconfirmed replacement requires explicit resend; schedule readback does not prove Watch arrival. Failed active-plan fetches cannot establish cancellation and therefore do not remove exports. Physical device behavior remains unverified.
