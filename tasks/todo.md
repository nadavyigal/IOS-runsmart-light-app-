## 2026-11-17 — Coach Mode Story 6.1

- [x] Implement route preparation, device-local sharing preference and retry, and an athlete-only write to `runs.route` and `runs.route_status`.
- [x] Verify the migration applies twice and the new SQL suite passes in throwaway embedded Postgres.
- [ ] Review Story 6.1 in #199, based on main after #193 landed.
- [ ] Mirror `20261117100000_coach_route_upload.sql` to the web migration tree at rollout. Production stays frozen.
- [ ] Keep `RouteUploadPolicy.isEnabled` false and the default preparer disabled until Story 6.4 implements privacy-zone trimming. Hold pilot invites until then.
- [ ] Story 6.2 must gate coach reads on an active link and `route_status = 'shared'`.

## 2026-11-16 — Coach Mode rollout

- Human Coach Mode is OFF by default. In an Xcode **Debug** run, add `-enable-coach-mode` under Scheme → Run → Arguments. Release builds (including current TestFlight archives) ignore the argument. There is no remote switch.
- Prior run completion/linking remains enabled because it is ordinary plan adherence. Existing database ownership rules and applied migrations remain in place. The flag stops coach role/link reads and user entry points.
- Production migrations are frozen. Never replay an already applied file. Read-only production migration history verified these equivalents:

| Repo file prefix | Production version | Migration |
| --- | --- | --- |
| 20261114120000 | 20261114191102 | close_cross_user_rls_leaks |
| 20261114130000 | 20261115065606 | runs_workout_link |
| 20261114210000 | 20261115065607 | coach_role_and_invites |
| 20261115091000 | 20261115173534 | coach_athlete_links |

## 2026-11-15 — Coach Mode pilot consent

- [x] Preserve the join intent through new-account onboarding.
- [x] Bind consent to the invite, coach and signed-in athlete. Return the stored link ID and consent time.
- [x] Verify the join migration twice on isolated Postgres and add its two-user tests to PR checks.
- [ ] Verify a new athlete reaches consent in the signed-in pilot app, including large Dynamic Type.
- [ ] Finish founder review of Story 1.3, then implement Story 1.5 before enabling the pilot.

## 2026-11-02 — Integrated Watch candidate

- [x] Owner reports the external tester completed beta38 testing successfully; retain as tester-reported evidence.
- [x] Reconcile PR165 with current main3c2d679, retaining iPhone improvements and project histories.
- [x] Red regression; recover Health lookup completion with persistent owner/target and safe retries.
- [x] Independent QA/race corrections; full841pass/0fail/1existing opt-in render skip.
- [x] Live ASC allocation:1.2.3(41), after complete1.2.2(40).
- [x] Push source4f20bc0 and verify signed archive, versions/signatures/HealthKit/privacy/dSYMs and actual-artifact backend HTTP200.
- [x] Owner signing approval; distribution IPA/signatures/debugging disabled/dSYMs/live backend pass.
- [x] Upload1.2.3(41); live ASC verifies Processing.
- [x] Assign exact processed build41 to Apple Watch Beta; save notes and submit external beta review: Waiting for Review, auto-notify enabled.
- [ ] Candidate41 paired Watch roundtrip and repeat-sync smoke.
- [ ] Separate public release decision after final candidate validation.

Older entries: [tasks/archive/todo-to-2026-10-29.md](archive/todo-to-2026-10-29.md).
