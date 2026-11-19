# RunSmart Live Activity, Dynamic Island and Widget: Plan

Date: 2026-11-19. Status: plan only, no app code changed. Waiting on the founder's direction pick.
Mockup: `design-mockups/live-activity/index.html` (screenshots in `design-mockups/live-activity/screenshots/`).
Base: `origin/main` at `b901258`.

## 0. Apple rules that constrain the design

1. Sizes: compact (leading + trailing around the camera), minimal (one detached circle when 2+ activities run), expanded (touch and hold, also shown briefly on alert updates), Lock Screen. All four are required.
2. Compact and minimal must fit a 28 pt circle when width is limited (landscape, two activities). If trailing does not make sense, leave it empty.
3. Island backgrounds cannot be colored. Lock Screen can be tinted.
4. Active for up to 8 hours, then the system ends it. It stays on the Lock Screen up to 4 more hours (12 hours total).
5. Static + dynamic data, including each update, must stay under 4 KB.
6. Animation: system and custom transitions only, 2 s max. SwiftUI animation modifiers are ignored. No animation on Always-On low luminance. No looping.
7. A running clock should use `Text(timerInterval:)` or `Text(date, style: .timer)`, so the clock ticks without sending updates.
8. Buttons and toggles must use App Intents. A `LiveActivityIntent` runs in the app's process, so the type must be compiled into the app target.
9. Alerts only for essential updates. Do not also send a push notification for the same event.
10. Keep it glanceable: no ads, no sensitive data. Tapping compact opens the app to the related screen.

Sources: Live Activities HIG, ActivityKit "Displaying live data with Live Activities", WidgetKit "Adding interactivity to widgets and Live Activities" (read 2026-11-19 from developer.apple.com).

## 1. Audit: what exists today

| Piece | Where | What it does |
|---|---|---|
| Attributes + state | `RunSmartShared/RunRecordingLiveActivityAttributes.swift:5-14` | `workoutTitle`; state is 3 preformatted strings (`distanceLabel`, `movingTimeLabel`, `paceLabel`) + `isPaused` |
| UI | `RunSmartRunLiveActivityExtension/RunRecordingLiveActivityWidget.swift:6-91` | Expanded: distance left, time right, Pause/Finish bottom. Compact: distance left, run or pause icon right. Minimal: icon. Lock: title, Recording/Paused, 3 metrics, 2 buttons |
| Intents | `RunSmartRunLiveActivityExtension/RunRecordingLiveActivityIntents.swift:4-23` | `PauseRunLiveActivityIntent`, `FinishRunLiveActivityIntent` (opens app). Both post a `NotificationCenter` notification |
| Controller | `IOS RunSmart app/Services/Run/RunLiveActivityController.swift:6-71` | Static `activity`. `sync()` requests or updates. `end()` ends with `.immediate` |
| Call sites | `IOS RunSmart app/Features/Run/RunTabView.swift:105-109, 147-161, 398-416` | Started and updated from `RunTabView` only |
| Plist | `RunSmartInfo.plist:46`, `RunSmartRunLiveActivityExtension-Info.plist:10` | `NSSupportsLiveActivities = true` in both |
| Extension target | bundle `com.runsmart.lite.runliveactivity`, iOS 17.0 | Synced folders: extension folder + `RunSmartShared` |

Not present: no home-screen widget, no App Group, no extension entitlements file (`RunSmart.entitlements` has Sign in with Apple, Associated Domains, HealthKit only), no `widgetURL` / deep link into the run, no `staleDate`, no reuse of `Activity.activities` after relaunch, no user setting.

The brief's audit is out of date on two points (verified on `main` today):
- Crash recovery already shipped: `RunSessionCheckpoint`, `RunRecorder.resumeRecoveredRun()` (`IOS RunSmart app/Services/Production/RunSmartProductionServices.swift:883`).
- Auto-pause already shipped: `RunRecorder.isAutoPaused` (`RunSmartProductionServices.swift:515, 742`). Km splits too (`:1236-1241`). Average pace exists (`averagePaceLabel`, `:598`). None of these reach the Live Activity.

### Findings, ranked

