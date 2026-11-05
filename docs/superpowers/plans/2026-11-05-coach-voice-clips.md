# Coach Voice Clips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run cues play short pre-recorded ElevenLabs coach clips per tone, joined with short Apple-voice numbers ("1 K. 5:10."), for free runs and planned workouts.

**Architecture:** A pure composer turns each moment (split, lifecycle, workout step) into a `CoachCue`: an ordered list of `.clip(moment)` and `.speech(text)` segments. A clip library resolves each clip to a bundled file (rotating 2 to 3 versions, falling back to Apple speech of the clip text). A small player plays the resolved segments one after another through injectable backends (`AVAudioPlayer` for clips, `AVSpeechSynthesizer` for numbers) and holds a ducking audio session only while a cue plays.

**Tech Stack:** Swift, SwiftUI, AVFoundation, XCTest. ElevenLabs creative MCP (`creative_list_voices`, `creative_generate_speech`) only at authoring time. macOS `afconvert` for AAC encoding.

**Spec:** `docs/superpowers/specs/2026-11-05-coach-voice-clips-design.md` (approved 2026-11-05). Read it before Task 1.

## Global Constraints

- No new dependencies. AVFoundation only in the app. Authoring scripts use Swift plus macOS `afconvert`.
- No API key, no ElevenLabs call, no network in the app's cue path. Cues work offline and while locked.
- Audio session: `.playback`, mode `.spokenAudio`, options `[.duckOthers]`, active only while a cue plays, deactivated with `.notifyOthersOnDeactivation`.
- Numbers are short: "1 K", "1.5 K", "5:10", "26:10", "10 minutes". Never "5 minutes 10 seconds" in a split or finish cue.
- Moving time is never in a split cue. The 5-minute cadence says "10 minutes." instead of the distance.
- A cue is never silent because a clip is missing: fall back to the Apple voice saying the clip's text.
- Never the same version of a moment twice in a row.
- The Apple voice keeps the T7 per-tone `speechRate` and `pitchMultiplier`.
- `CoachingTone` / `CoachingToneStore` stay the source of truth for the active tone.
- Clip files: AAC `.m4a`, mono, trimmed, loudness matched. Bundle file names are globally unique (synchronized groups copy resources flat): `coach-<voice>-<tone>-<moment>-<variant>.m4a`.
- Spending ElevenLabs credits: run `estimate_only` first, show the founder the estimate, generate only after the founder says yes. Never retry a generation by calling it again.
- Do not merge, bump the version, or upload a build. Push and open a PR only.
- Copy rules: no em dashes in any user-facing text, commit message, or PR body.

## Review Focus

1. **Phone locked, app in background when a cue fires.** The clip must still play. Pinned by Task 5 `testSessionOptionsAreMixableSoActivationWorksInBackground` plus the locked-phone check in Task 8.
2. **Music or a podcast playing.** It ducks for the cue and comes back after, including after `stop()` and after a clip fails to load. Pinned by Task 5 `testEveryActivationIsMatchedByOneDeactivation`.
3. **Two cues close together** (pause right after a split, a split while a step cue still plays). Queued cues wait, unqueued cues cut off, never two at once. Pinned by Task 5 `testQueuedCueWaitsAndUnqueuedCueInterrupts`.
4. **Runner turns cues off or discards the run mid-cue.** Sound stops at once and nothing queued plays later. Pinned by Task 6 `testDisablingCuesMidCueStopsAndDropsTheQueue`.
5. **Phone call interrupts a cue.** The queue is dropped and the session is not re-activated until the next cue. Pinned by Task 5 `testInterruptionDropsTheQueue`.

---

### Task 1: Lines, voice, and founder sample round (no app code)

**Files:**
- Create: `scripts/coach-voice/lines.json`
- Create: `scripts/coach-voice/render_samples.swift`
- Create: `docs/coach-voice/2026-11-05-voice-choice.md`

**Interfaces:**
- Produces: `scripts/coach-voice/lines.json`, an array of `{ "tone": "motivating|calm|technical", "moment": <CoachClipMoment raw value>, "variant": 1..3, "text": String, "delivery": String }`. Task 4 and Task 7 read it.

Moment raw values (exact, used everywhere): `splitOpen`, `splitClose`, `onTarget`, `aBitFast`, `aBitSlow`, `logged`, `started`, `restored`, `paused`, `autoPaused`, `resumed`, `finished`, `stepWarmup`, `stepWork`, `stepRecovery`, `stepCooldown`, `stepSteady`, `easeOff`, `pickItUp`, `workoutComplete`, `workoutPraise`.

Which tones have which moments:
- Motivating and Calm: every moment except `onTarget`, `aBitFast`, `aBitSlow`, `logged`. Calm has no `splitClose`.
- Technical: every moment except `splitOpen` and `splitClose`.

- [ ] **Step 1: Write `lines.json` with this copy.** Variant 1 is the founder-approved line where one exists.

