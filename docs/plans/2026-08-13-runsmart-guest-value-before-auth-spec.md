# RunSmart 1.1.6 Guest Value Before Auth

**Status:** Approved by founder on 2026-08-13; implementation complete in draft PR #136.
**Release:** RunSmart 1.1.6; Resumely 1.4.9 remains untouched while under App Store review.
**Decision:** This explicitly supersedes the earlier WP-61b sample-size hold and the original 1.1.6 exclusion of guest mode.

## Activation hypothesis

RunSmart currently asks a new runner to create an account before it can demonstrate the product's core value. Let a runner provide only the three inputs needed for a credible recommendation—goal, experience, and weekly rhythm—then show a locally generated Week 1 preview and the first recommended run. Ask for an account only when the runner chooses to save and unlock the full adaptive plan.

The preview must be genuinely derived from the selected inputs. It must not claim that a backend or AI-generated adaptive plan exists before one has been created.

## Story

As a new runner, I can preview a personalized first training week without creating an account, keep that preview on this iPhone across relaunches, and then sign in without re-entering my goal, experience, or schedule so I understand RunSmart's value before accepting the account gate.

## Acceptance criteria

1. The signed-out wall offers a primary “Build my free plan preview” action while Apple and email sign-in remain available.
2. Guest mode asks only for goal, runner experience, and weekly rhythm. It does not request HealthKit, location, notifications, Garmin, or backend access.
3. The Week 1 preview is deterministic and derived from all three input groups. It names each planned run and highlights a first recommended run.
4. Guest state and the preview survive app relaunch locally. No anonymous Supabase user or backend record is created.
5. The preview clearly states that it is local and that an account is required for the full adaptive plan, cross-device sync, connected health/device data, and durable progress.
6. “Save & unlock full plan” returns to existing Apple/email authentication. The runner can return to the guest preview if authentication is cancelled.
7. After a new account authenticates, signed-in onboarding begins at Coaching with the guest goal, experience, run count, and preferred days preserved. An existing completed account goes to the main app.
8. Guest state is cleared only after an authenticated account has completed onboarding, so a failed/cancelled upgrade cannot discard the preview.
9. The feature is controlled by `RUNSMART_GUEST_MODE_ENABLED`, defaults off if missing, ships on in 1.1.6, and can be disabled with the single plist value. A QA launch argument can enable it without changing release configuration.
10. Analytics separately cover guest start, profile completion, preview viewed, account prompt, and authenticated upgrade. A guest relaunch is attributed as `guest_value` rather than `sign_in_wall` for the first resolved frame.
11. Existing auth, onboarding, permission, account deletion, analytics, and signed-in app behavior do not regress.

## Explicit boundaries

- Guest mode is a local preview journey, not an anonymous cloud account.
- Guests cannot sync, connect Apple Health or Garmin, record durable account progress, or use cross-device features.
- The preview is not the full generated adaptive plan and the UI must say so.
- No payments, social features, Garmin commercial work, broad onboarding redesign, or Resumely mutation is included.

## Verification

- Red/green focused tests for the flag, local persistence, deterministic personalization, upgrade profile, and first-frame route.
- Full XCTest suite with the known locale baseline fixed or explicitly isolated.
- Clean signed-out simulator: guest start → preview → relaunch → preview → auth prompt → return to preview.
- New-account simulator/device: authenticate → Coaching (not Goal) → finish onboarding → generated plan.
- Existing-account smoke: authenticate → main app with no guest-state resurrection.
- Release build and archive inspection before any App Store upload.
