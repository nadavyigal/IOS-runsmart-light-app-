# Sprint 7: Real Run Completion State Fix

## Product Brief

### Idea
Make a completed real RunSmart GPS run become one canonical saved activity that exits cleanly from the Run tab and updates Report, Profile, Today, and Plan.

### Runner Problem
After a valid outdoor GPS run, the app can show saved-run copy while leaving Run stuck in post-run state, later showing "Run not saved" and leaving Today/Plan as if the run never happened.

### Target User
Physical-device beta runners recording real GPS runs before TestFlight expansion.

### Daily Use Moment
Finish a run, tap Keep Activity / Done, then check Report, Profile, Today, and Plan for the result.

### Desired Outcome
The run is saved once, report data is available consistently, matching planned workouts are completed, and failed suggested-workout saving never implies the run/report failed.

### Non-Goals
No live AI backend, route marketplace, notification feature work, share-card changes, or marketing-copy changes beyond the unsafe error-message fix.

### Success Signals
Run exits to idle after Keep Activity, no stale "Run not saved" sheet appears, Report/Profile agree, Today/Plan refresh, and the app builds.

## Feature Spec

### Summary
Unify the completed-run lifecycle around the inline Run tab post-run summary, make completed GPS runs canonical before report generation and plan matching, refresh all dependent surfaces, and harden suggested-next-run failure behavior.

### Goals
- Clear Run tab completion state after Keep Activity / Done or Delete.
- Save a completed RunSmart GPS run to the canonical local run/report path.
- Mark a matching same-day planned workout complete when within existing tolerance.
- Refresh Today, Plan, Report, and Profile after save/process completion.
- Keep user-facing error copy safe when suggested-workout saving fails.

### UX Requirements
- A valid saved run must not later show "Run not saved / could not find completed run metrics."
- If no planned workout matches, show existing extra-run language and keep the run/report saved.
- Suggested-workout failure copy must say the run report is saved and the workout can be retried later, without debug instructions.

### Data and State
- `RecordedRun` remains the canonical activity model.
- `RunReportDetail.runID` uses `SupabaseRunSmartServices.reportRunID(for:)`.
- Add a report-refresh notification so report-backed surfaces reload when reports are cached or generated.

### Acceptance Criteria
- Real GPS run records, finishes, saves, and exits cleanly.
- Run tab returns to pre-run/idle state after Keep Activity / Done.
- No stale "Run not saved" sheet appears after a valid saved run.
- RunSmart GPS run appears in Report tab.
- Profile and Report agree on the saved run/report.
- Today no longer recommends the same workout after it was completed.
- Plan marks the matching workout complete or reflects the run as extra completed activity.
- Suggested next run save works or fails with safe user copy.
- App builds successfully.

### QA Plan
- Unit-test matching, canonical report id stability, Today recommendation behavior, date parsing, and safe error copy.
- Run generic simulator build-for-testing and build sequentially.
- Manual physical-device QA remains required for real GPS recording, Report/Profile/Today/Plan refresh, Garmin duplicate handling, and suggested-next-run save.
