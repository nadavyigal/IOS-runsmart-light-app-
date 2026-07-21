# RunSmart 1.1.1 (25) — first-time Sign in with Apple S0 verification

**Date:** 2026-07-21
**Status:** **S0 PASS; bounded telemetry-integrity repair implemented and locally verified**
**Target binary:** Public App Store **1.1.1 (25)** (`com.runsmart.lite`)
**PostHog:** Running coach (`171597`, UTC)

## Verdict

**S0: PASS.** The founder confirms, without exposing the identifier, that the Apple ID used for this attempt had never authorized RunSmart. RunSmart was removed, public 1.1.1 was installed from the App Store, and Sign in with Apple was attempted exactly once. It succeeded, and the same physical session completed onboarding, HealthKit handling, plan generation, and first-run visibility.

This founder verification session validates production mechanics but remains excluded from clean customer activation cohorts. No screenshot was supplied, so the exact visible-outcome image remains an evidence gap; the founder's reported successful journey is corroborated by the matching production event sequence.

## Public App Store journey observed

All timestamps are UTC. PostHog reports `$is_emulator = false`, `$is_testflight = false`, and `$is_sideloaded = false`.

| Event | UTC | Evidence |
|---|---|---|
| `Application Opened` | `07:27:24.158` | 1.1.1 (25), iPhone 13 / iOS 26.5.2 |
| `sign_in_wall_viewed` | `07:27:24.219` | `screen = sign_in_wall` |
| `sign_in_wall_tapped` | `07:27:27.227` | Exactly one tap |
| `sign_in_completed` | `07:27:35.933` | `method = apple`; no `sign_in_failed` |
| `healthkit_sync_completed` | `07:28:45.988` | HealthKit handling completed |
| `onboarding_completed` | `07:28:50.614` | One completion; all five named steps present |
| `plan_generation_started` | `07:28:59.569` | One start |
| `plan_generated` | `07:29:07.853` | Plan persisted |
| `plan_generation_succeeded` | `07:29:07.863` | One success, `duration_ms = 8294`; zero failures |
| `first_run_cta_viewed` | `07:29:09.226` | First-run bridge visible |
| `first_workout_viewed` | `07:29:10.499` | First workout visible |

### Attribution, privacy, and shipped-build defects

- SDK `$app_version = 1.1.1` and `$app_build = 25` are present throughout the matching session.
- `sign_in_completed` has only the expected app fields `method = apple` and `screen = sign_in_wall`; no email, name, Apple ID, credential, token, or other app-supplied sensitive data was observed.
- The intended unprefixed `app_version` / `app_build` super properties were absent after the anonymous-user reset.
- Plan terminal deduplication passed: one start, one success, zero failed terminals.
- `onboarding_completed` appeared once, but `onboarding_started` appeared twice in the same session/person (`07:27:34.982`, `07:28:58.681`).
- Notification permission emitted two requests, then denied and granted 39 ms apart. Concurrent callers could both observe `.notDetermined` before either request resolved.

## Public binary and controlled-attempt record

| Field | Result |
|---|---|
| Apple public listing | Version 1.1.1, released `2026-07-20T20:38:19Z` |
| Installed build | 1.1.1 (25) |
| Apple ID eligibility | Owner-confirmed never authorized RunSmart; identifier not recorded |
| Device / iOS | iPhone 13 / 26.5.2 |
| Attempt UTC | `2026-07-21T07:27:27.227Z`; completed `07:27:35.933Z` |
| Sign-in attempts | Exactly one |
| Visible outcome | Successful sign-in followed by completed onboarding and plan creation |
| Screenshot/evidence location | Not supplied |
| S6 empty-goal behavior | Not exercised |
| S1 generation failure/retry | Not safely reproduced; successful terminal only |

Public listing: <https://apps.apple.com/us/app/runsmart-ai-run-coaching/id6768297840>

## Bounded telemetry-integrity repair

One local story covers the three production defects without renaming events or changing production configuration:

1. `Analytics.resetUser()` now restores only `app_version` / `app_build` after the SDK clears anonymous identity and super-property state.
2. An analytics identity reset no longer clears the onboarding-start guard. A distinct sign-in-wall tap is the explicit boundary that permits a new onboarding lifecycle.
3. `PushService` keeps one in-flight authorization task, so concurrent callers share one system result and one request/terminal analytics pair.

Four regression tests reproduce the clean-install reset, onboarding remount/lifecycle, and concurrent notification-call shapes. The focused telemetry suite passed **4/4**. The complete iOS suite passed **320/320**, with zero failures and zero skips, on iPhone SE (3rd generation) / iOS 26.5 Simulator. Counts were read from the saved xcresult bundle. The complete XCTest bundle also passed `build-for-testing`.

## Next action and gates

1. Review and merge the isolated repair, then ship it through the normal release process.
2. Verify an excluded physical App Store path contains unprefixed build attribution, one onboarding start, and one notification terminal.
3. Once production telemetry integrity is verified, resume the existing activation plan at **S2: let users see product value before the account wall**.
4. Keep S6 empty-goal and S1 failure/retry physical evidence open because neither was exercised in this successful session.
5. Do not start Experiment E1 until at least **10 clean, founder/QA-excluded physical installs are D7-mature**. Founder verification traffic does not count.

No production configuration, App Store metadata, authentication architecture, analytics names, backend services, dependencies, deployment, upload, or Apple submission changed.
