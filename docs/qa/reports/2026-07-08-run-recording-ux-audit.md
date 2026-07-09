# Run-Recording UX Audit — 2026-07-08

- Auditor: Fable 5 session (audit + spec, no implementation)
- Code under test: `main` @ `20f9a3a` (same recorder code as shipped 1.0.7 (21) — only docs commits after `6ed8b97`)
- Environment: **iPhone 17 Simulator, iOS 26.5, DEBUG + Demo Mode (`-RUNSMART_DEMO_MODE`)**, GPS simulated via `simctl location` ("City Run" scenario + fixed point)
- Build: Debug build from clean detached worktree `/tmp/runsmart-ux-audit` (main worktree still has Finder `* 2.swift` duplicates that break builds — see `tasks/progress.md` blocker)
- Screenshots: `docs/qa/reports/assets-2026-07-08-run-ux/`

## Global caveat — simulator only

All GPS-timing, background, lock-screen, and permission-prompt findings are **sim-only, need device confirm**. Specifically not tested: real time-to-GPS-lock outdoors, background recording with phone locked, the iOS location permission prompt (the sim had prior grant), thermal/battery, and pocket touches. State-machine findings (zombie recorder, layout overflow, dialog rendering) are code-confirmed and reproduce deterministically; they are not GPS-dependent.

## Scenario results

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 1 | First run (activation path) | **PASS with caveats** — Run tab → Start Run = 2 taps; recording began ~3 s after Start (sim GPS instant; device will be slower); GPS pill copy explains the wait and accuracy well; tab bar hides during recording and post-run | `02-prerun.png`, `03-after-start-tap.png` |
| 1b | "View Report" matches run | **PASS** — Report tab shows the saved run at correct distance | `10-view-report.png` |
| 2 | Pause / resume / discard | **FAIL** — pause/resume timing is correct (moving time freezes at 03:22, resumes cleanly), but (a) the paused 4-button row overflows the screen and shifts the whole layout, and (b) after Discard the app lands on a **zombie "Paused 00:00" live screen** instead of PreRun | `07-paused.png`, `13-discard-dialog.png`, `14-after-discard.png` |
| 3 | Short run edge case | **PASS** — "Finish this short run?" review-only copy shown; summary displays "Activity Saved / Review" chip, "Short activity saved" notice, and coach copy that refuses to over-analyze. Honest and well done | `16-short-run-finish-dialog.png`, `17-short-run-summary.png` |
| 4 | Finish / save / keep recording dialog | **UNCLEAR / FAIL on iOS 26 sim** — dialog copy is good and timer keeps recording behind it, but **"Keep Recording" / "Keep Workout" cancel buttons are not visible** in the compact alert rendering; only the confirm action shows. Escape hatch = tap outside, which nobody knows mid-run. Needs device confirm | `08-finish-dialog.png`, `13-discard-dialog.png` |
| 5 | Live screen information architecture | **PASS with gaps** — see element table below | `06-live-2min.png` |
| 6 | Post-run → second run same session | **FAIL (P0)** — after Save (or View Report), returning to the Run tab shows the finished run as a **frozen "Recording" screen** (zombie). No Start button, tab bar hidden, only escape is force-killing the app | `11-prerun-second.png`, `12-zombie-pause.png`, `19-after-delete.png` |
| 7 | Map quality | **MIXED** — live trace updates smoothly and matches the completed-route map; but the live map marks the runner's current position with a red **"Finish"** flag mid-run, the map is small (~13% of screen height), and the PreRun "GPS preview" is a decorative fake route, not a map | `06-live-2min.png`, `09-postrun-top.png`, `02-prerun.png` |

### Scenario 5 element table