| Moment | Motivating | Calm | Technical |
|---|---|---|---|
| splitOpen | Nice work. / Strong running. / That's it. | Smooth and easy. / Nice and relaxed. / Steady breathing. | none |
| splitClose | Keep it rolling. / Stay on it. / Keep that going. | none | none |
| onTarget | none | none | On target. / Right on pace. |
| aBitFast | none | none | A bit fast. / Slightly fast. |
| aBitSlow | none | none | A bit slow. / Slightly slow. |
| logged | none | none | Logged. / Split logged. |
| started | Run started. Let's go. / And we're off. | Run started. Ease in. / Here we go. Start gentle. | Run started. Clock is running. / Recording. Clock is running. |
| restored | Run restored. You're paused. / Back in. Still paused. | Run restored. Still paused. / Welcome back. Still paused. | Run restored. Paused. Totals kept. / Restored. Totals kept. |
| paused | Run paused. / Paused. Catch your breath. | Run paused. Take the rest. / Paused. Breathe easy. | Run paused. Moving time stopped. / Paused. Clock stopped. |
| autoPaused | Auto-paused. / Auto-paused. Ready when you are. | Auto-paused. Standing still. / Auto-paused. Take a moment. | Auto-paused. Speed is under the stop line. / Auto-paused. Below stop speed. |
| resumed | Run resumed. Back to it. / And we're moving. | Run resumed. Settle back in. / Moving again. Find your rhythm. | Run resumed. Moving time is counting. / Resumed. Clock running. |
| finished | Run finished. Great work. / That's a wrap. Great run. | Run finished. Easy work. / Run finished. Nicely done. | Run finished. Recorded totals. / Run finished. Final totals. |
| stepWarmup | Warm up. Ease into it. / Warm-up time. | Warm up. Keep it light. / Easy warm-up. | Warm-up. / Warm-up step. |
| stepWork | Here we go. / Time to work. | Work. Stay relaxed. / Rep time. Smooth effort. | Work interval. / Work rep. |
| stepRecovery | Recover. Shake it out. / Easy now. Recover. | Recover. Let it settle. / Easy jog. Breathe. | Recovery. / Recovery interval. |
| stepCooldown | Cool down. You earned it. / Bring it home easy. | Cool down. Let it go. / Easy to finish. | Cool-down. / Cool-down step. |
| stepSteady | Steady running. / Lock in steady. | Steady. Even effort. / Settle into steady. | Steady segment. / Steady block. |
| easeOff | Ease off a touch. / Too hot. Ease back. | Ease off. No rush. / A little softer. | Too fast. Ease off. / Over pace. Ease off. |
| pickItUp | Pick it up. / Little more. Push. | Pick it up, gently. / A touch more. | Too slow. Pick it up. / Under pace. Pick it up. |
| workoutComplete | Workout complete. | Workout complete. | Workout complete. |
| workoutPraise | Good job. / Well done. | Good job. / Well done. | Good job. / Well done. |

`delivery` is the per-tone ElevenLabs direction: read `creative_get_model_guide` for `eleven_v4` and pick one audio tag per tone (energetic and warm for Motivating, soft and slow for Calm, crisp and neutral for Technical). Same tag on every line of a tone.

- [ ] **Step 2: Pick the voice.** Call `creative_list_voices`. Choose one English voice that sounds like a real running coach, clear at phone-speaker volume, gender-neutral in casting is not required. Write `docs/coach-voice/2026-11-05-voice-choice.md` with: voice id, voice name, why, the three delivery tags, model `eleven_v4`, and the settings used.

- [ ] **Step 3: Estimate the sample round.** Samples are variant 1 of every moment, all three tones (about 50 clips). Call `creative_generate_speech` with `estimate_only: true` for the batch. Show the founder the credit estimate. Stop until the founder says yes.

- [ ] **Step 4: Generate the samples** (after the yes) into the scratchpad `coach-voice/raw/`, one file per line, named `<tone>-<moment>-<variant>` plus the extension the tool returns.

- [ ] **Step 5: Write `render_samples.swift` and render stitched full cues.** It renders Apple-voice numbers with `AVSpeechSynthesizer.write` at the tone's T7 rate and pitch (see `CoachingTone.speechRate` / `pitchMultiplier`), concatenates clip, 120 ms silence, numbers, 120 ms silence, clip into one `.caf`, then `afconvert` to `.m4a`. Render per tone: a split ("1 K. 5:10." / Technical "Kilometer 1. Pace 5:10."), pause, a rep start ("Rep 3 of 6. 400 metres. 4:30 to 4:40."), finish ("5 K. 26:10."), workout complete.

Run: `swift scripts/coach-voice/render_samples.swift <raw-dir> <out-dir>`
Expected: 15 files in `<out-dir>`, each plays with no clipped word.

- [ ] **Step 6: Send samples to the founder.** Send the per-tone clip files and the 15 stitched cues with `SendUserFile`. Ask one question: approve the voice and the lines, or what to change. **Stop. No app code until the founder approves.** Apply line changes to `lines.json` before Task 7.

- [ ] **Step 7: Commit**

```bash
git add scripts/coach-voice/lines.json scripts/coach-voice/render_samples.swift docs/coach-voice/2026-11-05-voice-choice.md
git commit -m "chore(voice): coach lines, voice choice, sample renderer"
```

---

### Task 2: Short numbers and split facts

**Files:**
- Create: `IOS RunSmart app/Services/CoachVoice/CoachNumbers.swift`
- Modify: `IOS RunSmart app/Services/LocalRunCueService.swift:33-102` (`RunCueSchedule.update` returns facts, not text)
- Test: `IOS RunSmart appTests/CoachNumbersTests.swift`, `IOS RunSmart appTests/LocalRunCueTests.swift`

**Interfaces:**
- Produces:
  - `enum CoachNumbers` with `static func distanceMark(meters: Double) -> String` ("1 K", "1.5 K"; km rounded to 0.1), `static func technicalDistanceMark(meters: Double) -> String` ("Kilometer 1", "Kilometer 1.5"), `static func pace(secondsPerKm: Double) -> String` ("5:10"), `static func clock(seconds: TimeInterval) -> String` ("26:10", "1:02:10"), `static func minutesMark(seconds: TimeInterval) -> String` ("10 minutes", "1 minute"), `static func finishDistance(meters: Double) -> String` ("5 K", "5.02 K"; km rounded to 0.01), `static func stepTarget(_ target: GuideStep.Target) -> String` (distance under 1000 m: "400 metres"; from 1000 m: `distanceMark`; duration: `WorkoutGuideFormat.spokenTarget`).
  - `struct SplitFacts: Equatable { var cadence: RunCueSettings.Cadence; var startDistance: Double; var crossingDistance: Double; var crossingTime: TimeInterval; var paceSecondsPerKm: Double? }` (pace nil when the split is under 20 m or 0 s, same rule as today).
  - `RunCueSchedule.update(distance:movingTime:settings:) -> SplitFacts?`. Returns nil when cues are disabled (the baseline still advances, as today).

- [ ] **Step 1: Write the failing tests** in `CoachNumbersTests.swift`:

