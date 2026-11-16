## 2026-11-16 — Local Coach Mode QA

- Start Docker Desktop. Use Supabase CLI 3.1.0 and run `git fetch origin` to obtain the two pending migration branches. Run `./scripts/local-coach-qa.sh start` from this checkout. This calls `supabase start` in the ignored, unlinked `.local-coach-qa` directory on a loopback-only Docker network. It replays this checkout's iOS migrations and includes the #192 and #193 SQL from the fetched branches until those files land on main. The local-only bootstrap supplies the older iOS-facing schema and has no production data. It does not reproduce every hosted integration or service.
- Studio: [http://127.0.0.1:55323](http://127.0.0.1:55323). API: `http://127.0.0.1:55321`. Run `./scripts/local-coach-qa.sh status` to get the local anon or publishable key. Use `./scripts/local-coach-qa.sh stop` to call `supabase stop` against that same directory and keep the local data.
- In this checkout create the gitignored `RunSmartSecrets.xcconfig` with `SUPABASE_URL = http:/$()/127.0.0.1:55321` and `SUPABASE_PUBLISHABLE_KEY = <local anon/publishable key>`. The escaped slashes avoid xcconfig treating the URL as a comment. Use an iPhone simulator with the Debug scheme's Run arguments set to `-enable-coach-mode`. Sign out of any previous account first and sign in with a local seeded email.
- Local-only accounts: `coach@qa.example.test`, `athlete1@qa.example.test`, and `athlete2@qa.example.test`. All use `LocalCoachQA123!`. The coach code is `QA2345`. Both athletes have an active plan, three scheduled workouts, and one imported run each. They start unlinked so QA can exercise consent and revocation.
- A physical iPhone needs the Mac's LAN IP instead of localhost. A loopback-only stack cannot serve it directly. Keep this default configuration private and use a separately authorized, restricted LAN relay for physical-device QA.
- Run `./scripts/test-local-coach-qa.sh` for the six SQL suites. They use separate disposable Postgres instances because the test fixtures deliberately refuse a seeded database. The regular seeded stack remains available for manual QA. The local project omits Edge Runtime, storage service, and analytics services.

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