| Element | Present? | Readable at glance? | Trustworthy? | Notes |
|---|---|---|---|---|
| Distance (km) | Yes | Yes — primary metric, huge | Yes | |
| Pace (/km) | Yes | Yes | Mostly — current pace from last 6 points, falls back to average silently | No label distinguishing current vs avg |
| Moving time | Yes | Yes | Yes | Appears twice (banner + Time tile), same value |
| Elapsed vs moving distinction | **No** | — | — | Elapsed is tracked in `RunRecorder` but never shown; `LiveRunView` param is even named `elapsedSeconds` while receiving `movingSeconds` |
| Live map / route trace | Yes | Small | Yes, once points exist | Current position labeled "Finish" (wrong); placeholder copy before first points is good |
| GPS accuracy indicator | Yes | Yes | **Excellent** — pill + meters tile + plain-language detail ("Weak GPS at Xm… keeps recording") | Best-in-class copy for this tier |
| Steps | No | — | — | See benchmark: not table stakes; defer |
| Calories | No | — | — | See benchmark: not table stakes; defer |
| Splits / lap | No (live) | — | — | Post-run "KM SPLITS" card shows **synthetic values** (avg pace ± fixed drift), not real splits — honesty problem |
| Pause / Resume | Yes | Yes — large, prominent | Yes | Haptics on tap |
| Finish (stop) | Yes | Yes | Yes — confirm dialog guards it | Cancel-visibility issue (Scenario 4) |
| Voice coach toggle | Yes ("Coach"/"Muted") | Yes | OK | Its presence makes the paused row 4 buttons wide → overflow |

## Quit points, ranked by severity

1. **P0 — Zombie recorder after save/discard/delete (Scenario 6).** `RunRecorder.finish()` and `discard()` never reset `phase`; `updatePhaseForAuthorization()` only remaps `.idle/.requestingPermission/.denied/.failed`, so `.recording`/`.paused` stick forever. After saving, the Run tab renders `LiveRunView` with the dead run's frozen stats, the tab bar is hidden, and there is no Start button. Discard from this state produces a second zombie ("Paused 00:00"). Only recovery: kill the app. Reproduced 3× (`11`, `12`, `14`, `19` screenshots). This ships in 1.0.7 (21) — daily single-run users rarely see it because an app restart between runs masks it, but any "finish → start another" session hits it immediately.
2. **P0 — Transient GPS error silently aborts an active run.** `locationManager(_:didFailWithError:)` sets `phase = .failed` on *any* error. During the audit a location-scenario switch threw `kCLErrorDomain` and the in-progress run (00:03 recording) vanished back to PreRun with only a small "GPS error" pill — no save, no explanation (`04-live-moving.png`). Apple docs say `kCLErrorLocationUnknown` is transient and should be ignored. On device, a momentary CL hiccup mid-run = lost run = uninstall-grade trust damage. (Sim-triggered; error injection path differs on device, but the code path is unconditional.)
3. **P1 — Paused control row overflows the screen.** Resume (112pt) + Finish + Coach + Discard (78pt each) + 3×18pt spacing + 36pt padding = **436pt on a 402pt screen**. The whole layout shifts left, the GPS pill and banner run off-edge, and "Discard" truncates (`07-paused.png`). Worse on smaller devices.
4. **P1 — Confirmation dialogs show no visible cancel.** Finish and Discard `confirmationDialog`s render on iOS 26 sim as a compact alert with only the confirm button; "Keep Recording"/"Keep Workout" never appear. A runner who tapped Finish by mistake sees no way back (needs device confirm).
5. **P1 — Post-run "KM SPLITS" are fabricated.** `PostRunSummaryView.splitRows` generates paces as `averagePace + ((km % 3) - 1) * 4s`. Presenting synthetic numbers as real splits fails the honesty bar (GLOBAL-TASTE: "says only what is true").
6. **P2 — Live map labels current position "Finish".** `RouteMapView` is shared between live and post-run without a mode flag (`06-live-2min.png`).
7. **P2 — PreRun trust gaps.** "GPS preview" panel is a decorative fake route drawing (`RunSmartRoutePreview` hard-coded path), and the "Last Run" card sits below the fold of a non-scrolling layout — effectively invisible (`02-prerun.png`).
8. **P2 — RPE selector input is discarded.** "How did that feel?" pre-selects 6/10 and the value only feeds on-screen copy; it is never persisted with the run.
9. **P3 — Elapsed vs moving time never explained** (single "Time" value; fine for v1 but Strava/Apple both expose the distinction or auto-pause).
10. **P3 — Delete dialog says "It will not delete anything from Garmin"** even for phone-recorded runs (`18-delete-dialog.png`), and `timeLabel` renders 1h30 as "90:00".

## What already works well (keep)

