# WP-38 S14a–d — Stretch bundle QA evidence (2026-07-09)

- **Environment:** iPhone 17 Simulator, iOS 26.3, DEBUG + `-RUNSMART_DEMO_MODE -INITIAL_TAB Run -AUTO_START_RUN`
- **Build:** Debug **SUCCEEDED** on branch `claude/wp38-runsmart-s14-stretch-bundle`

## Acceptance

| Story | Check | Result | Evidence |
|---|---|---|---|
| **S14a** | Screen stays awake during recording; normal timeout after finish/discard | **PASS (code)** | `RunScreenAwakePolicy` toggles `isIdleTimerDisabled` on `.recording`/`.paused` only; cleared on finish/discard/tab disappear |
| **S14b** | Lock-screen Live Activity with pause/finish controls | **PASS (build + wiring)** | `RunSmartRunLiveActivityExtension` embedded; `RunLiveActivityController.sync` updates distance/time/pace; intents post pause/finish notifications to `RunTabView` |
| **S14c** | Haptics on start/pause/resume/finish/discard without double-fire | **PASS (code)** | `start` medium; pause/resume light; finish light on tap + medium on confirm; discard light on open + medium on confirm |
| **S14d** | VoiceOver labels + Dynamic Type without clipping | **PASS (sim)** | Accessibility labels on PreRun/Live/Post-run controls; `02-live-accessibility-text.png` at extra-extra-extra-large content size |

## Notes

- Live Activity lock-screen button QA requires enabling Live Activities for RunSmart in Simulator Settings; extension is embedded and `NSSupportsLiveActivities` is set on app + extension.
- Physical-device lock-screen capture still recommended for S14b before TestFlight.
