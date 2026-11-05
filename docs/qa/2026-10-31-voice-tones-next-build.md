# Next build checklist: coach tones reach the voice

Date: 2026-11-01
Branch: `codex/2026-10-31-voice-tones`
Worktree: `/Users/nadavyigal/Developer/runsmart-ios-worktrees/2026-10-31-voice-tones`

This session did not commit, push, archive, or upload. Unit tests do not prove the cues sound natural.

## Source commit

- HEAD is still `c8de2db` (`Record RunSmart build 40 ASC delivery and remaining device gate`).
- The branch tracks `origin/codex/release-1-2-2`. The 1.2.2 source is not in `main`. PR #174 is a draft.
- `5c96738` (saved-report benchmark fix) is an ancestor of HEAD. `git merge-base --is-ancestor 5c96738 HEAD` exited 0. That does not mean a future archive contains this tone work. Record the archive's source commit and run the ancestor check against that commit.
- The tone work is uncommitted. `git status --short` shows the iOS edits plus `docs/qa/2026-10-31-voice-web-change.md` and this file. `.track-status.md` is gitignored.

Founder action before any archive: approve this working tree, then commit it on this branch. Do not archive `c8de2db` and call it the tone build.

## Release settings

Read from the app target Release configuration in `IOS RunSmart app.xcodeproj/project.pbxproj` (`33F1D5CB2FA0B36D006C1A3C`):

- `MARKETING_VERSION` = 1.2.2
- `CURRENT_PROJECT_VERSION` = 40
- Bundle id `com.runsmart.lite`
- `UIBackgroundModes` = `location audio`
- `CODE_SIGN_STYLE` = Automatic
- Development team `8VC4R5M425`
- Deployment target on the project Release config is 17.0

Build 40 is the build already selected for 1.2.2. Do not upload another archive as build 40. At release time, pick an unused build number greater than 40 and set the marketing version from live App Store Connect. This session did not change either number.

No OpenAI key, ElevenLabs key, or `VOICE_COACH_ENABLED` flag was found in the Swift, plist, entitlements, or xcconfig sources searched by name. Keys stay on the server. Before any upload, run `python3 scripts/verify-release-backend.py <built-app-path>` on the actual archived app. A nonempty key is not enough. This session did not archive, so that script was not run.

`VOICE_COACH_ENABLED` in Vercel production is still unverified. Do not turn it on from this checklist. Extra AI cues stay off on device unless the runner switches them on, and the server still returns 503 when the flag is not the string `true`.

## Packaged assets

This change adds no audio file. Offline cues use `AVSpeechSynthesizer` with the `en-US` system voice. Rate and pitch change with the tone. AI cues, when enabled, still play AAC returned by the server. The 1.2.2 (40) IPA had no `.mp3`, `.m4a`, `.aac`, `.wav`, `.caf`, or `.aiff` cue assets. The next archive should be checked the same way. An empty audio folder is the expected result.

## What the next binary will do

- Onboarding, the goal editor, and Coaching Tone offer Motivating, Calm, and Technical.
- Coaching Tone saves the label on the phone and, when signed in, upserts `profiles.coaching_style`: Motivating `encouraging`, Calm `supportive`, Technical `analytical`.
- After reload, the profile tile shows the label. Old `challenging` still shows Strict and speaks as Motivating. The word Direct still shows Direct until it is stored. A stored `supportive` row shows Calm, because old Direct was saved as `supportive`.
- Offline cues keep the distance, pace, and time sentences. Motivating adds "Push on." Calm adds "Settle in." Technical adds "Split check." Start, pause, resume, and finish stay the old sentences for Motivating and change for Calm and Technical.
- The system voice is slower and lower for Calm, faster for Technical, and the default rate with a slightly higher pitch for Motivating.
- The AI cue request body includes `coachingStyle`. The live server ignores that field until the web diff in `docs/qa/2026-10-31-voice-web-change.md` is applied and deployed.
- Spoken cues stay in English. The Audio cues screen says so.
- The Voice Coaching screen no longer shows the fake On / Light / Focused rows.

## Simulator evidence

2026-11-01, `xcodebuild test` on the iPhone 17 simulator, iOS 26.5 (the result bundle reports architecture x86_64). Result: passed. 825 passed, 0 failed, 1 skipped, 826 total.

Skipped by name: `RunSharePosterRenderTests.testMapPostersRenderAtExportSize`. It skips unless `TEST_RUNNER_RUN_SHARE_RENDER_DIR` is set, because the map render wants network. A skipped test is not evidence for that poster.

This does not prove the cues sound natural.

## Not done

- No commit, no pull request, no TestFlight upload, no App Store review.
- No physical device run. No lock test. No headphone test. No listening rating.
- The web route was not edited and its tests were not run.
- `VOICE_COACH_ENABLED`, `OPENAI_VOICE_KEY`, and the PostHog server key were not confirmed in Vercel.
- No phone-call interruption handler was added on the AI cue path.
- Hebrew cues were not translated. The screen says the cues are in English.
- ElevenLabs was not added. The proposed OpenAI voices were not turned on.

## Device checks the founder must do

Use a physical iPhone, the archive's build number, headphones, and music in another app. Write down the device, OS, and build. A simulator pass is not this list.

1. Coaching Tone: pick Calm, leave the screen, force-quit, reopen. The tile says Calm. Repeat for Technical and Motivating.
2. Offline cues, screen on: start, 1 km split, pause, resume, finish. The numbers match the screen. Calm and Technical do not use the Motivating sentences.
3. Offline cues, phone locked in a pocket for 2 km. Every split is spoken.
4. Music ducks during each cue and comes back after.
5. Bluetooth headphones and AirPods. The cue plays there.
6. Airplane mode with GPS on. Offline cues continue. No error dialog.
7. Phone call during a cue. Note whether the cue stops and whether music and cues return after. The AI path still has no interruption handler. This check is evidence, not a fix.
8. Hebrew as the device language. Note that the cues are still English.
9. One run each on Motivating, Calm, and Technical. Rate whether the wording and the voice are distinct, 1 to 5. Unit tests do not prove this.
10. Extra AI coach cues, only after `VOICE_COACH_ENABLED` is confirmed on and the web diff is deployed: signed in, 15 minutes, about three cues. Note the gap from the 5 minute mark to speech. Repeat once with the phone locked. If the flag is off, skip this and say it was skipped.