- GPS status pill: phase-aware, accuracy-aware, plain-language ("Stand near open sky…", "Weak GPS at Xm. RunSmart keeps recording…"). This is the calm-coach voice applied to sensor trust — better than Strava's silence.
- Start friction: 2 taps to recording, matching Strava/Apple.
- Short-run review-only flow: honest copy at finish, in the summary chip, notice card, and coach analysis.
- Finish is guarded, pause is instant, moving time math is correct through pause/resume (verified 03:22 freeze/resume).
- Live trace → completed-route map consistency is good; post-run summary lands fast with plan-fit copy that respects the runner.

## Competitive benchmark (Strava, Apple Fitness Outdoor Run)

Desk research (Strava support/press 2025 Record redesign; Apple Fitness iPhone workout docs). Principles RunSmart should meet at v1:

1. **Map + stats on one screen, no mode switching** — Strava's 2025 redesign headline. RunSmart already does this. ✔
2. **≤2 taps to recording** — both competitors. RunSmart ✔.
3. **Stats must be real** — Strava added *real-time* splits; Apple shows measured metrics only. RunSmart's fabricated post-run splits violate this; live splits are a later feature, honest splits are table stakes.
4. **Pause is prominent but protected** — Strava community complains about accidental pause from an oversized button; Apple offers Lock Controls. RunSmart's confirm-guarded Finish is right; keep Discard behind pause (current design) but fix the overflow.
5. **Finishing is reversible until explicitly saved, and the save state is explicit** — Strava routes Finish → save screen with a hard "discard is permanent" warning; Apple auto-saves with a summary. RunSmart follows the Apple model (auto-save + "Run Saved" hero) — honest, keep it; the gap is the invisible cancel in the finish dialog.
6. **A clean "start another" reset** — both competitors return to a ready-to-record screen immediately after saving. RunSmart currently fails this (zombie state).
7. **Calories/steps on the live screen are NOT table stakes** — Strava's live run stats are time/distance/pace/splits; Apple's iPhone-only Outdoor Run shows time/distance/pace (calories need Watch/HR hardware). **Recommendation: defer calories/steps**; a phone-GPS estimate would be low-trust filler and contradicts the calm-coach profile.

## Code-informed answers

- **Is `movingSeconds` vs `elapsedSeconds` explained to the user?** No. Only moving time is ever displayed (twice). `RunTabView` passes `recorder.movingSeconds` into a parameter named `elapsedSeconds`. Elapsed time exists in the model and is dropped in `RecordedRun` (only `movingTimeSeconds` is stored). Acceptable for v1 if labeled "Moving time" once; today it's just "Time".
- **When does the tab bar hide — can the user get trapped?** Hidden whenever `finishedRun != nil` or phase is `.recording`/`.paused` (`RunTabView.shouldHideTabBar`). By design you cannot leave the Run tab mid-run (same as Strava's record screen) — fine. But the zombie phase makes the hide permanent after saving: trapped until app kill. Fixing quit point #1 fixes the trap.
- **Does the VoiceCoach toggle belong on the primary control row?** Marginal. Mid-run mute is a legit need, but it is the 4th button that breaks the paused layout. Smallest fix: keep Coach on the row while recording, and swap it out for Discard when paused (never 4 buttons). Long-term it can live in the Audio sheet.
- **Post-run: is Done vs View Report vs implicit save obvious?** The run is already persisted inside `RunRecorder.finish()` (store + HealthKit) before the summary appears, and the hero honestly says "Run Saved". "Keep Activity" is actually just "dismiss", "View Report" also dismisses-and-navigates, "Delete" is the only real decision. Two green CTAs that both mean "leave" is mild redundancy, not a blocker. The dishonest part is the RPE selector whose value is thrown away.

## Verdict (per GLOBAL-TASTE)

**REVISE.** The skeleton is genuinely good — 2-tap start, one-screen map+stats, the most humane GPS-trust copy in this app tier, and an honest short-run path. But a recreational runner cannot yet trust it on a daily jog: finishing a run strands the app in a fake "Recording" screen until force-kill, a transient GPS error can silently eat an active run, the paused controls physically don't fit the screen, and the summary decorates itself with fabricated splits and a discarded effort rating. These are specific, small, fixable defects (see WP-37 S1–S5), not a wrong direction. Fix S1–S3 before spending a shekel marketing the recorder; ship the rest as polish.

## Session end note

No code changed; deliverables are this report + WP-37. Build worktree `/tmp/runsmart-ux-audit` (detached at `20f9a3a`) and derived data `/tmp/runsmart-ux-audit-dd` can be deleted.
