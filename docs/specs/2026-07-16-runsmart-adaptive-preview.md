# RunSmart Adaptive Preview — Side-by-Side Experiment

Date: 2026-07-16
Status: Implemented; review-ready with Simulator XCTest runner caveat
Branch: `codex/runsmart-adaptive-preview`

## Outcome

Create a separately installable, clearly labelled **RunSmart Adaptive** app that can run beside the current `com.runsmart.lite` app. The preview must use local demo data only, expose the existing missed-workout Flex Week experience prominently, and leave the production app, production bundle identity, production data, and production roadmap untouched.

## Safety Boundary

- Production app bundle ID stays `com.runsmart.lite`.
- Adaptive preview uses `com.runsmart.lite.adaptive`.
- Adaptive preview is Debug-only and always uses `DemoRunSmartServices`.
- Adaptive preview does not authenticate, initialize PostHog, call Supabase, write HealthKit, connect Garmin, or mutate production data.
- The existing production Xcode scheme remains buildable and behaves as before.
- No destructive migration, feature removal, paywall, release upload, or App Store action is in scope.
- Existing untracked QA duplicates in the primary worktree are unrelated and must remain untouched.

## Story 1: Separate Adaptive Build Identity

**As a** founder
**I want** RunSmart Adaptive installed as a second app
**So that** I can compare it with the current RunSmart without replacing or risking production.

### Acceptance Criteria

- [x] AC1: A shared `RunSmart Adaptive` scheme builds the existing app target using an `Adaptive Debug` configuration.
- [x] AC2: The adaptive app bundle ID is `com.runsmart.lite.adaptive`; the current app remains `com.runsmart.lite`.
- [x] AC3: The home-screen display name is `RunSmart Adaptive`; the current app remains `RunSmart`.
- [x] AC4: The embedded Live Activity extension has a compatible adaptive bundle ID.
- [x] AC5: The adaptive flavor is recognizable at runtime through a testable build-flavor policy.
- [x] AC6: Adaptive flavor forces demo/local services and never initializes production analytics or authentication.
- [x] AC7: The adaptive configuration is Debug-only; no adaptive Release/App Store configuration is created.

### Test Plan

- Unit test: build-flavor parsing identifies production vs adaptive from injected Info values.
- Unit test: adaptive flavor requires local demo isolation.
- Integration test: inspect built app and embedded extension bundle identifiers/display name.
- Manual check: current and adaptive app icons coexist on one Simulator.

### Out of Scope

- Physical-device provisioning for the new bundle ID.
- TestFlight/App Store distribution.
- A second source-code target or code fork.

### Dependencies

- Existing app target and Debug configuration.

## Story 2: Adaptive Missed-Run Preview

**As a** runner evaluating the proposed strategy
**I want** to immediately see how RunSmart responds to a missed run
**So that** I can understand and test the differentiation without altering real data.

### Acceptance Criteria

- [x] AC1: Adaptive flavor opens directly into the existing app shell using local demo data.
- [x] AC2: Today shows a clearly labelled `ADAPTIVE PREVIEW` explanation card that does not appear in production flavor.
- [x] AC3: The adaptive fixture always contains one recent missed scheduled workout and a safe upcoming week.
- [x] AC4: The card names the missed workout and offers `Review adaptive week`.
- [x] AC5: The CTA opens the existing Flex Week flow with `.missedWorkout` preselected.
- [x] AC6: The user can review exact changes and rationale, choose `Keep Original Plan`, or confirm the local proposal.
- [x] AC7: Confirming in adaptive preview changes no production or HealthKit data.
- [x] AC8: The adaptive UI explicitly says it is a safe local preview.

### Test Plan

- Unit test: adaptive fixture always exposes a most-recent missed workout relative to an injected date.
- Unit test: preview policy is hidden for production and shown for adaptive flavor.
- Unit test: preview policy produces the preselected `.missedWorkout` reason.
- Integration test: focused existing Flex Week tests continue passing.
- Manual check: launch adaptive app, open the card, review diff, exercise both keep-original and confirm paths.

### Out of Scope

- New rescheduling algorithms.
- Automatic production prompts.
- RPE/recovery-triggered adaptation.
- WorkoutKit, App Intents, widgets, or native watch UI.

### Dependencies

- Story 1.
- Existing `FlexWeekFlowView`, `DeterministicFlexWeekBuilder`, and demo services.

## Story 3: Side-by-Side QA and Handoff

**As a** founder
**I want** verified access to both versions
**So that** I can play with the experiment and decide whether it deserves further work.

### Acceptance Criteria

- [x] AC1: Current `IOS RunSmart app` Debug scheme builds after all changes.
- [x] AC2: `RunSmart Adaptive` builds and launches on Simulator.
- [x] AC3: Both bundle IDs are installed simultaneously.
- [x] AC4: Production launch does not show adaptive-preview UI.
- [x] AC5: Adaptive launch shows the preview card and completes the missed-run review flow.
- [x] AC6: Screenshots document production and adaptive Today surfaces plus the adaptive diff.
- [x] AC7: A short QA report explains how to launch and reset the local preview.
- [x] AC8: Task memory records the safety boundary, validation, branch, and remaining gates.

### Test Plan

- Unit test: focused build-flavor, adaptive-preview, and Flex Week suites.
- Integration test: build both schemes and inspect app metadata.
- Manual check: launch both apps sequentially on the same booted Simulator and capture screenshots.

### Out of Scope

- Production rollout.
- Merge to `main` without founder review.
- Analytics interpretation or activation conclusions from demo behavior.

### Dependencies

- Stories 1 and 2.

## Definition of Done

- All three stories pass their acceptance criteria.
- Production bundle/configuration remains intact.
- Adaptive preview is local-only, clearly labelled, and independently installable.
- Focused tests plus both-scheme builds pass.
- Side-by-side simulator evidence exists.
- Changes are committed, pushed, and opened as a reviewable PR; nothing is merged or released automatically.

## Verification Note

Both Debug schemes compile, the normal optimized Release build passes, both app identities coexist, and the full adaptive review path passed manual Simulator QA. The Release binary retains the production bundle identity and contains none of the adaptive card's user-facing strings. The focused XCTest bundle compiles with `build-for-testing`; the local Xcode 26.3/26.5 test runner repeatedly stalled at `waiting for workers to materialize`, so runtime XCTest completion remains an explicit PR caveat rather than a claimed pass.