```swift
func testShortNumbers() {
    XCTAssertEqual(CoachNumbers.distanceMark(meters: 1_000), "1 K")
    XCTAssertEqual(CoachNumbers.distanceMark(meters: 1_500), "1.5 K")
    XCTAssertEqual(CoachNumbers.distanceMark(meters: 9_999.6), "10 K")
    XCTAssertEqual(CoachNumbers.technicalDistanceMark(meters: 1_500), "Kilometer 1.5")
    XCTAssertEqual(CoachNumbers.pace(secondsPerKm: 310), "5:10")
    XCTAssertEqual(CoachNumbers.pace(secondsPerKm: 299.6), "5:00")
    XCTAssertEqual(CoachNumbers.clock(seconds: 1_570), "26:10")
    XCTAssertEqual(CoachNumbers.clock(seconds: 3_730), "1:02:10")
    XCTAssertEqual(CoachNumbers.minutesMark(seconds: 600), "10 minutes")
    XCTAssertEqual(CoachNumbers.finishDistance(meters: 5_000), "5 K")
    XCTAssertEqual(CoachNumbers.finishDistance(meters: 5_021), "5.02 K")
    XCTAssertEqual(CoachNumbers.stepTarget(.distance(meters: 400)), "400 metres")
    XCTAssertEqual(CoachNumbers.stepTarget(.distance(meters: 1_500)), "1.5 K")
    XCTAssertEqual(CoachNumbers.stepTarget(.duration(seconds: 90)), "90 seconds")
}
```

In `LocalRunCueTests.swift`, change the existing string assertions to `SplitFacts` assertions with the same distances, times and paces the tests use today (for example a first kilometre in 300 s gives `crossingDistance == 1_000`, `paceSecondsPerKm == 300`). Keep every existing scenario (pause time skipped, half-km and 5-min cadence, recovered run, disabled cues advance the baseline, overshoot interpolation, auto-pause rollback).

- [ ] **Step 2: Run to see them fail**

Run: `xcodebuild test -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"IOS RunSmart appTests/CoachNumbersTests" -only-testing:"IOS RunSmart appTests/LocalRunCueTests"`
Expected: build fails, `CoachNumbers` and `SplitFacts` not found.

- [ ] **Step 3: Implement `CoachNumbers` and change `RunCueSchedule.update` to return `SplitFacts?`.** The settings toggles no longer shape text here; the composer applies them (Task 3). Remove `RunCueSchedule.duration` once Task 6 replaces its last caller; until then leave it.

- [ ] **Step 4: Run the tests.** Same command. Expected: PASS. `LocalRunCueService.update` will not compile until Task 6; keep it compiling by mapping facts to the old text inside `update` for now (temporary, deleted in Task 6).

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Services/CoachVoice/CoachNumbers.swift" "IOS RunSmart app/Services/LocalRunCueService.swift" "IOS RunSmart appTests/CoachNumbersTests.swift" "IOS RunSmart appTests/LocalRunCueTests.swift"
git commit -m "feat(voice): short spoken numbers and split facts"
```

---

### Task 3: Workout guide events and the Technical verdict

**Files:**
- Modify: `IOS RunSmart app/Services/WorkoutGuide.swift:134-138` (`Announcement`), `:208-221` (`update`), add `splitVerdict`
- Test: `IOS RunSmart appTests/WorkoutGuideTests.swift`

**Interfaces:**
- Produces:
  - `WorkoutGuide.Announcement` becomes `struct Announcement: Equatable { enum Event: Equatable { case stepStart(GuideStep), complete, reminder(PaceStatus) }; var event: Event; var text: String { get }; var isReminder: Bool { get } }`. `text` keeps today's strings (`spokenStart`, "Workout complete.", "Ease off.", "Pick it up.") so the AI path and existing assertions on `.text` still hold.
  - `enum SplitVerdict: Equatable { case onTarget, fast, slow }`
  - `func splitVerdict(fromDistance: Double, toDistance: Double, paceSecondsPerKm: Double) -> SplitVerdict?` on `WorkoutGuide`. Returns a verdict only when the whole interval lies inside one step that has a `paceBand` (1 m slack at both ends). Step `i` spans `starts[i].distance` to `starts[i+1].distance`, or `finishedAt.distance` for the last step, or open-ended for the current step. Compare with `paceTolerance`: faster than `band.fast - 5` is `.fast`, slower than `band.slow + 5` is `.slow`, else `.onTarget`.

- [ ] **Step 1: Write the failing tests**

```swift
func testSplitInsideOneBandedStepGetsAVerdict() {
    var guide = WorkoutGuide(steps: [
        GuideStep(kind: .work, target: .distance(meters: 2_000), paceBand: GuidePaceBand(center: 300))
    ])!
    _ = guide.update(distance: 1_000, movingTime: 300)
    XCTAssertEqual(guide.splitVerdict(fromDistance: 0, toDistance: 1_000, paceSecondsPerKm: 300), .onTarget)
    XCTAssertEqual(guide.splitVerdict(fromDistance: 0, toDistance: 1_000, paceSecondsPerKm: 280), .fast)
    XCTAssertEqual(guide.splitVerdict(fromDistance: 0, toDistance: 1_000, paceSecondsPerKm: 320), .slow)
}

func testSplitAcrossARepAndARecoveryGetsNoVerdict() {
    var guide = WorkoutGuide(steps: [
        GuideStep(kind: .work, target: .distance(meters: 400), paceBand: GuidePaceBand(center: 270)),
        GuideStep(kind: .recovery, target: .distance(meters: 600))
    ])!
    _ = guide.update(distance: 1_000, movingTime: 330)
    XCTAssertNil(guide.splitVerdict(fromDistance: 0, toDistance: 1_000, paceSecondsPerKm: 330))
}

func testSplitInsideAStepWithoutABandGetsNoVerdict() {
    var guide = WorkoutGuide(steps: [GuideStep(kind: .steady, target: .distance(meters: 5_000))])!
    _ = guide.update(distance: 1_000, movingTime: 300)
    XCTAssertNil(guide.splitVerdict(fromDistance: 0, toDistance: 1_000, paceSecondsPerKm: 300))
}

