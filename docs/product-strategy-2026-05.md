# RunSmart iOS — Product Strategy
*Last updated: 2026-05-24*

---

## One-Sentence Positioning

RunSmart is a native iOS AI running coach that earns your trust by giving accurate, personalized daily guidance, showing your progress week over week, and never letting you get injured chasing a plan that wasn't built for your body.

---

## Target Customer

### Primary: The Rookie (28–45)
- New or returning runner, runs 1–3x/week, no wearable or basic Apple Watch
- Tried NRC or a free training plan, got injured or lost motivation by week 3
- Needs: a plan that feels accurate to *their* fitness level, visible proof they're improving, confidence they won't hurt themselves
- Win condition: hits week 2 and thinks "this coach actually knows me"

### Secondary: The Striver (25–40) with a wearable
- Intermediate runner, owns Garmin or Apple Watch, generates data they don't fully trust or act on
- Churned from Runna because the plan didn't adapt when life got in the way
- Needs: an additional intelligence layer on their wearable data, adaptive coaching with a "why"
- Win condition: replaces manual plan-dragging with AI that makes the adjustment for them

### Acquisition Wedge
Runners who have churned from Runna, specifically citing injury or plan rigidity.

---

## Competitive Context

### Primary Competitors
Runna, TrainingPeaks, Run Trainer, Nike Run Club

### Competitive Positioning
| | RunSmart | Runna |
|--|--|--|
| Category | AI running coach | Training plans app |
| AI depth | GPT-4o · conversational · 12 coaching skills | AI-powered plan selection + algorithmic + user-triggered adaptation |
| Adapts daily? | Yes — readiness gate, recovery engine, conversational adjustment | User-triggered + algorithmic; "Not Feeling 100%" added 2025 |
| Safety guardrails | Non-negotiable: 10% rule, readiness gate, conservative defaults by design | Recovery weeks + beginner plan overhaul; some users report overload following plans rigidly |
| Platform | Native iOS (HealthKit + Garmin readiness depth) | iOS, Android, Apple Watch, Garmin, COROS |
| Pricing | TBD | $19.99/mo · $119.99/yr · $149.99/yr (Strava bundle, US only) |
| Distribution | App Store + organic | Strava bundle — 100M user funnel |

### When RunSmart Wins
- Runner has been injured or overloaded on a rigid plan and needs a safer coach
- Beginner wants daily readiness-aware guidance, not just a schedule
- Busy life requires real-time conversational flexibility (not manual plan-dragging)
- Runner values "why" explanations for every recommendation — not just what to do
- Churned from Runna; not locked into Strava bundle pricing ($149.99/yr annual-only)

### When Runna Wins
- User already pays for Strava — bundle upsell is frictionless and annual-only
- Runner wants Olympian-credentialed, coach-authored plan library
- User needs ultra/marathon-specific plan depth
- Needs Android or non-Apple Watch wearable support on day 1
- Brand awareness: they've heard of Runna, not RunSmart

### Battlecard Notes (updated 2026-05-24)
- Do not claim "Runna lacks Garmin/COROS depth" — they support structured workout sync to Garmin and COROS.
- Do not claim "Runna is unsafe" — softer: "some users and press report overload; Runna has responded with beginner plan updates."
- Do not claim "Runna has no AI" — they have AI-powered features; RunSmart's edge is conversational + readiness-first + daily adaptation.
- AI running coach space is now crowded: Kotcha (Kipchoge-backed), KASI (real-time audio), URUNN (Mo Farah/WithU), Strava Athlete Intelligence, Garmin Connect+, Apple Workout Buddy. Avoid generic "AI running coach" positioning.
- Sharpest wedge: "The AI running coach for beginners and returning runners who need safe daily adaptation — not just faster race plans."
- Alternative contrast line: "Not built around Olympian intensity. Built around real-life consistency."

### Three Things to Remember
1. **A plan isn't a coach.** Runna delivers a schedule. RunSmart delivers a coach that reads your body every morning.
2. **Safety is a feature.** The 10% rule, readiness gate, and conservative defaults aren't fine print — they're the product.
3. **Personal growth, not race times.** Runna is organized around finish lines. RunSmart is organized around you.

---

## Core Problem Statement

Beginner and intermediate runners can't tell if their training is working for *them* specifically. They can't tell when to push and when to back off, and no tool they've tried gives them a trustworthy, personalized signal. The result: they overtrain (injury), undertrain (stagnation), or quit (burnout) — usually before week 3.