1. **Pause and Finish buttons likely do nothing (high, not device-verified).** `RunRecordingLiveActivityIntents.swift` sits only in the extension folder, so the intent types are compiled into the extension, not the app. Apple runs `LiveActivityIntent` in the app's process. Either the system cannot find the type in the app, or `perform()` runs in the extension and its `NotificationCenter.post` never reaches the app. Fix: move the intents into `RunSmartShared/` (compiled into both targets) and call the recorder directly instead of a notification. Verify on device before anything else.
2. **Leaving the Run tab kills the Live Activity while the run keeps recording.** `RunTabView.swift:105-109` calls `RunLiveActivityController.end()` in `onDisappear`. The recorder lives in the app shell (`RunSmartLiteAppShell.swift:161`), so it survives a tab change; the Live Activity does not. The tab bar is hidden during a run, but there are 17 programmatic tab switches in the app. Worse, the Pause/Finish receivers (`RunTabView.swift:147-152`) and every update (`:153-161`) live on that view, so off-tab there are no updates and no button handling.
3. **Duplicate or orphan activity after a kill.** The controller only knows the activity it created in this process (`RunLiveActivityController.swift:7`). After a crash or kill, the old activity stays on the Lock Screen (up to 8 h). On relaunch, `resumeRecoveredRun()` sets phase `.paused`, `sync()` finds `activity == nil` and requests a second one. Discarding the recovered run leaves the orphan showing stale numbers.
4. **One update per second.** `movingLabel` changes every second (`RunTabView.swift:156`), so the app sends an ActivityKit update every second, each in an untracked `Task`. Costs battery, and depends on SwiftUI `onChange` firing while the phone is locked. A system timer view removes this entirely.
5. **No stale handling.** `staleDate: nil` everywhere. If the process dies the Lock Screen shows a frozen clock with no hint.
6. **Finish ends with `.immediate`.** The runner loses the summary the moment they tap Finish. Strava and NRC both leave a short "run complete" card.
7. **Compact island is weak.** Leading shows distance, trailing is a static icon. Apple's own example (Timer) shows the live value in minimal. The clock is the one thing that always changes.
8. **No GPS-acquiring state.** The activity starts only at `.recording`, so the island is empty while the runner waits for a fix.

Kept as-is (on par with Strava per the 22 Oct audit): Lock Screen layout with title, state, three metrics and two buttons; Pause/Resume + Finish set; Finish opens the app to confirm.

## 2. Direction pick

**Recommended: A, Run-first, plus two borrowed pieces.**

- A for the island and Lock Screen. During a run the clock and the distance are what change, and A uses only data the recorder already has. It is also the smallest step from today's layout, so the "don't break it" risk is lowest.
- Borrow B's ring for the minimal view when the run has a planned distance. Free runs fall back to distance.
- Borrow C's widget for the home screen: next planned run, week progress dots and streak. When no run is active the clock has nothing to say; the plan does.

Others in one line:
- **B, Pace and goal:** strong for structured workouts, but half the runs are free runs with no target, and `WorkoutSummary.distance` is a string, so the core of the design needs new parsing and a fallback.
- **C, Plan and streak:** good for a plan-led runner, but it needs workout steps, week data and plan week number in the activity state, which is the largest new surface for the least glance value mid-run.

## 3. Architecture