func testAnnouncementsCarryTheirEvent() {
    var guide = WorkoutGuide(steps: [
        GuideStep(kind: .work, target: .distance(meters: 400), paceBand: GuidePaceBand(center: 270), repIndex: 1, repTotal: 2)
    ])!
    XCTAssertEqual(guide.update(distance: 0, movingTime: 0).map(\.event), [.stepStart(guide.steps[0])])
    XCTAssertEqual(guide.update(distance: 400, movingTime: 110).map(\.event), [.complete])
}
```

Update every existing `WorkoutGuide.Announcement(text:isReminder:)` construction in tests (`WorkoutGuideTests.swift:230`, `CoachingToneCueTests.swift:152`) to the `event:` form.

- [ ] **Step 2: Run to see them fail**

Run: same `xcodebuild test` command with `-only-testing:"IOS RunSmart appTests/WorkoutGuideTests"`
Expected: compile failure on `event` / `splitVerdict`.

- [ ] **Step 3: Implement the `Event` enum, computed `text` / `isReminder`, and `splitVerdict`.**

- [ ] **Step 4: Run the tests.** Expected: PASS, including every existing WorkoutGuide test.

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Services/WorkoutGuide.swift" "IOS RunSmart appTests/WorkoutGuideTests.swift" "IOS RunSmart appTests/CoachingToneCueTests.swift"
git commit -m "feat(voice): workout guide events and split verdict"
```

---

### Task 4: Cue composer

**Files:**
- Create: `IOS RunSmart app/Services/CoachVoice/CoachCue.swift`
- Create: `IOS RunSmart app/Services/CoachVoice/CoachCueComposer.swift`
- Modify: `IOS RunSmart app/Services/CoachingTone.swift:129-136` (`CoachCueEvent.finished` carries numbers)
- Test: `IOS RunSmart appTests/CoachCueComposerTests.swift`

**Interfaces:**
- Consumes: `SplitFacts`, `CoachNumbers` (Task 2); `WorkoutGuide.Announcement.Event`, `SplitVerdict` (Task 3).
- Produces:
  - `enum CoachClipMoment: String, Codable, CaseIterable` with the raw values listed in Task 1, plus `var fallbackText: String` (the Motivating variant 1 line, or "Workout complete." / "Good job." / "On target." etc. for Technical-only moments).
  - `enum CueSegment: Equatable { case clip(CoachClipMoment), speech(String) }`
  - `struct CoachCue: Equatable { let segments: [CueSegment]; init(_ segments: [CueSegment]) }`. The init merges neighbouring `.speech` segments with one space, so two Apple-voice parts never play as separate utterances.
  - `CoachCueEvent.finished(distanceMeters: Double, movingSeconds: TimeInterval)` replaces `.finished(detail:)`.
  - `enum CoachCueComposer` with:
    - `static func lifecycle(_ event: CoachCueEvent, tone: CoachingTone) -> CoachCue`
    - `static func tick(split: SplitFacts?, settings: RunCueSettings, verdict: SplitVerdict?, guide: [WorkoutGuide.Announcement], tone: CoachingTone) -> CoachCue?`

