# Plan: RunSmart iOS record-a-run UX (2026-10-22)

Source: Grok report `RunSmart-iOS-run-recording-UX-report.md` (22 Oct 2026), re-verified against `origin/main` @ `d57f314`.
Persona: a regular runner who uses Strava and Nike Run Club today.
Benchmark: Strava, Nike Run Club (NRC).

Status: PLAN, awaiting founder OK. One story at a time.

## 1. Verdict on the Grok report

Grok's 12 gaps are real, with two corrections:

- **Tel Aviv map default (report #5):** not visible to users. `RouteMapView` shows a placeholder until there are 2+ points, then fits the route on appear (`DesignSystem/RunSmartMapViews.swift:42-62`). The real live-map bug is different, see N2.
- **Health route (report #11):** the route type is only in `readTypes` (`Services/HealthKit/HealthKitSyncService.swift:291`); `shareTypes` (`:285`) holds only the workout. Writing a route or energy needs new **write** permissions, which means a new Health prompt for existing users.

## 2. New findings (missed by Grok)

Probe results come from a temporary XCTest run on the iPhone 17 simulator (iOS 26.5), 2026-10-22. See section 5.

| # | Finding | Evidence | Runner impact |
|---|---|---|---|
| N1 | Music is ducked for the whole run, not just during cues | `VoiceCoachService.swift:88-92` activates a `.duckOthers` session at run start and only deactivates at stop | Spotify/podcast is quieter for the entire run. Strava/NRC duck only while speaking |
| N2 | Live map stops following the runner after about 1.2 km | Camera refit key is `displayCount / 20` (`RunSmartMapViews.swift:35-38`), and the display route is capped at 240 points (`RunSmartProductionServices.swift:444, 709`) | Runner's dot leaves the frame mid-run |
| N3 | Splits disagree with total distance after a pause | `resume()` drops the pause gap from distance (`:540`), but `kilometerSplits` re-measures every point pair, gap included, and uses wall-clock timestamps (`:842-858`) | Split km lands in the wrong place; split pace includes pause time |
| N4 | GPS jitter adds distance while standing still; pace freezes | Any fix ≤65 m accuracy and ≥1 m move is added (`:692-737`). Current pace uses the last 6 points and never decays (`:470-479`) | Distance grows at a traffic light; pace shows running pace while stopped |
| N5 | "Finding GPS" can hang forever | Start is disabled while acquiring (`PreRunView.swift:38, 210`); no timeout, no cancel, no "start anyway" (`RunSmartProductionServices.swift:684-689`) | Runner in a city canyon cannot start. Strava/NRC start the clock immediately |
| N6 | Pausing in the background is the riskiest moment | `pause()` stops location updates (`:528`). Background location is the only thing keeping the app alive | iOS can suspend, then kill, a paused run. Auto-resume is impossible |
| N7 | Planned workout steps are ignored during the run | Steps are shown pre-run (`PreRunView.swift:336`), never in `LiveRunView` | The AI-coach differentiator is missing at the moment it matters (NRC Guided Runs) |
| N8 | Post-run screen has 3 "coach" sections and 4 "save" moments | `PostRunSummaryView.swift:28-138`: template `COACH ANALYSIS` labelled "AI", real AI debrief below it, `PLAN UPDATE` coach report. Alert "Finish and Save" → "Run Saved" → "View Report" (hint: "Saves this activity") → "Keep Activity" | Runner cannot tell what is AI, or whether the run is saved. Run is already saved at Finish (`RunSmartProductionServices.swift:580`) |
| N9 | Stat pill shows "Route: 847 pts" | `PostRunSummaryView.swift:199-202` | Meaningless number in the hero slot |
| N10 | No path to Strava | No Strava code in the app | A Strava user's RunSmart runs never reach Strava: real switching cost |
| N11 | Live HUD gives GPS accuracy a full tile, no average pace | `RunTabView.swift:151-158` | Wrong priorities vs NRC (distance, pace, time) |

## 3. Plan (stories, in order)

Effort is single-developer days, rough.

### Release A: never lose a run, trust the numbers

**S0. Quick fixes (0.5 day).** One PR, all small and independently testable.
- N1 audio: activate the session only around a cue; `.playback` + `.spokenAudio` + `[.duckOthers, .mixWithOthers]`; deactivate with `.notifyOthersOnDeactivation` after playback (`VoiceCoachService.swift:41-52, 88-92, 140-149`).
- N2 map: refit on route length, not point count, or follow user (full fix in S7). Minimal: key the camera on `routePoints.count / 20` of the raw route.
- Report #8: pass the planned workout type instead of `"easy"` (`SupabaseRunSmartServices.swift:1234`).
- N8 honesty: drop the "AI - GPS - RunSmart" label on the template card (`PostRunSummaryView.swift:550`).
- N9: replace "Route: N pts" with elevation gain or "Map" / "No map".
- Done when: unit tests for the camera key and debrief type; device check that Spotify stays at full volume between cues.

**S1. Crash and kill recovery (2-3 days).** Report P0 #1, plus N6.
- Codable `RunSessionCheckpoint` (startedAt, pause intervals, route points, distance, phase, workout). Write every 10 s and on pause/resume/finish. Delete on finish/discard.
- On launch: "You have an unfinished run (5.2 km, 31:04)". Resume / Save / Discard.
- While paused, keep location running at reduced accuracy (`kCLLocationAccuracyHundredMeters`) so iOS keeps the app alive. This also enables auto-resume (S5).
- Done when: force-quit mid-run (recording and paused) and relaunch restores distance, time and route.

**S2. Run data integrity (1.5 days).** N3, N4, report #7.
- Store pause intervals on `RecordedRun`; splits skip pause gaps (distance and time).
- Remove the 8-split cap; add a partial final split.
- Jitter filter: reject fixes whose implied speed > 12 m/s; when speed < 0.5 m/s and the move is within accuracy radius, do not add distance.
- Current pace: rolling 20-30 s path distance; show "--" after 10 s without movement.
- Done when: probe scenarios C, D, E pass as real tests.

**S3. GPS start (0.5 day).** N5.
- After 20 s of "Finding GPS": show "Start anyway" (timer starts, distance waits for a good fix) and "Cancel".
- Done when: simulator with no location shows both options and Cancel returns to PreRun.

### Release B: run like Strava and NRC

**S4. Local audio cues + real settings (2-3 days).** Report P0 #3.
- On-device `AVSpeechSynthesizer`: each km (distance, split pace, time), start/pause/resume/finish. Works for guests and offline.
- Replace `AudioCuesScaffold` (`SecondaryFlowView.swift:1537`) with real settings: on/off, every 1 km / 0.5 km / 5 min, which metrics. AI cue becomes an optional extra.
- Done when: guest in airplane mode hears every km.

**S5. Auto-pause (2 days).** Report P0 #2. Needs S1 (location alive while paused) and S2 (pause intervals).
- Pause after speed < 0.5 m/s for 8 s; resume on movement. Setting, default ON (Strava default is off; NRC on). Banner "Auto-paused", haptic, audio.
- Done when: GPX with a 30 s stop shows auto pause/resume and moving time excludes the stop.

**S6. End-of-run controls (1 day).** Report #4, N8.
- Finish = press and hold 1.5 s with fill ring + haptic. VoiceOver: double-tap opens the confirm alert.
- One end sheet: Save / Resume / Discard. Remove the separate Discard button.
- Done when: a single tap on Finish never ends a run.

**S7. Live screen layout (1.5 days).** Report #5, N11, N2 full fix.
- Two pages, swipe or toggle: Stats (distance huge, time, avg pace, current pace, calories) and Map (full screen, follows user with heading, metrics in a bottom card).
- GPS accuracy becomes a small status icon.
- Done when: map fills ≥60% of the screen in map mode; dot stays in frame for a 10 km GPX.

**S8. Calories (1 day).** Report #6.
- ACSM running formula from weight (HealthKit, then profile; ask once). Live tile, summary, labelled "est.".

### Release C: the AI-coach advantage

**S9. Guided structured workouts (3-4 days).** N7.
- Live: current step, time/distance left in step, target pace band (green/amber/red), next step preview.
- Audio at each step change ("Interval 3 of 6, 400 m at 4:30").
- Uses `StructuredWorkoutFactory.makeSteps(for:)`.

**S10. Post-run summary redesign (2-3 days).** Report #9, N8.
- Order: hero (distance, time, avg pace, elevation, calories) → map (tap for full screen) → one Coach section (real debrief; template card removed) → splits chart → plan update → share.
- Header says "Saved" once. Buttons: "Done" + overflow menu (Delete, Save route).
- Title and notes.

**S11. Apple Health route + energy (1 day).** Report #11.
- `HKWorkoutBuilder` + `HKWorkoutRouteBuilder`, pause events, energy. Adds write permissions for route and active energy.

**S12. Sharing and Strava (decision needed).** Report #10, N10.
- Opt-in map share image (private stays default).
- Strava upload via Strava API (OAuth + `POST /uploads` with GPX). Needs Strava API app approval.

## 4. Order and totals

S0 → S1 → S2 → S3 (Release A, ~5 days) → S4 → S5 → S6 → S7 → S8 (Release B, ~8 days) → S9 → S10 → S11 → S12 (Release C, ~8 days + Strava).

## 5. Probe evidence

Temporary test `ZZRecordRunUXProbeTests.swift` (not committed), iPhone 17 simulator, iOS 26.5:

- A (audio): `setCategory(.playback, .spokenAudio, [.duckOthers, .allowBluetoothHFP])` succeeds (options=7). So N1 is about the session staying active for the whole run, which is code-confirmed; needs one real-device check with Spotify.
- B (map, N2): raw route 500 m → camera key 5; 1.2 km, 2.5 km, 5 km, 15 km → camera key 12 every time. The camera never refits after ~1.2 km.
- C (splits, N3): 1.5 km + 5 min pause (walked 300 m) + 1 km, all at 5:00/km. Recorder distance 2,493 m (correct). Splits: km1 5:05, km2 8:30.
- D (jitter, N4): 2 min standing still, fixes every 2 s scattered ±12 m at 20 m accuracy: +735 m distance, current pace label "0:01". Harsh case; real drift is smaller but unfiltered.
- E (cap): 15 km run → 8 splits. Computing them takes 6 ms, fine for now.

## 6. Test plan

- GPX fixtures: 10 km with a 30 s stop; pause spanning a km boundary while walking 300 m; 2 min standing still with noisy fixes; 15 km long run.
- Force quit while recording and while paused; phone locked 30 min; airplane mode as guest.
- Real device before release: background GPS, Live Activity, music ducking with Spotify, Bluetooth headphones.
