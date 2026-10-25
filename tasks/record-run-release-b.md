# Record-a-run Release B — 22 October 2026

Founder authorized S4–S8 while Claude completes S3. Isolated branch based on S2 `15e9edf`; integrate S3 before final review. No Release C or store submission.

## S4: Offline cues
As a runner including guests, I want local milestones so cues work offline.
Acceptance: lifecycle announcements; 1 km default / 0.5 km / 5 moving-minute cadence; selectable distance/split pace/time; persisted settings; AI extra optional/authenticated; duck only during speech.
Tests: boundaries, repeats, recovery, preferences, disabled state. Airplane-mode locked-phone audio needs physical smoke.

## S5: Auto-pause
As a runner, I want stops excluded and movement to resume automatically.
Acceptance: speed below 0.5 m/s for 8 seconds; default on; resume only automatic pauses; manual pauses stay paused; banner/haptic/voice; frequent paused GPS.
Tests: 30-second stop, bad fixes, manual override, preference off, no pause-distance bridge.

## S6: Finish safely
As a runner, I want a deliberate gesture and one decision sheet.
Acceptance: tap does nothing; 1.5-second hold with ring/haptic; VoiceOver same Save/Resume/Discard sheet; cancel restores prior state.
Tests: hold contract, simulator inspection, save/discard regressions.

## S7: Stats and map
As a runner, I want readable metrics and a following map.
Acceptance: swipe pages; huge distance, moving time, average/current pace, estimated calories; compact accessible GPS; map >=60% of map page, follows latest fix; small-screen scrolling.
Tests: build, simulator inspection, follow camera math.

## S8: Calories
As a runner, I want an honest active-energy estimate.
Acceptance: ACSM level-running estimate; Health then manual/profile weight; no invented weight; live/summary est.; 70 kg x 10 km ~700 kcal; old runs decode.
Tests: numeric reference, invalid data, settings, Codable.

Each story is verified before completion. Final gate: combined suite, simulator QA, independent review, push and PR. Physical requirements remain explicit.
