# Record-a-run setup — 23 October 2026

Founder decision: **defer Strava**. No subscription purchase, app registration, client ID, secrets, OAuth consent or edge-function deployment. The existing integration remains dormant; an empty `RUNSMART_STRAVA_CLIENT_ID` keeps its UI hidden. Strava setup, assets, upload and Strava-specific privacy publication are not release gates for this build.

## Final review fixes

- Clear local weight defaults and published state during account-data deletion, including invalidation of in-flight Health reads.
- Require RunSmart identity metadata before Health workout finalization; discard a builder if preparation fails.
- Keep exported route timestamps inside the workout interval and monotonic while preserving pause boundaries.

## Verification

Full simulator suite: **724 passed, 0 failed, 0 skipped**, iPhone 17 Pro / iOS 26.5. See `test-summary.json`. The 12 new regressions cover deletion during outstanding Health reads, required identity metadata sequencing, and route timestamp/segment normalization. Final diff review found no additional blocker in these changes. Existing Swift concurrency/deprecation warnings remain.

## Before merge/release

Review updated PR #164 and complete the physical iPhone checks: locked-phone cues and Spotify/Bluetooth, recording and paused recovery, traffic-light auto-pause, interval guide, Health route/pauses/estimated calories and optional privacy-trimmed map sharing. Health query failures remain fail-closed (no duplicate-prone write); eventual retry is not implemented. Title and notes remain local-only. No merge, upload, submission or release was authorized here.

## Privacy publication

The corrected policy is live and browser-verified at https://www.runsmart-ai.com/privacy (web source `63e82cd6`, production `dpl_CDGcoK8VvKf87WYr6VdXjCw7m38Y`, web PR147 open). It covers native storage, identified analytics, optional Health weight/writes, and opt-in map sharing. App Store Connect currently redirects to Apple sign-in; actual answers remain unverified until the owner signs in. Prepared mapping: `app-privacy.md`.
