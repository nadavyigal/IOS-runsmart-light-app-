> Delivery update — 28 October: required benchmark/sharing source is now in uploaded, processed1.2.1(39), archive source98360ef. Exact build UUID73d723ad-3a78-4b93-bbb2-ed6e5a53f19a is Testing internally and selected in production draft. Await owner actual iPhone share/history check, then merge/submission evidence before closing this requirement. Watch38 excluded. Canonical current state: `../sharing-benchmarks/README.md`.

> Updated owner scope — 28 October 2026: next production candidate must also include PR167 native image/video exports and exclude Apple Watch PR165/beta build38. Combined integration: PR168, branch `codex/release-sharing-benchmarks`, `/Users/nadavyigal/Developer/runsmart-production-release`. PR158 API-host protection is also included. Candidate1.2.1(39) is being verified; live ASC allocation, physical candidate checks and exact processed-build selection remain open. See `../sharing-benchmarks/README.md`. Historical status below is retained as the original inclusion requirement.

# Next RunSmart ASC submission — required scope

Owner mandate: 27 October 2026. Include the route-benchmark fix from [PR #166](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/166) in the next App Store Connect submission.

Status: **release requirement recorded; not yet satisfied by an uploaded/submitted candidate**. PR #166 remains open at this check; its code review is running. Current remote main `61b7cfb` does not contain implementation `5c96738`. Build 37 was built before this fix and cannot be retrofitted. Do not claim the fix is in that existing submission.

## Blocking inclusion checks

- [ ] Complete review and merge PR #166 (including any required fixes) into the release source.
- [ ] Record the exact clean source commit used to archive, and pass `git merge-base --is-ancestor 5c96738 <archive-source-commit>`.
- [ ] Check live ASC version/build state; choose an unused build number greater than 37 and the appropriate editable app version. Do not change an existing review submission without owner authorization.
- [ ] Create a new archive/export from that recorded source. Verify app and extension version/build, distribution signatures, entitlements, privacy and matching dSYMs; pass the actual-artifact live backend gate.
- [ ] Verify on the candidate: reopen a stored run report → map and Save Route are available; before saving, no-match explanation is visible; Benchmark Route defaults on; save once and compare three existing matched runs using Previous, Route PB, Month Avg and Trend; relaunch and reopen with the comparison preserved. Check a different loop with nearby endpoints is not treated as the same full route; variants use pace appropriately.
- [ ] Verify the owner’s actual same-route history on the new TestFlight candidate. Synthetic simulator checks do not establish recovery of those particular records or physical GPS correctness.
- [ ] Record the newly uploaded/processed build and confirm that exact build is selected for the next ASC submission. Link the source and artifact evidence here before closing the requirement.

## Existing evidence

Implementation `5c96738` passed 745 simulator tests (742 XCTest + 3 Swift Testing), zero failures/skips, iPhone 17 / iOS 26.5. Visual QA verified save-once comparison of three existing synthetic runs immediately and after relaunch. [QA and screenshots](../../reports/2026-10-26-repeat-route-benchmarks.md). These results support the source fix; they are not evidence for a new uploaded binary.

## Draft release-note addition

Save a running route once and compare repeat runs with your previous run, personal best, average pace and trend. Saved run reports now show your route and benchmark comparisons, including earlier matching runs.

No archive, upload, submission, withdrawal, version change, or release was performed for this handoff.
