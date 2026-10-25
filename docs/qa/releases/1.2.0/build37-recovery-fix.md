# 1.2.0 (37): preserve immediate planned-run recovery

As a runner starting a planned workout with GPS, I want its interval guide in the first recovery checkpoint so an immediate termination does not lose the planned steps.

Acceptance: the first GPS checkpoint contains the complete guide; relaunch and resume restores that guide and workout title; the start cue precedes step announcements; free runs and Start anyway retain existing behavior. No Strava, backend, or pricing changes.

Regression: RunRecoveryTests.testImmediateGPSStartRecoveryKeepsPlannedWorkoutGuide failed on build-36 code with a nil WorkoutGuide in the first checkpoint. The fix initializes the guide before accepting the first GPS location, preserving start-cue ordering. Build incremented to 37 across all six configurations.

Owner reported 1.2.0 (36) TestFlight testing passed on 25 October. Full simulator suite: 725 passed, 0 failed, 0 skipped (including the new recovery regression). Build 37 archive/export and processing results pending. Physical planned-run recovery retest remains pending; App Store 1.2.0 draft created with current release notes and reviewer instructions. No App Review submission yet.