Composition rules (exact):
- Split numbers, Motivating and Calm: `"<mark>. <pace>."` where mark is `distanceMark(crossingDistance)` or, on the 5-minute cadence, `minutesMark(crossingTime)`. Pace alone: `"Pace <pace>."`. Mark alone: `"<mark>."`.
- Split numbers, Technical: `"<technicalDistanceMark>. Pace <pace>."` (5-minute cadence: `"<minutesMark>. Pace <pace>."`). Mark alone: `"<mark>."`. Pace alone: `"Pace <pace>."`.
- `settings.distance` controls the mark in every cadence. `settings.pace` controls the pace. No mark and no pace: no split cue at all.
- Split segments: Motivating `[.clip(.splitOpen), .speech(numbers), .clip(.splitClose)]`; Calm `[.clip(.splitOpen), .speech(numbers)]`; Technical `[.speech(numbers), .clip(closer)]` where closer is `.onTarget` / `.aBitFast` / `.aBitSlow` from `verdict`, or `.logged` when `verdict` is nil or the split has no pace.
- When the same tick has a `.stepStart` or `.complete` event, drop the split's closing clip (Motivating `splitClose`, Technical closer) and append the guide segments.
- Step start: `[.clip(stepMoment(kind)), .speech(numbers)]`. Numbers: rep step `"Rep 3 of 6. 400 metres. 4:30 to 4:40."`; other steps `"<stepTarget>."` plus `" <fast> to <slow>."` when banded (pace via `CoachNumbers.pace`).
- Complete: `[.clip(.workoutComplete), .clip(.workoutPraise)]`.
- Reminder: `[.clip(.easeOff)]` for `.tooFast`, `[.clip(.pickItUp)]` for `.tooSlow`. Reminders are dropped when a split speaks (today's rule).
- Lifecycle: `[.clip(<moment>)]`; finish `[.clip(.finished), .speech("<finishDistance>. <clock>.")]`.

- [ ] **Step 1: Write the failing tests**

```swift
private func facts(_ d: Double, _ t: TimeInterval, pace: Double? = 310, cadence: RunCueSettings.Cadence = .kilometer) -> SplitFacts {
    SplitFacts(cadence: cadence, startDistance: d - 1_000, crossingDistance: d, crossingTime: t, paceSecondsPerKm: pace)
}

func testSplitPerTone() {
    let s = RunCueSettings()
    XCTAssertEqual(CoachCueComposer.tick(split: facts(1_000, 310), settings: s, verdict: nil, guide: [], tone: .motivating)?.segments,
                   [.clip(.splitOpen), .speech("1 K. 5:10."), .clip(.splitClose)])
    XCTAssertEqual(CoachCueComposer.tick(split: facts(1_000, 310), settings: s, verdict: nil, guide: [], tone: .calm)?.segments,
                   [.clip(.splitOpen), .speech("1 K. 5:10.")])
    XCTAssertEqual(CoachCueComposer.tick(split: facts(1_000, 310), settings: s, verdict: .onTarget, guide: [], tone: .technical)?.segments,
                   [.speech("Kilometer 1. Pace 5:10."), .clip(.onTarget)])
    XCTAssertEqual(CoachCueComposer.tick(split: facts(1_000, 310), settings: s, verdict: nil, guide: [], tone: .technical)?.segments,
                   [.speech("Kilometer 1. Pace 5:10."), .clip(.logged)])
}

func testFiveMinuteCadenceSaysTheTimeNotTheDistance() {
    let cue = CoachCueComposer.tick(split: facts(1_900, 600, cadence: .fiveMinutes), settings: RunCueSettings(), verdict: nil, guide: [], tone: .calm)
    XCTAssertEqual(cue?.segments, [.clip(.splitOpen), .speech("10 minutes. 5:10.")])
}

func testSettingsShapeTheNumbersAndNoNumbersMeansNoCue() {
    var s = RunCueSettings(); s.distance = false
    XCTAssertEqual(CoachCueComposer.tick(split: facts(1_000, 310), settings: s, verdict: nil, guide: [], tone: .calm)?.segments,
                   [.clip(.splitOpen), .speech("Pace 5:10.")])
    s.pace = false
    XCTAssertNil(CoachCueComposer.tick(split: facts(1_000, 310), settings: s, verdict: nil, guide: [], tone: .calm))
}

func testSplitWithAStepDropsTheClosingClip() {
    let rep = GuideStep(kind: .work, target: .distance(meters: 400), paceBand: GuidePaceBand(center: 275), repIndex: 3, repTotal: 6)
    let cue = CoachCueComposer.tick(split: facts(1_000, 310), settings: RunCueSettings(), verdict: nil,
                                    guide: [.init(event: .stepStart(rep))], tone: .motivating)
    XCTAssertEqual(cue?.segments, [.clip(.splitOpen), .speech("1 K. 5:10."), .clip(.stepWork), .speech("Rep 3 of 6. 400 metres. 4:30 to 4:40.")])
}

func testRemindersOnlyWithoutASplit() {
    let tooFast = WorkoutGuide.Announcement(event: .reminder(.tooFast))
    XCTAssertEqual(CoachCueComposer.tick(split: nil, settings: RunCueSettings(), verdict: nil, guide: [tooFast], tone: .calm)?.segments, [.clip(.easeOff)])
    XCTAssertEqual(CoachCueComposer.tick(split: facts(1_000, 310), settings: RunCueSettings(), verdict: nil, guide: [tooFast], tone: .calm)?.segments,
                   [.clip(.splitOpen), .speech("1 K. 5:10.")])
}

func testWorkoutCompleteAndFinish() {
    XCTAssertEqual(CoachCueComposer.tick(split: nil, settings: RunCueSettings(), verdict: nil, guide: [.init(event: .complete)], tone: .technical)?.segments,
                   [.clip(.workoutComplete), .clip(.workoutPraise)])
    XCTAssertEqual(CoachCueComposer.lifecycle(.finished(distanceMeters: 5_000, movingSeconds: 1_570), tone: .calm).segments,
                   [.clip(.finished), .speech("5 K. 26:10.")])
    XCTAssertEqual(CoachCueComposer.lifecycle(.paused, tone: .technical).segments, [.clip(.paused)])
}

func testNeighbouringSpeechMerges() {
    XCTAssertEqual(CoachCue([.speech("1 K."), .speech("5:10.")]).segments, [.speech("1 K. 5:10.")])
}
```

- [ ] **Step 2: Run to see them fail.** `-only-testing:"IOS RunSmart appTests/CoachCueComposerTests"`. Expected: compile failure.

- [ ] **Step 3: Implement `CoachCue.swift` and `CoachCueComposer.swift`; change `CoachCueEvent.finished`.** Keep `CoachCueSpeech.line(for:tone:)` and `splitLine` until Task 6 removes their callers; update `line(for: .finished)` to build its detail from the new associated values so it still compiles.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Services/CoachVoice/CoachCue.swift" "IOS RunSmart app/Services/CoachVoice/CoachCueComposer.swift" "IOS RunSmart app/Services/CoachingTone.swift" "IOS RunSmart appTests/CoachCueComposerTests.swift"
git commit -m "feat(voice): compose cues from coach clips and short numbers"
```

---

### Task 5: Clip library, rotation, and player

**Files:**
- Create: `IOS RunSmart app/Services/CoachVoice/CoachClipLibrary.swift`
- Create: `IOS RunSmart app/Services/CoachVoice/CoachCuePlayer.swift`
- Test: `IOS RunSmart appTests/CoachClipLibraryTests.swift`, `IOS RunSmart appTests/CoachCuePlayerTests.swift`

**Interfaces:**
- Consumes: `CoachCue`, `CueSegment`, `CoachClipMoment` (Task 4).
- Produces:
  - `struct CoachVoiceManifest: Codable, Equatable { var voiceId: String; var voiceName: String; var model: String; var clips: [Clip] }`, `struct Clip: Codable, Equatable { var id: String; var tone: String; var moment: String; var variant: Int; var text: String; var file: String; var gainDb: Float; var settings: [String: String] }`.
  - `enum CoachVoice { static let activeSlug: String }` (set in Task 7; use `"coach"` until then).
  - `struct CueRotation { init(random: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }); mutating func pick(_ key: String, count: Int) -> Int }`. Never returns the previous index for the same key when `count > 1`.
  - `enum ResolvedSegment: Equatable { case clip(url: URL, gain: Float, text: String), speech(String) }`
  - `struct CoachClipLibrary { init(manifest: CoachVoiceManifest?, fileURL: (String) -> URL?); static func bundled(_ bundle: Bundle = .main) -> CoachClipLibrary; func resolve(_ cue: CoachCue, tone: CoachingTone, rotation: inout CueRotation) -> [ResolvedSegment] }`. A clip with no manifest entry for that tone and moment, or whose file URL is nil, becomes `.speech(text)` (the chosen variant's text, else `moment.fallbackText`). After resolving, neighbouring `.speech` segments merge with one space. `gain` is `pow(10, gainDb / 20)`.
  - `extension Array where Element == ResolvedSegment { var transcript: String }`: texts joined by one space.
  - Backend protocols (`@MainActor`): `protocol CueClipBackend { func play(url: URL, gain: Float, completion: @escaping (Bool) -> Void) -> Bool; func stop() }`, `protocol CueSpeechBackend { func speak(_ text: String, rate: Float, pitch: Float, completion: @escaping () -> Void); func stop() }`, `protocol CueAudioSession { func activate() -> Bool; func deactivate() }`. `play` returns false when the file cannot load; the player then speaks the clip text.
  - `struct CueAudioSessionConfig { static let category: AVAudioSession.Category = .playback; static let mode: AVAudioSession.Mode = .spokenAudio; static let options: AVAudioSession.CategoryOptions = [.duckOthers] }`
  - `@MainActor final class CoachCuePlayer { init(clips: CueClipBackend, speech: CueSpeechBackend, session: CueAudioSession, notificationCenter: NotificationCenter = .default); func play(_ segments: [ResolvedSegment], rate: Float, pitch: Float, queued: Bool); func stop(); var isPlaying: Bool { get } }` plus live backends `AVClipBackend` (AVAudioPlayer + delegate), `AVSpeechBackend` (AVSpeechSynthesizer with `usesApplicationAudioSession = true`, en-US system voice), `SystemCueAudioSession` (applies `CueAudioSessionConfig`, deactivates with `.notifyOthersOnDeactivation`).

Player rules: activate the session when a cue starts from idle; play segments in order, each starting on the previous one's completion; when the queue is empty, deactivate. `queued: true` appends to the queue; `queued: false` stops the current segment, clears the queue, and starts the new cue. `stop()` stops, clears, and deactivates if active. On `AVAudioSession.interruptionNotification` with type `.began`: same as `stop()`. If `activate()` fails, still try to play (the system may play unducked) and do not call `deactivate()` for that cue.

- [ ] **Step 1: Write the failing tests.** Library (fixture manifest built in the test, file URLs from a dictionary):

```swift
func testResolveUsesTheToneClipAndFallsBackToSpeech() {
    let manifest = CoachVoiceManifest(voiceId: "v", voiceName: "V", model: "eleven_v4", clips: [
        .init(id: "calm.splitOpen.1", tone: "calm", moment: "splitOpen", variant: 1, text: "Smooth and easy.", file: "a.m4a", gainDb: 0, settings: [:])
    ])
    let url = URL(fileURLWithPath: "/tmp/a.m4a")
    let library = CoachClipLibrary(manifest: manifest, fileURL: { $0 == "a.m4a" ? url : nil })
    var rotation = CueRotation(random: { _ in 0 })
    let resolved = library.resolve(CoachCue([.clip(.splitOpen), .speech("1 K. 5:10.")]), tone: .calm, rotation: &rotation)
    XCTAssertEqual(resolved, [.clip(url: url, gain: 1, text: "Smooth and easy."), .speech("1 K. 5:10.")])
    let missing = library.resolve(CoachCue([.clip(.paused)]), tone: .calm, rotation: &rotation)
    XCTAssertEqual(missing, [.speech(CoachClipMoment.paused.fallbackText)])
}

