# How to run the external Claude design session

This folder is a self-contained handoff. Take it into a Claude.ai chat/project with design capability, iterate, then bring the results back here for SwiftUI implementation.

## Steps

1. **Start a new Claude.ai chat** (or project) — use one with image/design generation.
2. **Paste `DESIGN-BRIEF.md`** as the first message.
3. **Attach the audit screenshots** from `../product-design-2026-06-25/screenshots/` (see list below).
4. **Attach or paste `DESIGN-TOKENS.md`** so the output stays on-brand and implementable.
5. **Kick off** with something like:
   > "You're redesigning a native iOS (SwiftUI) running-coach app used outdoors during exercise. Read the brief and tokens. Bold reimagining is welcome but it must stay native iOS, keep the near-black + electric-lime identity, be glanceable/one-handed/sunlight-legible on the run screens, and respect Dynamic Type / VoiceOver. Start with Today (Screen A) and the Run flow (Screen C) — they're the plan→run activation spine. For each screen give me: a hi-fi mockup, a short rationale, implementation notes (layout/spacing/tokens/components/motion), and any new copy. Flag anything needing new backend/plan-engine/sensor data. Do not undo the safety fixes already shipped (deliberate Finish guard, active-run nav protection, HealthKit disclosure)."
6. **Iterate** screen by screen. Push for the activation-critical surfaces first.

## The 13 screenshots (what each is)

| File | Screen | Priority |
|---|---|---|
| `01-today.jpg` | Today + next workout + Start Run CTA | **P1 (activation hero)** |
| `02-plan.jpg` | Weekly plan | P1 |
| `03-flex-week.jpg` | Flex Week reason picker | P1 |
| `04-run-prestart.jpg` | Run pre-start (GPS, benefits, Start) | **P1** |
| `05-location-permission.jpg` | Location permission prompt | P1 (context) |
| `06-run-active.jpg` | Active run HUD (safety-critical) | **P1** |
| `07-run-saved.jpg` | Post-run saved summary | **P1** |
| `08-report-runs.jpg` | Report / Runs list | P2 |
| `09-report-reports.jpg` | Report / Reports cards | P2 |
| `10-profile.jpg` | Profile + connected services | P3 |
| `11-garmin-wellness.jpg` | Garmin Wellness detail | P3 |
| `12-sign-in.jpg` | Sign in with Apple + HealthKit disclosure | P2 |
| `13-onboarding-goal.jpg` | Onboarding goal selection | P2 |

## Already-shipped fixes (don't redo / don't undo)

PR #64 already tackled the tactical safety/UX findings: global tab-bar bottom padding, **deliberate Finish guard**, active-run navigation protection, short/zero-distance run copy, Flex Week disabled-CTA-until-selected, Profile status vs action separation, Garmin Wellness un-truncation. Ask the designer to **build on** these, not reopen them.

## Bringing it back

Save returns into `returns/` in this folder — ideally:

- `returns/<screen>-mockup.<png|jpg>` — the image(s)
- `returns/<screen>-notes.md` — rationale + implementation notes + copy

…or paste the designs + notes back into the Claude Code session here. Then implementation proceeds **one screen at a time, Today + Run flow first**, each as its own branch/PR with the existing review + test gates.

## Guardrails to repeat to the external session

- Native iOS / SwiftUI only — no web patterns, no new UI frameworks.
- Keep the **near-black + electric-lime** identity; reuse tokens unless a change is called out.
- The **plan → Start Run → finish** spine must get *easier and more motivating*.
- Run screens: **glanceable, one-handed, sunlight-legible, accidental-tap-safe.**
- Respect Dynamic Type, VoiceOver, reduced motion; never rely on color alone for status.
- Flag anything needing new backend / plan-engine / sensor data.
