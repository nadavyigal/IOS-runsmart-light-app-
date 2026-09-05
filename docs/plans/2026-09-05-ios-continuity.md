# September 5 bounded continuity batch

As a runner, I want the existing guest preview to describe available functionality and a paused run to resume without counting travel during the pause, so the first completed run is trustworthy.

Acceptance: preserve goal/experience/schedule through guest restoration and authenticated onboarding; remove the paused Garmin promise; exclude pause displacement from recorded distance; save one run on finish and retain completion-event deduplication. Reuse open WP-74 PR #149 without reimplementing attribution.

Test contract: synthetic location fixes before/during/after pause; persisted decoded run and repeated finish; existing guest, screen attribution, build identity, exclusions and completed-run tests. Run simulator suite. Read measurement contract twice, respecting empty cohorts and historical build keys.

Out of scope: new guest flow, integration relaunch, telemetry expansion, production configuration, dependencies, release or shared vault edits. Simulator logic is not physical GPS/background/public-binary proof. Authentication against a live account remains a founder walkthrough.

## Source inspection and measurement

- Base: PR #149, b098943, still open; main 32258e4. No release or merge performed.
- Guest preview restores local state, passes upgradeProfile to OnboardingView at coaching step 3, then saves TrainingGoalRequest.onboardingDefault. The activation sheet loads the first runnable generated workout and passes that workout to router.startRun. The preview is deterministic introductory guidance, not a persisted full-plan workout ID. No full-plan identity guarantee is asserted.
- Public version remains 1.1.7, released 2026-09-02T19:44:12Z; repo build 32. Two fresh contract runs are byte-identical. The separate all-events since-release query returned [events=0, persons=0, version=0, build=0, neither=0, installed=0, screen=0] twice. No events is not missing attribution.
- Historical public code uses app_build; PR #149 prospectively registers build_number and unregisters the persisted old key. September 3 is the code-change date, not a public shipping boundary. Queries coalesce build_number then app_build. Native $app_version/$app_build remain the safer install/update identity because SDK setup can emit before custom properties register.
- Contract excludes persons with internal-tester events within its window. With no post-release events, exclusions do not change current counts; this is not proof the filter identifies every historic founder or test identity. n=0 at each ordered launch-to-wall step; no rate or activation inference.
- Shared insight 10997860 still needs a separately reviewed build-key migration when a carrying build ships. Shared vault and analytics definitions were not edited.
