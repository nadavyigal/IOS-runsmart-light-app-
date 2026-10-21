# RunSmart API + route candidate — October 21, 2026

Status: integrated development candidate; physical-device gates OPEN. No upload or submission while the Resumely release sprint remains active.

## Source and review

- Worktree: `/Users/nadavyigal/Developer/runsmart-worktrees/pr158-api-www` (reused clean detached checkout; original checked-out API branch left untouched).
- Candidate branch: `codex/ios-api-route-candidate-2026-10-21`.
- Integrated code commit: `9c5005f45111b5c3744d67f025976c12d99b4e13`.
- API source: [#158](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/158), head `26a4104aae3e1e37ef17c323d931cafb9081fbf2`, still OPEN. Plist and fallback point directly at `https://www.runsmart-ai.com`.
- Route source: [#161](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/161), merged as `d57f314b814289ec42ef76d87a879116106cc578`, including fixes through `d38c512`.
- Fresh GitHub read: #158 MERGEABLE, GitGuardian SUCCESS; CodeRabbit status is SUCCESS but its description says “Review skipped: manual review required for this OSS repository”, so that status alone is not a clean review receipt. Fresh [Codex receipt](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/158#issuecomment-6312211104) and summary confirm review completed with no findings at `26a4104`; no duplicate review requested for that unchanged head. One earlier CodeRabbit nit: existing configured-URL tests do not independently execute the absent-plist fallback; carried as a nonblocking coverage follow-up.
- #161: all five inline review threads resolved. Rulesets API returns `[]`; branch protection read via gh returns 404, “Branch not protected”. Connector protection read alone was permission-denied; no additional required Xcode CI checks were discovered. Local integration tests remain necessary.
- This draft candidate carries #158 without merging or waiving its device gate. Prefer accepting #158 after signed-in device evidence; then rebase/refresh this handoff PR, whose remaining diff should be documentation. Do not merge two divergent implementations.

## Candidate identity and installation

The source retains **1.1.9 (34)**, bundle `com.runsmart.lite`; this is a development QA candidate, not an allocated next App Store build. Identify it by source commit and build from this worktree. The public 1.1.9 (34) does not prove that this code is installed. A distribution build needs a fresh version/build allocation and the normal signing/privacy/release review later.

On the founder's Mac, open `IOS RunSmart app.xcodeproj` from this worktree, choose scheme `IOS RunSmart app`, connect/unlock the existing iPhone, choose that physical device and Run using configured development signing. **Install over the existing app; do not delete it**: raw run GPS is on-device/Health, not uploaded in `runs.route`. Record installed source commit, phone/iOS, date, install success and launch result. If signing/account access blocks installation, record that gate rather than claiming a device pass. Unsigned Release compilation is not an installable archive.

## Gate A — signed-in API smoke (#158)

1. Open the candidate, sign in to the founder's existing account and confirm the authenticated profile. Use existing data; do not create or expose credentials/tokens in evidence.
2. Open Plan and tap “Try again” if the plan error/retry card is present. Otherwise open Profile → Goal & Plan, retain the intended goal/settings, and choose “Save Goal & Generate Plan” (the wizard may show “Continue & Generate Plan”/“Save” depending on its entry state); note current plan first because successful generation may replace it. Expect a populated plan, no repeated “no plan”/401, and persistence after closing/reopening the app. Record visible outcome, timestamp and any displayed error.
3. Open a saved run and generate/open its report (`api/run-report`); expect actual report content. A previously cached report alone does not prove a fresh signed-in request.
4. Exercise supported signed-in coach/chat and workouts retrieval once if available. Record success, failure or unavailable per surface. Voice-cue is flag-gated: record unavailable if disabled; do not enable it for this smoke.
5. If request diagnostics are available, record host `www.runsmart-ai.com`, status and absence of a cross-host redirect, with authorization headers and personal content redacted. A simulator URL assertion or unsigned HTTP probe does not replace this signed-in phone result.

**Pass:** signed-in plan generation succeeds and persists, with the other supported API outcomes recorded. Any 401/no-plan failure leaves #158's gate open. API failure and route comparison failure are separate findings.

## Gate B — stored October loops (#161)

1. Keep the existing install and Health access. Confirm the Oct 18 run (1385, 5.03 km) and Oct 21 run (1386, 5.52 km) exist in history with usable route points. If needed use existing Apple Health import/sync; its current window is 180 days/newest 100 workouts and stored rematch covers newest 300 runs. Record missing data as a blocker; **no new outdoor recording is required to compensate for the old matcher**.
2. In Routes, turn OFF benchmarking for both saved loops, then choose **Make Benchmark on ONE loop only**, preferably Oct 18. Wait for rematching to finish; keep the other loop saved but not benchmarked.
3. Open the Oct 21 run and the selected benchmark history. Expect both stored efforts to attach to that one benchmark: the longer detour effort is a route variant. Confirm pace comparison (`/km`) and “Best Pace” for the variant, distance delta about +0.49 km against Oct 18. Time PB/average must come from full-route runs only. Do not treat the longer elapsed time over a longer distance as a slower route PB.
4. Open Share on the variant comparison. Expect current/best **pace**, no misleading total-time Route PB, no exact map/raw coordinates. Cancel share and confirm a clean return. Do not send it externally for this test.
5. Remove the selected benchmark. Confirm comparison is no longer presented as an enabled benchmark. Enable ONLY the Oct 21 loop and wait for rematching. Both stored runs should now attach there; Oct 18 is the shorter variant (about -0.49 km). Recheck pace and share text.
6. Relaunch and verify the selected single benchmark and both history attachments persist. Restore the preferred one-benchmark configuration. Record screenshots/text, dates, run IDs, selected benchmark, counts and pass/fail. If both loops are benchmarks each effort can stay on its own route, which is not this acceptance setup.

**Pass:** both existing loops attach with either single benchmark, variant comparison/share uses pace, disable/re-enable rematches, and configuration/history persist. Do not claim real-trace results from synthetic fixtures.

## Verification and release decision

- Simulator built Info.plist verified: `com.runsmart.lite`, 1.1.9 (34), `https://www.runsmart-ai.com`.
- Full integrated simulator suite: **448 passed, 0 failed, 0 skipped**, iPhone 17, iOS 26.5 (x86_64), source `9c5005f`. Result bundle `/tmp/runsmart-api-route-candidate-tests.xcresult`; log `/tmp/runsmart-api-route-candidate-tests.log`. Includes APIBaseURLTests and route variant/rematch/share regressions.
- Standalone iPhone 17 simulator install/launch passed; inspected restored guest Week 1 preview, no visible overlap/crash on that entry surface. Screenshot: `evidence/2026-10-21-api-route/simulator-launch.png`. This is not a signed-in API or route-device smoke.
- Unsigned **Release generic iOS arm64 build PASSED** (`CODE_SIGNING_ALLOWED=NO`). App and extension both 1.1.9 (34); app bundle/API verified as above; analytics and Supabase configuration resolved/nonempty without exposing values. Evidence: `evidence/2026-10-21-api-route/release-configuration.json`; build log `/tmp/runsmart-api-route-release.log`; unsigned app `/tmp/runsmart-api-route-release-dd/Build/Products/Release-iphoneos/IOS RunSmart app.app`. Not a signing/archive/install/distribution proof.
- `git diff --check` passed. No new runtime code beyond the already accepted #158/#161 source. Local integration/static review found no new blocker.
- Workflow router references `.agent-os/workflows/{story-implementation,ios-qa-review,testflight-review}.md`; these files are absent in the actual canonical checkout. Used repository AGENTS.md, available QA/TestFlight checklists and release-prep skill; historical checklist ticks are not treated as current-candidate evidence. iOS 26.3 is not installed; physical-device signed-in, GPS/background, account/signing and App Store outcomes are not supplied by simulator tests. Current work changes no GPS upload/privacy scope, production service setting or RunSmart web #140. No partner outreach.

After both phone gates pass: record evidence, accept #158 according to the existing merge decision, refresh candidate main/head and perform normal release identity/signing/privacy checks. Resume RunSmart distribution only after the Resumely release sprint closes and distribution is authorized.
