# WP-25: Garmin Track

*Track:* Garmin Production Gate + Garmin-powered product depth
*Started:* 2026-07-02
*Branch:* `codex/wp25-garmin-track`
*Status:* Initiated

## Product Brief

### Idea
Create a durable Garmin track so each Garmin work package has one shared source of truth for brand compliance, production gate evidence, live-device validation, and future Garmin-powered product improvements.

### Runner Problem
Garmin-connected runners need RunSmart to feel trustworthy: connection surfaces must be brand-compliant, imported data must be attributed clearly, and Garmin-derived insights must be accurate enough to guide daily training decisions.

### Current Reality
- v1.0.6 (19) is live on the App Store as of 2026-07-01.
- Garmin Gate-4 evidence was rejected a third time because "Garmin Wellness" naming and rendered Garmin Connect logo treatment were non-compliant.
- PR #69 removed the invented "Garmin Wellness" naming and stopped clipping the official Garmin Connect tile.
- PR #70 bumped the app to `1.0.7 (20)` for the next Gate-4 resubmission build.
- WP-24 is paused and must not be mixed into this track unless explicitly resumed.

## Track Rules

1. Keep Garmin brand compliance and Garmin product-depth work in separate small work packages.
2. Do not invent Garmin feature names, marks, logos, or compound labels.
3. Use the official Garmin Connect asset exactly as provided; do not crop, mask, clip, recolor, or reshape it.
4. Prefer live-device screenshot verification for Garmin evidence before sending replies.
5. Keep founder-only App Store Connect, upload, and Garmin-ticket actions explicit and separate from code-complete status.
6. Do not bump version/build inside a work package unless the task is explicitly release preparation.

## WP-25 Scope

WP-25 is the Garmin track initiation and Gate-4 restart package.

### Goals
- Establish this track artifact as the anchor for future Garmin WPs.
- Confirm current repo state after PR #69 and PR #70.
- Define the next evidence-first execution path for Garmin Gate 4.
- Preserve WP-24 as paused.

### Non-Goals
- No new Garmin product UI.
- No wearable-depth implementation from E7.
- No version/build changes.
- No App Store Connect upload from this session.
- No Garmin ticket reply without fresh verified evidence.

## WP-25 Execution Plan

1. Confirm canonical app repo status on `main`.
2. Branch from `main` into `codex/wp25-garmin-track`.
3. Add this Garmin track artifact.
4. Update canonical task state.
5. Run lightweight static verification for planning-only changes.
6. Commit the planning artifact.

## Next Garmin Work Packages

### WP-26 Candidate: Gate-4 Evidence Recapture
- Build/install `1.0.7 (20)` on a real device.
- Capture all required Gate-4 screenshots from the live build.
- Verify every screenshot against the Garmin brand PDF.
- Confirm whether the official Garmin Connect tile asset is pristine.
- Prepare the Garmin reply package for ticket 213145/213165.

Status: implemented as a founder-run evidence runbook in `docs/qa/wp26-garmin-gate4-evidence-recapture.md`.

### WP-27 Candidate: Garmin Data Trust Audit
- Audit Garmin-derived data labels, fallback behavior, and source attribution across Today, Report, Recovery, and Profile.
- Confirm legacy Garmin rows without device names still render compliant attribution.
- Add focused tests only where behavior is product-critical.

Status: implemented in `docs/qa/wp27-garmin-data-trust-audit.md`; code tightened Recovery, Wellness Trends, and Morning Check-In attribution gating.

### WP-28 Candidate: Garmin Product Depth
- Resume the E7 wearable-depth spec when Gate-4 compliance is stable.
- Implement real 7-day Garmin HRV/readiness trends in small verified slices.

## Acceptance Criteria

- [x] WP-25 track artifact exists under `docs/specs/`.
- [x] WP-24 is explicitly treated as paused.
- [x] Current Garmin gate status is captured with PR #69/#70 context.
- [x] Future Garmin WPs are named as candidates without starting their implementation.
- [x] Planning-only changes are committed on `codex/wp25-garmin-track`.

## Verification

Planning-only change. Use static checks:
- `git diff --check`
- `git status --short --branch`
