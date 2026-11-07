# Apple Watch release candidate — 2 November 2026

Owner approved proceeding after reporting the external tester completed the beta tests and all looked good. Treat that as tester-reported acceptance of 1.2.1 (38), not an independently observed test matrix. Correct tester: the external tester; ASC confirms iPhone installation. No additional email or public App Store submission is requested by this continuation.

## Story 1: Reconcile the tested Watch feature with main

As a runner I want Watch scheduling alongside the current production features so the candidate preserves sharing, benchmarks, plan recovery and analytics corrections.

Acceptance: merge current main into PR165 without rewriting history; retain both tracks' project records; use a new candidate version/build verified against ASC. Confirm required benchmark implementation 5c96738 remains an ancestor. Tests: combined simulator suite and signed artifact verification. Out of scope: new Watch functionality, Garmin/Strava activation, backend/security/account changes.

## Story 2: Recover deferred Health plan completion safely

As a runner I want a Health run whose first association lookup failed to complete the intended plan item after a successful read, without duplicate completion or report generation.

Acceptance:
- A failed-to-successful lookup with no WorkoutKit association queues deferred completion.
- Pending recovery survives persistence and transient backend failure; ordinary unchanged unassociated runs do not replay completion.
- A selected workout ID is persisted before attempting completion. A retry cannot fall back to a different or replacement plan item.
- Missing/completed selected items and successful no-match evaluation stop recovery; unavailable plan data retains pending work.
- Hidden runs and unresolved Health lookups remain excluded. Existing exact WorkoutKit identity remains authoritative.
- Stale imports, upload confirmation and generic saves preserve the recovery state and user edits.

Tests: reproduce missing completion before the fix; focused transition, persistence, unavailable backend, retry, exact-ID, canceled/completed and no-report regressions; combined suite. Out of scope: automatic/background Health import, Health deletions or a new database schema.

## Story 3: Prepare the replacement beta

As the release owner I want a traceable signed candidate and short validation checklist so the external tester can validate the integrated binary before public shipment.

Acceptance: record source, simulator results, app/extension identity, distribution signatures, privacy and dSYM checks, and actual-artifact live backend verification. Preserve manual/foreground sync and no custom live Watch coaching limitations. The candidate's final paired-device check remains external work: Watch workout → Health import → intended completion → repeat sync/relaunch without duplicates. Public App Store submission remains a separate release decision.
