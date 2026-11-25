# RunSmart 1.2.7 (47) · Coach v2 TF-1a

Record the TestFlight version and build, archive source commit, test date, iOS versions, and which phone is the coach. Use dedicated QA accounts for link removal, consent, and route-sharing tests. Start with both phones on the same TestFlight build, and use an existing QA link for the upgrade-consent case and a fresh invite for the join case. Keep the production App Store pilot allowlist empty through TF-1a.

| Check | Device actions and pass criteria | Result |
|---|---|---|
| C7.0 · Release gate | Start with a TestFlight coach and a 1.2.6 athlete where a spare or unchanged install is available. Confirm the coach sees the upgrade state, with no v2 sharing or coach writes for the old client. Upgrade the athlete and wait for both phones to report TestFlight capability. A v2 App Store build with an unlisted coach must show base Coach Mode. Use the automated gate test as separate evidence if that App Store binary is unavailable. | Pending |
| C7.8 · Consent | On a fresh invite, review the v2 disclosures before accepting. On the existing link, confirm the athlete gets the upgrade notice and the coach cannot read v2 sharing before acknowledgment. After acknowledgment, eligible RPE from the prior 14 days appears and historical private notes stay private. Reopen the app to check the accepted notice stays dismissed. Exercise the leave option on a disposable link. | Pending |
| C7.1 · Coach Today | Seed a planned run, a completed run, and a case that needs attention. Confirm Coach Today shows the expected counts, order and filters. Open a row and verify it reaches the right athlete and day. Check the empty and all-clear states with QA data. | Pending |
| C7.3 · Effort and notes | Save a short recorded run on the athlete phone. Add effort and a note. Confirm the coach sees the current effort and note on that run. Hide the note and check that it disappears on refresh while the effort remains. Unhide it, edit the effort, and verify both phones agree after relaunch. Test note sync after a brief offline period. | Pending |
| C7.4 · Pain flags | Create a linked-run flag and a runless flag from Today. Verify the appropriate attention chip and detail, then mark one handled as coach. Confirm it leaves the open count. Remove the other as athlete and recheck the coach screen. | Pending |
| C7.7 · Replies | Send coach feedback. Reply as athlete from the matching feedback card, then check the coach sees the reply on the same thread. Retry once after a brief offline period and verify one reply. Confirm there is no second-level reply action. | Pending |
| C7.2 · New since last visit | After the coach last viewed the athlete, sync a run, flag or reply. Verify the new marker and reason. Open the detail and verify the marker clears without clearing unrelated athletes. Reopen after relaunch and check the marker does not reappear. | Pending |
| C7.16 · Milestones and praise | Verify a qualifying QA run shows First Run or Longest Run and the expected praise chip. Send one reaction and confirm the athlete sees it once. Use fixture evidence for the full-week and quiet-for-three-days cases if the QA accounts lack the required history. | Pending |
| C7.11 · End the link | On a disposable link, remove the athlete as coach. Confirm the athlete sees the neutral notice and the coach loses roster and old-link access. Rejoin on a fresh test link and repeat by leaving as athlete. Confirm the solo plan stays accessible and old feedback is read-only on the athlete phone. | Pending |
| C7.12 · Kill switch | With owner approval, run the global flag drill in a controlled window using dedicated QA accounts. Have the owner flip the flag. Foreground both phones and verify v2 UI disappears, server-side v2 reads/writes close, and base coaching remains usable. Stage or retain a queued QA flag, restore the prior flag value, and verify delivery once. Record elapsed time and restore evidence. Push delivery is a TF-1b check. | Pending |

## Release scope

- Base source is iOS main `25704dd235cc12399b3d9c733545ebdc1b68eb03`. It contains Coach v2 Batches A and B, the saved-route benchmark fix (`5c96738`), the Live Activity and weekly widget work, and the recent coach and debrief changes. The AI prompt upgrade is also deployed separately in production as `coach_message` v12.
- The owner saw 1.2.6 (44) in TestFlight. Apple's delivery record confirms 46 was used for 1.2.6. The 1.2.7 candidate uses build 47.
- The runner-name PR #229 is open with merge conflicts. Check that the QA coach can distinguish athletes in the intended pilot roster. Garmin worker recovery and push delivery have separate backend work.
- Record the signed archive's source SHA, app and extension versions, provisioning and entitlements, and the result of `scripts/verify-release-backend.py` against the archived and exported app before upload. The upload and two-phone results are pending.

## Release regression on the candidate

- Sign in, finish or reopen onboarding, make a plan, and verify Profile and Today in English and Hebrew.
- Record a short outdoor run with location permission. Confirm pause, resume, finish, Live Activity, persisted report, route, and widget update. Use visible UI or owner assistance for outdoor GPS, Lock Screen and permission prompts.
- Reopen a saved run. Confirm the map, Save Route with benchmark enabled by default, save-once matching for three runs, Previous, Route PB, Month Avg and Trend, and persistence after relaunch. Check that a different loop with nearby endpoints is excluded.
- Verify Apple Health import or export with the intended test data. Record Garmin separately, including whether only the app surface or actual import was verified.
- Exercise a linked athlete’s cloud debrief. On an eligible English device with Apple Intelligence and the feature enabled, exercise the opt-in on-device debrief with an unlinked QA account. Verify the app with the existing backend settings.

For each result, record Pass, Fail, or Blocked, the phone and build, the observed result, and sanitized screenshot or log evidence. Report the TestFlight-only checks separately from checks run with fixtures or a local build.