**The gap is not more data or more features. It's a coach that earns trust through accuracy, visible progress, and safety confidence.**

---

## Retention Thesis

Users stay past week 2 when three things are true simultaneously:

1. **Personalization accuracy** — the plan and daily recommendation feel calibrated to *my* body and fitness, not a template
2. **Visible progress** — I can see and feel that I'm improving, even if small
3. **Safety confidence** — RunSmart has my back; when it holds me back, it tells me why in coach language, and I trust it

These three together = earned trust. Earned trust = retention. Retention = word-of-mouth growth.

---

## Jobs-to-be-Done

1. *When I wake up*, I want to know if I should run and at what effort — in plain language, not numbers — so I can make a confident decision in 30 seconds.
2. *When my plan says something that feels wrong for my body today*, I want RunSmart to explain why it's right (or adapt it if it isn't), so I don't have to choose between the plan and my instincts.
3. *When I finish a workout*, I want to see that it contributed to something — a streak, a fitness milestone, a coach reaction — so I feel the progress building.
4. *When I'm tired or sore*, I want RunSmart to catch it before I do and hold me back with a reason I believe, so I trust it more than I trust my impulse to push through.

---

## Epic Roadmap

| # | Epic | Retention Link | Priority |
|---|------|---------------|---------|
| E1 | **Personalization Accuracy Signal** — coach rationale on every Today recommendation | Accuracy = trust | P1 |
| E2 | **Progress Narrative** — weekly coach summary of what changed and what's next | Visible progress = commitment | P1 |
| E3 | **Safety Explanation Layer** — plain-language "why" when RunSmart holds you back | Safety confidence = loyalty | P1 |
| E4 | **21-Day Rookie Challenge** — structured first experience with daily micro-goals and coach check-ins | Onboarding to habit | P1 |
| E5 | **Adaptive Plan / Flex Week** — one-tap "I'm tired / traveling" triggers AI week restructure | Accuracy + safety | P2 |
| E6 | **Post-Run Debrief Loop** — AI reaction to run quality with "what it means for tomorrow" | Visible progress | P2 |
| E7 | **Garmin / Wearable Depth** — HRV trend and training readiness trend (7-day) for Striver persona | Striver accuracy | P3 |

---

## Roadmap by Release

### Now — Pre-Launch (current sprint)
- E1: Personalization rationale on Today card (AI backend live — prompt + copy work)
- E3: Safety explanation layer: when readiness gate fires or workout scales down, show the "why" in coach voice
- App Store submission: signing, privacy strings, screenshots, archive inspection

### V1.1 — First 30 days post-launch
- E4: 21-Day Rookie Challenge — structured onboarding trial that converts new users into habits
- E2: Weekly progress narrative (push notification or in-app coach summary card)
- Monitoring: PostHog D7 + D14 retention, identify where trust breaks

### V1.2 — Days 30–90 (based on retention signal)
- E6: Post-run debrief loop
- E5: Adaptive plan / Flex Week
- Acquisition: churned-Runna campaign ("Your plan injured you. Ours won't.")

### Later — 90+ days
- E7: Garmin / wearable depth for Striver persona
- Apple Watch complication
- Community / social (only if retention is strong enough that users want to share)

---

## Top Risks

| Risk | Why it matters | Mitigation |
|------|---------------|-----------|
| Plan accuracy feels generic in week 1 | Kills trust before it forms | E1 rationale must ship before launch; prompt quality is the product |
| 21-Day Challenge not differentiated from NRC/Runna onboarding | Loses the Rookie before they experience the coach | Make coach *voice* the differentiator — explain every step |
| Safety explanations feel paternalistic, not coaching | Users override and ignore them | Frame as "here's what the data says" not "you can't do this" |
| Solo founder: four P1 epics competing for the same sprint | E1–E4 ship late or half-baked | Sequence strictly: E1 + E3 before launch, E4 in V1.1 |
| Runna brand awareness gap (735K followers vs. early-stage) | Acquisition is harder without social proof | Lean into churned-Runna wedge; safety story creates earned media |

---

## Open Questions

- What does the 21-Day Rookie Challenge look like day-by-day? Does it replace the standard onboarding flow or run alongside it?
- What is the pricing model relative to Runna's $119.99/yr?
- When does the weekly progress narrative ship — push notification, in-app card, or both?
