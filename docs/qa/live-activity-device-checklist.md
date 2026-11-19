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

## Later PRs (add as they land)

- PR 3: hybrid B/A layout (target run vs free run), split pop, island does not touch the status-bar clock or battery.
- PR 4: small widget shows weekly km ring and "Run in progress".
- PR 5: in-app on/off switch.