func testRotationNeverRepeatsBackToBack() {
    var rotation = CueRotation(random: { _ in 0 })
    var picks: [Int] = []
    for _ in 0..<6 { picks.append(rotation.pick("calm.splitOpen", count: 3)) }
    for (a, b) in zip(picks, picks.dropFirst()) { XCTAssertNotEqual(a, b) }
    XCTAssertEqual(rotation.pick("calm.paused", count: 1), 0)
}
```

Player, with fake backends that record calls and let the test fire completions:

```swift
func testSegmentsPlayInOrderAndTheSessionClosesAfter()
// play [.clip, .speech, .clip]: clip1 starts; finish it -> speech starts with the given rate/pitch; finish -> clip2; finish -> session.deactivate called once, isPlaying false.

func testAClipThatFailsToLoadIsSpoken()
// clips.play returns false -> speech backend receives the clip's text.

func testQueuedCueWaitsAndUnqueuedCueInterrupts()
// cue A playing; play B queued -> B starts only after A's last completion.
// cue A playing; play C unqueued -> clips.stop and speech.stop called, C's first segment starts, A's rest never plays.

func testEveryActivationIsMatchedByOneDeactivation()
// three sequences: normal finish, stop() mid-cue, failed clip load. Each ends with activate count == deactivate count == 1.

func testInterruptionDropsTheQueue()
// post interruptionNotification (type .began) on the injected center mid-cue: backends stopped, queue empty, a later completion callback plays nothing.

func testSessionOptionsAreMixableSoActivationWorksInBackground() {
    XCTAssertEqual(CueAudioSessionConfig.category, .playback)
    XCTAssertEqual(CueAudioSessionConfig.mode, .spokenAudio)
    XCTAssertTrue(CueAudioSessionConfig.options.contains(.duckOthers))
}
```

Write each commented test as code with those exact assertions.

- [ ] **Step 2: Run to see them fail.** `-only-testing:"IOS RunSmart appTests/CoachClipLibraryTests" -only-testing:"IOS RunSmart appTests/CoachCuePlayerTests"`. Expected: compile failure.

- [ ] **Step 3: Implement the library, rotation, player and live backends.** Late completions from a stopped segment must be ignored (tag each segment start with a generation counter).

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Services/CoachVoice/CoachClipLibrary.swift" "IOS RunSmart app/Services/CoachVoice/CoachCuePlayer.swift" "IOS RunSmart appTests/CoachClipLibraryTests.swift" "IOS RunSmart appTests/CoachCuePlayerTests.swift"
git commit -m "feat(voice): clip library with rotation and a sequenced cue player"
```

---

### Task 6: Wire cues into the run

**Files:**
- Modify: `IOS RunSmart app/Services/LocalRunCueService.swift:126-205`
- Modify: `IOS RunSmart app/Services/Production/RunSmartProductionServices.swift:650,696,719,721,754,800-801,871,1333-1339`
- Modify: `IOS RunSmart app/Services/CoachingTone.swift:138-196` (remove `PreparedCueSpeech`, `CoachCueSpeech.splitLine`, `CoachCueSpeech.line`, `CoachCueSpeech.prepared`; keep `spokenLanguageNote`)
- Modify: `IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift:1605-1607` (cue toggles)
- Test: `IOS RunSmart appTests/CoachingToneCueTests.swift`, `IOS RunSmart appTests/RunLiveReviewFixesTests.swift`, `IOS RunSmart appTests/RunMergeLeftoverTests.swift`, `IOS RunSmart appTests/WorkoutGuideTests.swift:225-240`

