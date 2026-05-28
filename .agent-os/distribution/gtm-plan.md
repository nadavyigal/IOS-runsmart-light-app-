---
type: gtm-plan
product: RunSmart iOS
version: v0.1
inherited_from: RunSmart iOS/docs/product-strategy-2026-05.md
status: draft
created: 2026-05-28
last_updated: 2026-05-28
owner: founder
---

# GTM Plan — RunSmart iOS

Last synced from: `RunSmart iOS/docs/product-strategy-2026-05.md` (2026-05-24)

## 1. One-Line Positioning

The AI running coach for beginners and returning runners who need safe daily adaptation — not just faster race plans.

## 2. Audience Segments

See `audience.md` for full segment details. Summary:
- Primary: The Rookie (28–45) — new or returning runner, no wearable or basic Apple Watch
- Secondary: The Striver (25–40) — intermediate runner with Garmin or Apple Watch, churned from Runna

## 3. Jobs To Be Done

1. Wake up and know if I should run and at what effort — in 30 seconds
2. Explain why the plan is right (or adapt it) when it feels wrong for my body today
3. Show me that my workout contributed to something visible
4. Catch tiredness before I do and hold me back with a reason I believe

## 4. Acquisition Wedge

Churned-from-Runna runners citing injury or plan rigidity.

## 7. Pricing

- v1.0 ships free (decided 2026-05-27)
- Paid tier: TBD (model not yet confirmed — subscription vs. IAP vs. credits)
- Android: out of scope for 2026
- Hebrew ASO: in scope

## 8. Channels (Priority Order)

1. App Store Optimization (Tier A — active)
2. Product-led landing pages (Tier A — next focus week after App Store submission)
3. LinkedIn founder updates (deferred to launch week)
4. Running SEO content (Tier B — next focus week)
5. Runna comparison page (Tier B — plan next)
6. Garmin / Strava integration content (Tier B — plan next)
7. Beginner challenges (Tier C — conditional on challenge feature ship)
8. Partnerships (Tier B — next focus week)
9. Lifecycle email (planned — 3 drafts ready, Resend + Supabase spec ready)
10. Community research (Tier C — observation only, no spam)

## 9. Acquisition Funnel

App Store (primary) → install → Today screen → plan generated → first run logged

Web → App Store CTA (secondary; `at=` / `ct=` attribution not yet wired — add to assets-needed.md)

## 10. Activation Funnel

Install → onboarding complete → first plan generated → first run logged → week-1 adherence check

## 11. Retention Funnel

Week 1: daily readiness check + plan recommendation
Week 2: earned trust signal — "this coach knows me"
Week 3+: post-run debrief loop + visible progress narrative

## 13. Launch Model

- **Now — Pre-Launch (current sprint)**: App Store submission (target 2026-06-01); rs-aso-001 description approved; rs-aso-002 screenshot overlays approved
- **V1.1 — First 30 days post-launch**: 21-Day Running Foundation onboarding; weekly progress narrative; monitor D7 + D14 retention
- **V1.2 — Days 30–90**: Post-run debrief loop; Adaptive Plan / Flex Week; churned-Runna campaign
- **Later — 90+ days**: Garmin / wearable depth (Striver persona); Apple Watch complication; community / social (if retention is strong)

## 15. Risks And Mitigations

| Risk | Why it matters | Mitigation |
|---|---|---|
| Plan accuracy feels generic in week 1 | Kills trust before it forms | E1 (coach rationale) must ship before launch |
| 21-Day Challenge not differentiated from NRC/Runna | Loses the Rookie before they experience the coach | Make coach voice the differentiator — explain every step |
| Safety explanations feel paternalistic | Users override and ignore them | Frame as "here's what the data says" not "you can't do this" |
| Solo founder: four P1 epics in one sprint | E1–E4 ship late or half-baked | Sequence: E1 + E3 before launch; E4 in V1.1 |
| Runna brand awareness gap (735K followers vs. early-stage) | Acquisition is harder without social proof | Lean into churned-Runna wedge; safety story creates earned media |

## 16. Open Questions

- What does the 21-Day Rookie Challenge look like day-by-day? Does it replace the standard onboarding flow or run alongside it?
- What is the pricing model relative to Runna's $119.99/yr?
- When does the weekly progress narrative ship — push notification, in-app card, or both?
- Is Hebrew ASO in scope for the initial App Store submission or a follow-up locale?

## 17. Decision Log

- 2026-05-27: v1.0 ships free; paid tier TBD
- 2026-05-27: Android out of scope for 2026; Hebrew ASO in scope
- 2026-05-27: Email platform = Resend via Supabase Edge Functions (free 3K/mo)
- 2026-05-27: App Store submit target = 2026-06-01 (soft; may slip if overlays or analytics not done)
- 2026-05-28: GTM plan v0.1 derived from product-strategy-2026-05.md; full install per `install-runsmart-ios.md` is a follow-up session
