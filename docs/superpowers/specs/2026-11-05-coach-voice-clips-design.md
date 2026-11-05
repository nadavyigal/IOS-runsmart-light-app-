# Coach voice clips: human coach words, short numbers

Date: 2026-11-05
Status: draft for founder approval
Builds on: T7 coaching tones (PR #176, branch `claude/2026-11-05-voice-tones`)
Branch for this work: `claude/2026-11-05-coach-voice-clips`

## Why

The run cues sound robotic. Every cue today is the built-in Apple voice reading a long, fixed sentence:
"1 kilometer. Split pace 5 minutes 0 seconds per kilometer. Moving time 5 minutes 0 seconds."

The founder wants the coach to sound like a person, with less data per cue, said the way runners say it.
The founder chose pre-recorded ElevenLabs clips bundled in the app over live server speech, so cues work
offline and cost nothing per run.

## What the runner hears

Every cue is built from two kinds of sound played back to back:

1. **Coach words**: a short ElevenLabs clip, recorded once, bundled in the app. One per tone, 2 or 3
   recorded versions of each moment that rotate so the runner does not hear the same sentence every km.
2. **Numbers**: the Apple voice, short and runner style. "1 K. 5:10." Never "5 minutes 10 seconds".

The two must join smoothly: no audible gap, no overlap, and no voice switch in the middle of a sentence.
A number part is always its own short sentence.

### Split cue (every 1 km, 0.5 km, or 5 min, per the runner's setting)

| Tone | Coach clip | Numbers (Apple voice) | Coach clip |
|---|---|---|---|
| Motivating | "Nice work." | "1 K. 5:10." | "Keep it rolling." |
| Calm | "Smooth and easy." | "1 K. 5:10." | none |
| Technical | none | "Kilometer 1. Pace 5:10." | "On target." |

The founder approved these three: Motivating "Nice work." / "1 K. 5:10." / "Keep it rolling.", Calm
"Smooth and easy." / "1 K. 5:10.", Technical "Kilometer 1." / "Pace 5:10. On target." Each gets 1 or 2
more versions in the same spirit (builder writes them, founder hears them before they ship).

- Technical's km number is a number, so "Kilometer 1. Pace 5:10." is all Apple voice and "On target." is
  the coach clip after it.
- The Technical end clip is "On target.", "A bit fast." or "A bit slow." only when the run has a target
  pace (a planned workout step with a pace band). With no target, Technical ends with a neutral coach clip such as "Logged." (builder's call), so every
  Technical cue still has the coach's voice in it.
- Moving time is not in the split cue. The 5-minute cadence says the time instead of the km:
  "10 minutes. 5:10."
- Spoken numbers: "1 K", "1.5 K", "5:10" read as "five ten". Pace is the split pace of the last segment,
  as today.

### Run lifecycle

Start, restored, pause, auto-pause, resume and finish become coach clips per tone, using the T7 wording as
the base (for example Calm pause: "Run paused. Take the rest."). Finish adds a short numbers part:
"5 K. 26:10." (distance and moving time). Moving time is allowed here.

### Planned workout cues (run started from the plan)

Today these are Apple voice only, the same for every tone, and wordy:
"Rep 3 of 6. 400 metres at 4:30 to 4:40 per kilometre."

New:

- Step start: coach clip for the step kind (warm up, work, recovery, cool down, steady), then numbers:
  "Rep 3 of 6. 400 metres. 4:30 to 4:40." Reps and targets are numbers, so they stay in the Apple voice.
- Pace nudges "Ease off." and "Pick it up.": coach clips per tone.
- Workout complete: coach clip "Workout complete." followed by "Good job." or "Well done." (rotating).

## Goals

- The coach's words sound human and match the tone the runner picked.
- Numbers are short and said the way runners say them.
- Cues stay fully offline. Nothing new is sent off the phone.
- Planned workouts get the same voice and style as free runs.

## Non-goals

- Live text-to-speech from a server. The AI cue path (`/api/coach/voice-cue`, OpenAI) is untouched.
- A voice picker. Later the founder wants a second voice the runner can choose. This work must make that
  easy (clips organized by voice) but does not build the picker.
- Hebrew or any other language. Cues stay English.

## Anti-goals (a failure even if it works)

- A cue that sounds stitched: a gap, a clipped word, two voices at different loudness, or a voice switch
  mid-sentence.
- Any API key or ElevenLabs call in the app.
- A cue that goes silent when a clip is missing. Fall back to the Apple voice saying the clip's text.
- Two cues talking over each other. Today's rules hold: a split cue carries a workout step cue with it, and
  a pause cue waits for speech in progress.

## Constraints

- No new dependencies. Use AVFoundation (for example `AVAudioPlayer` or `AVQueuePlayer` for clips,
  `AVSpeechSynthesizer` for numbers) and sequence them in code.
- Keep the audio session behavior: `.playback`, `.spokenAudio`, duck other audio only while speaking.
- Works while the phone is locked (the app already has `audio` and `location` background modes).
- One voice for now, delivered three ways (Motivating, Calm, Technical). Builder picks the voice from the
  connected ElevenLabs workspace and sets delivery per tone (model `eleven_v4` style tags or voice
  settings). Founder approves by listening.
- Clips live in the app bundle in a folder per voice, then per tone. A manifest file lists every clip:
  id, tone, moment, variant, exact text, voice id, model, settings. The manifest makes clips easy to
  regenerate and to add a second voice later.
- Clip files: small compressed audio (AAC `.m4a`), trimmed of leading and trailing silence, loudness
  matched across all clips and to the Apple voice.
- The Apple voice for numbers keeps the T7 per-tone rate and pitch, so it sits close to the coach clip.
- T7's tone model (`CoachingTone`, `CoachingToneStore`, `CoachCueSpeech`) stays the source of truth for
  which tone is active.

## Decided by the founder

- Pre-recorded ElevenLabs clips bundled in the app, mixed with the Apple voice for numbers.
- Data said short ("1 K. 5:10."), everywhere: splits, workout steps, finish.
- Moving time removed from the split cue.
- The three split lines above, including the Motivating "Nice work." / numbers / "Keep it rolling." sandwich.
- Workout complete ends with "Good job." or "Well done."
- 2 or 3 versions per moment, rotating.
- Planned workout step cues use the same system.
- Builder picks the voice. A second, user-selectable voice comes later.

## Calls made by the builder (not approved by the founder; flag in the PR)

- Clip, then numbers, then optional clip. Never numbers inside a clip.
- Missing clip falls back to the Apple voice reading the same text.
- Rotation: never the same version twice in a row; order otherwise random.
- Technical is the only tone that compares to target pace, and only when a target exists.
- Technical compares only when the whole split lies inside one step that has a pace band, using the
  existing tolerance (`WorkoutGuide.paceTolerance`, 5 s). A split that mixes steps (for example a rep and
  a recovery jog) gets "Logged." instead, so a runner never hears "A bit slow" because the recovery
  pulled the average down.
- When a split cue and a workout step cue land together, the split's closing clip (Motivating
  "Keep it rolling.", Technical "On target." or "Logged.") is dropped and the step cue follows the
  numbers. The step instruction matters more at that moment, and the full cue stays short.
- The existing "Moving time" toggle in Audio cues: builder decides whether it now controls the finish
  numbers only or is removed, and explains in the PR.

## Left to the builder

- Writing the extra versions of each line in the spirit of the approved ones.
- Voice choice and per-tone delivery settings.
- How clips and speech are sequenced, and how the join is measured to be smooth.
- File naming, manifest format, where the sequencing code lives.
- Tests: cue composition (which parts, which order, which text) is unit tested per tone and moment.
  Audio smoothness is checked by listening, with recorded samples sent to the founder.

## How the founder checks it

1. Before any app code: samples of every coach clip, per tone, plus a few full cues stitched the way the
   app will play them. Founder approves the voice and the lines.
2. After the build: a simulator recording of a split, a pause, and a planned workout step per tone.
3. Production: the founder listens on a real run after release (founder chose to check on the phone in
   production).

## Open items that need the founder

- ElevenLabs plan: bundling generated audio in a commercial app needs a plan that allows commercial use.
  Founder confirms the plan before clips ship.
