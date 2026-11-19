# Live Activity: physical iPhone checklist

Use a real iPhone with a Dynamic Island (iPhone 14 Pro or newer), a Debug or TestFlight build, Live Activities on in iOS Settings → RunSmart. Run outside (real GPS). Tick each line, and note the build number.

Simulators cannot prove these: Lock Screen buttons, background GPS, force-quit, and Low Power Mode all need a real phone.

## PR 2: fixes (no visual change)

- [ ] **Lock Screen Pause.** Start a run, lock the phone, tap Pause on the Lock Screen. The run pauses (unlock: the app shows Paused). The Live Activity says Paused, the clock stops.
- [ ] **Lock Screen Resume.** Tap Resume. The clock moves again from where it stopped.
- [ ] **Island Pause.** Long-press the Dynamic Island, tap Pause. Same result as above.
- [ ] **Finish from the Lock Screen.** Tap Finish. The phone asks to unlock, RunSmart opens on the Run tab with the finish sheet. Nothing is saved until you confirm.
- [ ] **After Finish.** Confirm. The Lock Screen card shows Finished with distance, time and average pace, no buttons, and stays about 30 minutes.
- [ ] **Discard.** Start a run, then discard it. The Live Activity disappears at once.
- [ ] **Tab switch mid-run.** During a run, open the app and get to another tab (for example tap a push notification or a link that opens Today). The Live Activity stays and keeps updating. Go back to Run: still one activity.
- [ ] **Force-quit and resume.** During a run, swipe the app away. Reopen it, choose Resume on the recovery prompt. Exactly one Live Activity, showing Paused, then Recording after Resume.
- [ ] **Force-quit and discard.** Same, but choose Discard. The old Live Activity disappears.
- [ ] **Stale.** During a run, force-quit and do not reopen. Within about 2 minutes the card dims and says "Open RunSmart to update".
- [ ] **Locked 20 minutes.** Run 20 minutes with the phone locked. Clock ticks every second, distance moves every 15 to 60 seconds.
- [ ] **Weak GPS.** Use "Start anyway" before a GPS fix (or start indoors). The status says Finding GPS, then Recording once GPS is good.
- [ ] **Auto-pause.** Stop moving with auto-pause on. Status says Auto-paused, clock stops.
- [ ] **Low Power Mode.** Turn it on mid-run. Clock still ticks; distance still updates.
- [ ] **Live Activities off.** iOS Settings → RunSmart → Live Activities off. Start a run: no activity, the run records normally.
- [ ] **Regression.** Lock Screen still shows title, status, Distance / Moving time / Pace, and Pause + Finish, as before.

## PR 1: App Group (do this before any device build)

- [ ] Apple Developer portal: App Group `group.com.runsmart.lite` exists and is enabled for `com.runsmart.lite` and `com.runsmart.lite.runliveactivity`. Xcode signs both targets without errors.

## PR 3: hybrid layout

- [ ] **Planned run with a target pace** (from the plan or your coach): the island and Lock Screen show pace vs target ("12 s faster than target") and a ring/bar toward the planned distance.
- [ ] **Planned run with a target but no distance** (time-based): pace vs target, no ring, no empty ring.
- [ ] **Free run:** time and distance large, pace small.
- [ ] **Km split:** a "Km 3 · 5:18 /km" chip pops once, no sound or vibration, gone within about a minute.
- [ ] **Island fit:** compact island does not touch the status-bar clock or battery; expanded labels are not clipped at the corners.
- [ ] **Two Live Activities** (start a timer too): the minimal view is readable.
- [ ] **Tap the activity:** opens RunSmart on the Run tab. After Finish, tapping the card opens the Run tab.

## PR 4: weekly widget

- [ ] Add the "Weekly km" small widget. With a plan: ring and "21.4 of 30 km" style. Without a plan: km only, no ring.
- [ ] Start a run: the widget shows "Run in progress" within a few seconds. Finish: back to the week, km updated.
- [ ] Monday morning: the week resets to 0.

## PR 5: in-app switch

- [ ] Run tab → Audio → Audio Cues → Run preferences → "Live Activity on Lock Screen" off: starting a run shows no activity. Turning it off mid-run removes it within a second or two.
- [ ] With Live Activities off in iOS Settings, the in-app switch is greyed out and says why.
