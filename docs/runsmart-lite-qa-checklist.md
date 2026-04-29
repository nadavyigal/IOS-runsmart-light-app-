# RunSmart Lite QA Checklist

Devices: test on at least one small iPhone (SE or 16e) and one large iPhone (16 Pro Max).
Each step has an explicit expected result. Mark PASS or FAIL.

---

## 1. Cold Launch

| # | Step | Expected |
|---|---|---|
| 1.1 | Kill app from switcher, tap icon | Today tab visible within 1 s; no black screen |
| 1.2 | Observe Readiness card | Shows score (e.g. 82), label (e.g. High), progress ring |
| 1.3 | Observe Coach Recommends card | Shows workout title, distance, pace, elevation, mini route path |
| 1.4 | Observe compact stats row | 4 cards: Weekly Progress, Streak, Recovery, HRV Status |
| 1.5 | Observe tab bar | 4 tabs visible; Today is highlighted in lime |

---

## 2. Tab Navigation

| # | Step | Expected |
|---|---|---|
| 2.1 | Tap Plan | Plan tab renders; week strip and month overview visible |
| 2.2 | Tap Run | Run tab renders; 4 metric tiles (Distance, Pace, Time, Heart Rate) visible |
| 2.3 | Tap Profile | Profile tab renders; runner name, stats bar, Coach Spark card visible |
| 2.4 | Tap Today | Returns to Today; state unchanged from step 1 |
| 2.5 | Repeat on small iPhone | No tab label truncation; run button is accessible |

---

## 3. Coach Sheet — Today

| # | Step | Expected |
|---|---|---|
| 3.1 | Tap **Talk to Coach** | Sheet opens at full-screen height with drag indicator |
| 3.2 | Type a message, tap Send | Message appears in thread with "Just now" timestamp; input field clears |
| 3.3 | Tap Send with empty input | Nothing happens; no crash |
| 3.4 | Swipe sheet down | Sheet dismisses; returns to Today tab |

---

## 4. Coach Sheet — Other Tabs

| # | Step | Expected |
|---|---|---|
| 4.1 | Plan → tap any coach entry point | Coach sheet opens |
| 4.2 | Run → tap **Tap to talk** | Coach sheet opens |
| 4.3 | Profile → tap **Chat with Coach** | Coach sheet opens |
| 4.4 | All sheets | Dismiss on swipe-down without crash |

---

## 5. Secondary Sheets — Today

| # | Step | Expected |
|---|---|---|
| 5.1 | Tap **Start Workout** | Switches to Run tab (not a sheet) |
| 5.2 | Tap Coach Insight card | Workout Detail sheet opens; title and session purpose visible |
| 5.3 | Inside Workout Detail: tap **Reschedule Workout** | Reschedule sheet opens with 3 day options |
| 5.4 | Inside Workout Detail: tap **Choose Route** | Route Selector sheet opens with map and route list |
| 5.5 | Inside Workout Detail: tap **Adjust Plan** | Plan Adjustment sheet opens with assessment bars |
| 5.6 | Inside Plan Adjustment: tap **Add Missing Activity** | Add Activity sheet opens |

---

## 6. Secondary Sheets — Plan Tab

| # | Step | Expected |
|---|---|---|
| 6.1 | Tap the plan adjustment entry | Plan Adjustment sheet opens |
| 6.2 | Sheet shows 3 readiness bars and proposed changes | All bars render with lime fill |

---

## 7. Secondary Sheets — Run Tab

| # | Step | Expected |
|---|---|---|
| 7.1 | Tap **Audio** | Audio Cues sheet opens; cue timing preferences and live preview visible |
| 7.2 | Tap **Lap** | Lap Marker sheet opens; Lap 5 metrics and Mark Lap button visible |
| 7.3 | Tap **Finish** | Post-Run Summary sheet opens; splits list and Save Run button visible |
| 7.4 | Tap **Pause** | No crash; button has no live action at this stage (verify no hang) |

---

## 8. Secondary Sheets — Profile Tab

| # | Step | Expected |
|---|---|---|
| 8.1 | Tap **Voice Coaching** | Voice Coaching sheet opens |
| 8.2 | Tap **Coaching Tone** | Coaching Tone sheet opens; 3 personality tiles visible |
| 8.3 | Tap **Goal Focus** | Goal Focus sheet opens |
| 8.4 | Tap **Check-in Cadence** | Reminders & Preferences sheet opens |
| 8.5 | Tap **Garmin Connect** | Connected Service Detail opens; permission rows visible |
| 8.6 | Tap **Strava** | Connected Service Detail opens |
| 8.7 | All sheets | Dismiss on swipe-down without crash |

---

## 9. Visual and Accessibility

| # | Step | Expected |
|---|---|---|
| 9.1 | Set Dynamic Type to Accessibility Large in Settings | Core text remains readable; no clipping of critical labels |
| 9.2 | Rotate iPhone to landscape on Today | UI remains usable; no overlap or clip of buttons (known risk: landscape not optimised) |
| 9.3 | Verify lime text contrast on dark background | Neon labels and buttons pass a visual readability check |
| 9.4 | Check tab bar on iPhone SE | All 4 tabs fit; run button circle does not overflow |
| 9.5 | Scroll Today to bottom | Content is not hidden behind the custom tab bar |

---

## 10. Performance

| # | Step | Expected |
|---|---|---|
| 10.1 | Cold launch on oldest supported device | Today tab fully rendered within 1.5 s |
| 10.2 | Rapid tab switching (cycle 5×) | No dropped frames visible; no crash |
| 10.3 | Open and close coach sheet 3× quickly | No memory warning or UI corruption |

---

## Known Gaps (not QA failures at this stage)

- Mock data only — all service calls return preview data. Live API failures are not testable yet.
- Location permission denial path — no Core Location integration yet.
- Pause/resume/finish state machine — Pause button has no live action.
- Interruption handling (incoming call, lock screen) — deferred to live-run integration.
- Save Run / Mark Lap / Save Activity buttons — wired to empty actions; verify no crash on tap.