**Interfaces:**
- Consumes: everything from Tasks 2 to 5.
- Produces (on `LocalRunCueService`):
  - `func begin(distance: Double = 0, movingTime: TimeInterval = 0, recovered: Bool = false, tone: CoachingTone = CoachingToneStore.load())`
  - `func update(distance: Double, movingTime: TimeInterval, guide: [WorkoutGuide.Announcement] = [], guideState: WorkoutGuide? = nil, tone: CoachingTone = CoachingToneStore.load())`. Verdict: `guideState?.splitVerdict(fromDistance: facts.startDistance, toDistance: facts.crossingDistance, paceSecondsPerKm: pace)` when Technical and the split has a pace.
  - `func announce(_ event: CoachCueEvent, queued: Bool = false, debounce kind: RunCueRepeatKind? = nil, now: Date = Date(), tone: CoachingTone = CoachingToneStore.load())`
  - `var speechHandler: ((String) -> Void)?` still exists and receives the resolved `transcript`, so tests stay free of audio devices.
  - `private(set) var lastCue: (cue: CoachCue, tone: CoachingTone, rate: Float, pitch: Float)?` replaces `lastPreparedSpeech` (make it a small `Equatable` struct `PlayedCue`).
  - `var isSpeaking: Bool` reads `player.isPlaying`.
  - `var rotation: CueRotation` and `var library: CoachClipLibrary` are internal vars so tests can inject a fixed rotation and a fixture library.
- Settings screen: remove the "Moving time" toggle (time is no longer in splits; finish always says it). Label the distance toggle `cues.settings.cadence == .fiveMinutes ? "Time mark" : "Distance"`. Keep `RunCueSettings.time` in the struct so saved settings still decode; nothing reads it.

Cue gating and priority stay as today: split cues interrupt (`queued: false`), guide-only cues queue, pause/resume/auto-pause queue, auto-pause and auto-resume debounce 20 s, finish interrupts. Disabling cues calls `player.stop()` and `VoiceCoachService.shared.cancelPlaybackForLocalCue()`.

Production call sites: `begin()` unchanged at 650/696/871; pause/auto-pause/resume use `announce(.paused / .autoPaused / .resumed, ...)`; finish uses `announce(.finished(distanceMeters: run.distanceMeters, movingSeconds: run.movingTimeSeconds), tone: tone)` and deletes the `finishDetail` string; the tick passes `guideState: workoutGuide`.

- [ ] **Step 1: Write the failing tests** in `CoachingToneCueTests.swift`. Use `let service = LocalRunCueService.shared`. In `setUp`, save and then set `service.library = CoachClipLibrary(manifest: nil, fileURL: { _ in nil })` (every clip falls back to its text) and `service.rotation = CueRotation(random: { _ in 0 })`; restore both in `tearDown`. Every test calls `service.begin(tone:)` first so the split schedule starts at 0.

```swift
func testCalmSplitSpeaksShortNumbersWithoutMovingTime() {
    var spoken: [String] = []
    service.speechHandler = { spoken.append($0) }
    service.begin(tone: .calm)
    spoken.removeAll()
    service.update(distance: 1_000, movingTime: 310, tone: .calm)
    XCTAssertEqual(spoken, ["\(CoachClipMoment.splitOpen.fallbackText) 1 K. 5:10."])
    XCTAssertFalse(spoken[0].contains("Moving time"))
    XCTAssertEqual(service.lastCue?.rate, CoachingTone.calm.speechRate)
    XCTAssertEqual(service.lastCue?.pitch, CoachingTone.calm.pitchMultiplier)
}

func testTechnicalSplitInsideABandedRepSaysOnTarget() {
    var guide = WorkoutGuide(steps: [GuideStep(kind: .work, target: .distance(meters: 2_000), paceBand: GuidePaceBand(center: 310))])!
    service.begin(tone: .technical)
    _ = guide.update(distance: 1_000, movingTime: 310)
    service.update(distance: 1_000, movingTime: 310, guideState: guide, tone: .technical)
    XCTAssertEqual(service.lastCue?.cue.segments, [.speech("Kilometer 1. Pace 5:10."), .clip(.onTarget)])
}

func testFinishSaysShortTotals() {
    service.announce(.finished(distanceMeters: 5_000, movingSeconds: 1_570), tone: .motivating)
    XCTAssertEqual(service.lastCue?.cue.segments, [.clip(.finished), .speech("5 K. 26:10.")])
}
```

In `RunLiveReviewFixesTests.swift`:

```swift
func testDisablingCuesMidCueStopsAndDropsTheQueue()
// inject a fake-backed CoachCuePlayer into the service; start a cue, queue a second; set settings.enabled = false;
// assert both backends got stop(), the queued cue never starts after firing the first segment's completion.
```

Update the existing assertions that expect the old long strings (`CoachingToneCueTests.swift:140-165`, `RunLiveReviewFixesTests.swift:190-205`, `RunMergeLeftoverTests.swift:45-60`, `WorkoutGuideTests.swift:225-240`) to the new transcripts. Delete `combinedText` tests; the composer tests in Task 4 cover that logic.

- [ ] **Step 2: Run to see them fail.** `-only-testing` the four test classes. Expected: compile failure on `announce(_ event:)`, `lastCue`, `guideState`.

- [ ] **Step 3: Implement.** Delete `combinedText`, `RunCueSchedule.duration` (if no caller remains), the Task 2 temporary text mapping, and the removed `CoachCueSpeech` members. `LocalRunCueService` owns one `CoachCuePlayer` built with live backends; tests swap it through an internal `init(player:)` or settable property.

- [ ] **Step 4: Run the full suite**

