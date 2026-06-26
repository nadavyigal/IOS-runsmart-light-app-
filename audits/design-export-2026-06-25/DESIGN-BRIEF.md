# RunSmart iOS — Design Improvement Brief

- Date: 2026-06-25
- Source audit: `../product-design-2026-06-25/audit-notes.md` (13 screenshots in that folder's `screenshots/`)
- Latitude: **Bold reimagining welcome** (still native iOS, still implementable in SwiftUI)
- Owner: founder (Nadav). Designs come back here for SwiftUI implementation.
- Note: The 2026-06-25 audit's tactical safety/UX fixes are **already shipped** (PR #64) — see §2. This brief is for the *bolder* rethink on top of those.

---

## 1. The product

**RunSmart** is an AI running coach for iOS. It builds a personalized training plan around the user's goal, tells them what to run today, records the run with GPS, and coaches them before and after.

**Core flow:** sign in → **pick a running goal** (onboarding) → **AI generates a training plan** → **Today** shows the next workout with a *Start Next Run* action → **Run** (pre-start → active recording → saved summary) → **post-run debrief / reports** → repeat. Garmin / Apple Health / Garmin Wellness feed readiness and recovery context.

**Navigation:** custom dark bottom tab bar — **Today, Plan, Run, Report, Profile**. Secondary surfaces include Flex Week (plan adjustment) and Garmin Wellness detail.

It is used **outdoors, in motion, one-handed, often in bright light** — glanceability and accidental-tap safety matter more here than in a typical app.

---

## 2. The business problem this redesign must serve

This is not a cosmetic refresh. The activation metric that matters is **plan → run conversion**:

- The instrumented funnel is **`plan_generated` → `plan_run_cta_tapped` → `run_started` → `run_completed`.**
- Target: **at least 20% plan-to-run conversion** in a usable-plan cohort.
- So the **#1 job of this redesign:** make the path from *"I have a plan / a workout for today"* to *"I started and finished that run"* feel effortless, motivating, and obvious — especially the **Today → Start Run → finish** spine.

**Already shipped (PR #64, do not undo — build on these):** global tab-bar bottom padding; **deliberate Finish guard** (a run no longer ends on one accidental tap); active-run navigation safety; short/zero-distance run handling in post-run copy; Flex Week disabled-CTA-until-selected; Profile connected-service status vs action separation; Garmin Wellness text no longer truncated.

**Design north star:** a user who opens RunSmart with a workout waiting should start that run in one or two confident taps, and the active-run + finish experience should feel safe and rewarding enough that they come back tomorrow.

---

## 3. Audience & context of use

Runners from beginner to experienced, mobile-first, motivation-sensitive. Critically, the core moments happen **outdoors during exercise**: pre-start (standing, about to go), active run (moving, glancing, one-handed, possibly sweaty, bright sunlight), and immediately post-run (catching breath). Recovery/readiness data (Garmin/Apple Health) informs but shouldn't overwhelm.

---

## 4. Platform & constraints (so designs are implementable)

- Native **iOS / SwiftUI**, iPhone. **Dark mode is the brand** (near-black + electric lime).
- Must respect: **Dynamic Type**, safe areas, **VoiceOver**, reduced motion, and **outdoor legibility / large touch targets** during a run.
- Bottom nav stays a bottom tab bar (restyleable; the active-run screen may hide/protect it — already done).
- Use the brand tokens in `DESIGN-TOKENS.md`. You may evolve them, but say so and keep the app recognizable (no full rebrand; the lime action color is core identity).
- Standard iOS components / SwiftUI only — assume **no new third-party UI frameworks**.
- Flag anything needing new backend data, plan-engine changes, or new sensor/HealthKit data.

---

## 5. Screens to redesign (in priority order)

### Priority 1 — activation-critical (the plan→run spine)

#### Screen A. Today — `01-today.jpg` (`Features/Today/TodayTabView.swift`)
**Current:** overview + next workout, now with a *Start Next Run* CTA for the next planned workout. Health: good, with a bottom-overlap layout risk (tab bar).
**Goals:** make "your next run" and its **Start** action the unmistakable hero of the screen; surface just enough readiness/why-this-workout to motivate without clutter; one confident tap to begin.
**Bold invitation:** rethink Today as an activation surface — what's the single most motivating thing to show a runner who should run today? Consider a run-first hero, a "today's mission" framing, streak/momentum, or readiness-aware nudges.

#### Screen B. Plan — `02-plan.jpg` (`Features/Plan/PlanTabView.swift`) + Flex Week — `03-flex-week.jpg` (`Features/Plan/FlexWeekReasonPicker.swift`)
**Current:** weekly plan (good, with bottom crowding) and Flex Week reason picker (Continue-state already tightened in PR #64).
**Goals:** make the week legible and motivating — where am I, what's next, what happens if life gets in the way (Flex Week). Reinforce that the plan adapts to the runner.
**Bold invitation:** reconsider how a week of training is visualized for motivation and glanceability, not just as a list.

#### Screen C. Run flow — pre-start `04-run-prestart.jpg`, location permission `05`, active `06-run-active.jpg` (`Features/Run/LiveRunView.swift`), saved `07-run-saved.jpg` (`Features/Run/PostRunSummaryView.swift`)
**Current:** pre-start is strong (GPS readiness, benefits, big Start). Active run is the safety-critical surface (Finish guard + nav protection already added). Saved summary handles short/zero runs now.
**Goals:** the active run must be **glanceable in motion, sunlight-legible, one-handed, accidental-tap-safe**, with Pause/Finish/Coach unmistakable. The saved summary should make finishing feel earned and pull the user toward the next run.
**Bold invitation:** reimagine the active-run HUD for real outdoor use (large metrics, minimal chrome, safe finish), and the post-run moment as a reward + "come back tomorrow" hook.

### Priority 2 — first impression & retention surfaces

#### Screen D. Sign-in & Onboarding goal — `12-sign-in.jpg`, `13-onboarding-goal.jpg`
**Current:** both strong — Sign in with Apple + visible HealthKit disclosure; onboarding starts from a concrete running goal.
**Goals:** keep the low-effort, trustworthy first impression; if anything, raise the emotional pull of "what RunSmart will do for you." Don't regress the App-Review-friendly HealthKit disclosure.

#### Screen E. Report — runs `08-report-runs.jpg`, reports `09-report-reports.jpg`
**Current:** Reports cards are strong; Runs list has crowding.
**Goals:** make progress feel earned and motivating; fix list density; keep scores understandable.

### Priority 3 — trust / readability

#### Screen F. Profile & Garmin Wellness — `10-profile.jpg` (`Features/Profile/ProfileTabView.swift`), `11-garmin-wellness.jpg` (`Features/Wellness/GarminWellnessViews.swift`)
**Current:** Profile is a clear home for connected services (status/action semantics tightened in PR #64); Garmin Wellness no longer truncates.
**Goals:** keep connection status vs action clear; make wellness/readiness guidance readable and confidence-building.

---

## 6. Cross-cutting requirements

- **Accessibility:** primary content clears the tab bar at all Dynamic Type sizes; secondary/metadata text needs sufficient contrast on the dark card system; never rely on color alone for status (keep text labels beside colored dots/badges); large comfortable touch targets, especially during a run.
- **Outdoor use:** the run surfaces must stay legible in bright light and usable one-handed in motion.
- **Motivation/copy:** every surface should answer "what's my next run, and how do I start it?" — and make finishing feel rewarded.

---

## 7. What "bold" means here

You're invited to rethink layout, hierarchy, motion, depth, and the metric/data visual language — as long as it stays **native iOS**, **implementable in SwiftUI**, and keeps the **near-black + electric-lime** identity recognizable. Non-negotiables:

1. The **plan → Start Run → finish** spine must get *easier and more motivating*, not just prettier.
2. The **active-run** surface must stay safe (no accidental finish/navigation) and glanceable outdoors.
3. Respect **Dynamic Type, VoiceOver, reduced motion**, and don't regress the safety/trust fixes from PR #64 or the HealthKit disclosure.

---

## 8. What to bring back (return format)

For **each** redesigned screen, deliver:

1. **A hi-fi mockup** of the bold direction (a safer fallback variant is optional and welcome).
2. **A short rationale** — what problem it solves, what changed, why.
3. **Implementation notes** — layout structure (stacks/sections), spacing, which tokens, any new component, motion intent.
4. **New copy strings** (English).
5. **Flags** — anything needing new backend data, plan-engine changes, or new sensor/HealthKit data.

Prioritize **Today (A)** and the **Run flow (C)** — they are the plan→run activation spine. Drop returns into `returns/` in this folder (or paste them back into the chat); implementation proceeds **one screen at a time, activation-critical screens first.**