### 3.1 App Group first (PR 1)
- ID: `group.com.runsmart.lite`. Add to the app and a new `RunSmartRunLiveActivityExtension.entitlements`.
- Shared store: `RunSmartShared/RunSmartWidgetSnapshot.swift`, a small `Codable` written to the App Group `UserDefaults(suiteName:)` (or a JSON file in the container).
- What it shares (widget only, the Live Activity gets its data through ActivityKit):
  - next planned workout: date, kind, title, distance km, target pace (optional)
  - week: km done, km goal, done days (7 bools)
  - streak count (from the same source as Today's `streak` string)
  - last run: date, distance, moving seconds
  - `updatedAt`, `schemaVersion`
- Written by the app on: plan load, run saved, plan changed, app background. Then `WidgetCenter.shared.reloadTimelines(ofKind:)`.
- Setup gotcha from the source thread: the App Group must exist in the developer portal for both bundle IDs and in both provisioning profiles before any widget code. Do it first and ship it empty.

### 3.2 Activity attributes and state (PR 2)
Move formatting into the extension so the state carries numbers, not strings. Keep it well under 4 KB.

```swift
struct RunRecordingLiveActivityAttributes: ActivityAttributes {
    var schemaVersion: Int            // bump when ContentState changes
    var runID: UUID                   // ties the activity to the recorder's run
    var workoutTitle: String
    var goalDistanceMeters: Double?   // planned distance, nil for free runs (minimal ring)

    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case acquiring, running, paused, autoPaused, finished }
        var phase: Phase
        var timerStart: Date?         // startedAt + accumulated pause; drives Text(timerInterval:)
        var frozenMovingSeconds: Int  // shown when paused or finished
        var distanceMeters: Double
        var currentPaceSecPerKm: Int?
        var averagePaceSecPerKm: Int?
        var lastSplitKm: Int?         // for the split pop
        var lastSplitPaceSecPerKm: Int?
        var gpsAccuracyMeters: Int?   // acquiring only
    }
}
```

- A pure mapper `RunLiveActivityState.make(from: RunRecorderSnapshot) -> ContentState` in `RunSmartShared`, unit tested.
- Schema change: on launch, end any activity whose `schemaVersion` differs, so an app update never renders a half-decoded state.
- Coach cue (placeholder in the mockup): not in the state until the voice coach exposes a "cue playing" signal. No new field now.

### 3.3 Widget extension target
Reuse `RunSmartRunLiveActivityExtension`. Add the home widget to `RunSmartRunLiveActivityBundle.swift:5-9`. No new target, so no new signing surface beyond the App Group entitlement.

### 3.4 App Intents
- Move `RunRecordingLiveActivityIntents.swift` into `RunSmartShared/` so the types exist in the app binary.
- `PauseResumeRunIntent: LiveActivityIntent`: calls the recorder's `pause()` / `resume()` through a shared `RunControl` hook the app registers at launch (`@MainActor`). Remove the `NotificationCenter` hop.
- `FinishRunIntent: LiveActivityIntent`, `openAppWhenRun = true`: pauses and opens the app to the existing finish confirmation. The run is never saved from the Lock Screen without the confirmation sheet.
- Widget "Start run" is a deep link, not an intent: starting GPS recording needs the app in the foreground for the permission and acquiring flow.

### 3.5 Deep links
- Activity `widgetURL`: `runsmart://run/live` while running, `runsmart://run/debrief/<runID>` after finish.
- Widget: `runsmart://run/start` (pre-run), `runsmart://run/live` (during a run), `runsmart://today` (default).
- Route in `RunSmartLiteAppShell.openIncomingURL` (`RunSmartLiteAppShell.swift:617`), before the coach-invite branch, which currently consumes `runsmart://` URLs it does not know.

## 4. Lifecycle in `RunRecorder`

Move ownership out of `RunTabView` into a `RunLiveActivityCoordinator` owned by the app shell next to the recorder (`RunSmartLiteAppShell.swift:161`), subscribing to the recorder's published state. This fixes finding 2 at the root.

| Event | Action |
|---|---|
| App launch | Read `Activity<…>.activities`. If one matches the checkpoint's run, adopt it. If there is no checkpoint, or the schema differs, end it with a stale final state. |
| `acquiringLocation` | Request the activity in phase `.acquiring` with GPS accuracy. If the runner cancels, end `.immediate`. |
| `start()` → `.recording` | Update to `.running`, set `timerStart`. |
| Running | Update on: phase change, every 50 m of distance, or 15 s max, whichever is first. The clock never needs an update. Coalesce: never more than one update in flight. |
| Km split | Update with `lastSplitKm` / pace: one pop transition. Alert only if the runner turns split alerts on (default off: the voice coach already announces splits). |
| `pause()` / auto-pause | Update to `.paused` / `.autoPaused`, freeze `frozenMovingSeconds`, `timerStart = nil`. |
| `resume()` | Update to `.running` with a new `timerStart`. |
| `finish()` saved | End with `.finished` state, `dismissalPolicy: .after(now + 30 min)`, `widgetURL` to the debrief. |
| `discard()` | End `.immediate`. |
| `resumeRecoveredRun()` | Adopt the old activity if it exists, else request one in `.paused`. Never two. |
| `discardRecoveredRun()` / `saveRecoveredRun()` | End the adopted activity. |
| Every update | `staleDate = now + 2 min`. The view dims and shows "Open RunSmart" when `context.isStale`. |

`onDisappear` at `RunTabView.swift:105-109`: remove the `RunLiveActivityController.end()` line. The coordinator owns the end. Keep the tab-bar and screen-awake lines.

Battery: today about 3,600 updates per hour. Planned: about 60 to 240 per hour (distance and phase only), zero for the clock.

## 5. Home-screen widget

- Sizes: small first; medium later if asked.
- Content (from Direction C): header "Next run · Today" or weekday, workout title, distance and target pace, week dots, streak count. During a run: "Running now" + distance, with a `Text(timerInterval:)` clock. After today's run: "Done today" + next workout.
- No plan: "Start a run" with last run summary. No data yet: a single "Open RunSmart" state, no fake numbers.
- Timeline: one entry now, one at local midnight (rolls "Today" to the next day), plus a reload when the app writes the snapshot. No network calls from the widget: it reads only the App Group snapshot.
- Taps: deep links in §3.5. No interactive buttons in v1.

## 6. User setting

- Profile/Settings → Run recording → "Live Activity on Lock Screen" toggle, default on. Stored in the App Group defaults so the coordinator and the widget read the same value.
- Off: the coordinator never requests an activity and ends any running one.
- If the system setting is off (`ActivityAuthorizationInfo().areActivitiesEnabled == false`), show the toggle disabled with "Turned off in iOS Settings".

## 7. Test plan

Unit (`IOS RunSmart appTests`):
- `RunLiveActivityState.make` for each phase: acquiring, running, paused, auto-paused, split, finished; free run vs planned run; pace nil below 20 m.
- Coordinator with a fake ActivityKit adapter: one activity per run; recovery adopts instead of duplicating; discard ends; schema mismatch ends; throttle sends at most one update per 15 s with no distance change.
- Intent → `RunControl` routes to pause, resume and finish confirmation.
- Snapshot encoder: size under 4 KB, round-trips.

Xcode previews: every size (minimal, compact, expanded, Lock Screen) × every phase, plus the widget's no-plan, planned, running and done states. Use `#Preview(as: .content, using:)` with fixed state.

Real device checklist:
- [ ] Pause and Resume from the Lock Screen while locked, app in background
- [ ] Finish from the island opens the confirmation sheet
- [ ] Background GPS: 20 min locked run, clock and distance keep moving
- [ ] Switch tabs mid-run (via a deep link or notification): activity survives
- [ ] Kill the app mid-run, relaunch, choose Resume: one activity, not two
- [ ] Kill, relaunch, choose Discard: activity gone
- [ ] Low Power Mode: activity still updates, clock still ticks
- [ ] Two activities (start a timer): minimal view readable, fits the circle
- [ ] Landscape and iPhone Duo: compact uses the reduced width
- [ ] Compact island does not touch the status-bar clock or battery
- [ ] Always-On: no animation, still readable
- [ ] Setting off: no activity starts
- [ ] Regression: today's Lock Screen layout and controls still present

## 8. Delivery: draft PRs on new branches, never merged by an agent

1. **App Group and shared snapshot.** Entitlements for app + extension, `RunSmartWidgetSnapshot`, writer in the app. No UI. Includes the portal / profile checklist for the founder.
2. **Live Activity fixes (no visual change).** Intents into `RunSmartShared` + `RunControl`; coordinator in the app shell; remove `onDisappear` end; adopt on relaunch; throttle; `staleDate`. Tier 1 review.
3. **Direction A visuals.** New `ContentState`, timer text, acquiring and finished states, split pop, minimal ring for planned runs, deep links.
4. **Home-screen widget.** Small widget from the snapshot, timeline, deep links.
5. **Setting and polish.** Toggle, disabled state, device checklist pass, screenshots.

PR 2 alone fixes the worst bugs (dead buttons, lost activity off-tab, duplicates), so it can ship before any redesign.

## 9. Open questions for the founder

1. Direction: A with B's ring and C's widget, as recommended? Or a different mix?
2. Can I confirm finding 1 on your phone first: does tapping Pause on the Lock Screen pause the run today?
3. Should the Live Activity start at GPS acquiring (new), or stay as today and start at Start?
4. After Finish: keep the summary card for 30 minutes, or a different time?
5. Split alerts: off by default (the voice coach already speaks splits), agreed?
6. Widget scope for v1: small only, or small and medium?