Run: `xcodebuild test -project "IOS RunSmart app.xcodeproj" -scheme "IOS RunSmart app" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: TEST SUCCEEDED. Baseline before this work: 825 passed, 0 failed, 1 skipped (`RunSharePosterRenderTests.testMapPostersRenderAtExportSize`). New total is 825 plus new tests minus deleted ones; report the exact numbers.

- [ ] **Step 5: Commit**

```bash
git add "IOS RunSmart app/Services/LocalRunCueService.swift" "IOS RunSmart app/Services/Production/RunSmartProductionServices.swift" "IOS RunSmart app/Services/CoachingTone.swift" "IOS RunSmart app/Features/Secondary/SecondaryFlowView.swift" "IOS RunSmart appTests"
git commit -m "feat(voice): run cues play coach clips with short numbers"
```

---

### Task 7: Produce, process, and bundle the clips

**Files:**
- Create: `scripts/coach-voice/prepare_clips.swift`
- Create: `IOS RunSmart app/Resources/CoachVoice/<slug>/coach-voice-<slug>.json` and `coach-<slug>-<tone>-<moment>-<variant>.m4a` files
- Modify: `IOS RunSmart app/Services/CoachVoice/CoachClipLibrary.swift` (`CoachVoice.activeSlug`, `bundled` loads `coach-voice-<slug>.json`)
- Test: `IOS RunSmart appTests/CoachVoiceBundleTests.swift`

**Interfaces:**
- Consumes: `lines.json` (Task 1, as approved), `CoachVoiceManifest` (Task 5).
- Produces: the bundled manifest and clips. `<slug>` is the lower-case voice name from Task 1, letters only.

- [ ] **Step 1: Confirm the ElevenLabs plan.** Ask the founder whether the plan allows commercial use of generated audio. Stop until confirmed. Then estimate the full set (every line in `lines.json` not already generated in Task 1) with `estimate_only: true`, show the founder, and generate only after a yes.

- [ ] **Step 2: Write the failing bundle test**

```swift
func testEveryMomentEachToneUsesHasABundledClip() throws {
    let library = CoachClipLibrary.bundled(Bundle(for: LocalRunCueService.self))
    let manifest = try XCTUnwrap(library.manifest)
    let needed: [CoachingTone: Set<CoachClipMoment>] = [
        .motivating: Set(CoachClipMoment.allCases).subtracting([.onTarget, .aBitFast, .aBitSlow, .logged]),
        .calm: Set(CoachClipMoment.allCases).subtracting([.onTarget, .aBitFast, .aBitSlow, .logged, .splitClose]),
        .technical: Set(CoachClipMoment.allCases).subtracting([.splitOpen, .splitClose])
    ]
    for (tone, moments) in needed {
        for moment in moments {
            let clips = manifest.clips.filter { $0.tone == tone.rawValue && $0.moment == moment.rawValue }
            XCTAssertFalse(clips.isEmpty, "\(tone) \(moment) has no clip")
            for clip in clips { XCTAssertNotNil(library.fileURL(clip.file), "\(clip.file) missing from the bundle") }
        }
    }
}

func testManifestTextMatchesTheApprovedLines() throws
// decode scripts/coach-voice/lines.json via #filePath, compare (tone, moment, variant, text) sets with the bundled manifest: equal.
```

(`fileURL` and `manifest` become internal read-only properties on `CoachClipLibrary` for this test.)

- [ ] **Step 3: Write `prepare_clips.swift`.** Input: raw clip dir, `lines.json`, output dir, voice id, voice name, model, target loudness. For each line: read audio with `AVAudioFile`, trim leading and trailing audio below -45 dBFS leaving 30 ms, normalize RMS to the target, write a temp `.caf`, then `afconvert -f m4af -d aac -b 64000 -c 1` to the final name. Target loudness: render "1 K. 5:10." with the Apple voice at Calm rate (`AVSpeechSynthesizer.write`), measure its RMS, and pass that number. Write the manifest with `gainDb: 0` for every clip.

Run: `swift scripts/coach-voice/prepare_clips.swift <raw> scripts/coach-voice/lines.json "IOS RunSmart app/Resources/CoachVoice/<slug>" <voiceId> <voiceName> eleven_v4 <targetRmsDb>`
Expected: one `.m4a` per line, manifest with the same count, total folder size under 3 MB.

- [ ] **Step 4: Run the bundle tests and the full suite.** Expected: PASS, same counts as Task 6 plus the two bundle tests.

- [ ] **Step 5: Commit**

```bash
git add scripts/coach-voice/prepare_clips.swift "IOS RunSmart app/Resources/CoachVoice" "IOS RunSmart app/Services/CoachVoice/CoachClipLibrary.swift" "IOS RunSmart appTests/CoachVoiceBundleTests.swift"
git commit -m "feat(voice): bundle the coach clips and manifest"
```

---

### Task 8: Listen, record, and open the PR

**Files:**
- Create: `docs/qa/2026-11-05-coach-voice-clips.md`
- Modify: `tasks/progress.md`

- [ ] **Step 1: Simulator recording.** Run the app on the iPhone 17 Pro simulator. For each tone record (`xcrun simctl io booted recordVideo`) a split, a pause and resume, a planned rep start, and the finish. Use a debug-only path or a unit-test host harness that calls `LocalRunCueService.shared` with the live player; do not ship a debug button. Send the recordings to the founder.

- [ ] **Step 2: Measure the joins.** In the recordings, the silence between a clip and the numbers must be 80 to 300 ms and no word may be clipped. If any join is over 300 ms, pre-render the next speech segment with `AVSpeechSynthesizer.write` while the clip plays and play it through `AVAudioPlayerNode`; re-measure. Write the measured gaps in the QA doc.

- [ ] **Step 3: Locked-phone and music check (simulator).** Start music in the simulator's Music app, lock the simulator, trigger a cue: music ducks, the cue plays, music returns. Note the result in the QA doc. Real-device listening stays with the founder in production, as the founder chose.

- [ ] **Step 4: Full suite, then push and open the PR.** Full `xcodebuild test` (Task 6 Step 4 command), report exact counts. Push the branch and open a non-draft PR to `main` with a plain-words body: what the runner hears per tone, the builder calls from the spec's "Calls made by the builder" list (including the Moving time toggle decision), the measured gaps, how to listen, what was not checked on a device, and that PR #176 (T7) must merge first. End the body with the Claude Code attribution line. Run the rule 17 pre-check: `@codex review` once, a read-only `code-reviewer` subagent, one `<!-- pr-precheck -->` comment.

- [ ] **Step 5: Update `tasks/progress.md`** (Status, Current Phase, Active Story, Last Completed Story, Next Recommended Story, Blockers, Last Validation, Last Updated 2026-11-05 or the actual date) and commit it in the same response as the last code commit.

```bash
git add docs/qa/2026-11-05-coach-voice-clips.md tasks/progress.md
git commit -m "docs(voice): coach clip QA notes and progress"
git push
```
