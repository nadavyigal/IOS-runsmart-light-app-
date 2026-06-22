---
product: RunSmart iOS
artifact: assumptions
feature: HRV dual-source attribution
status: draft
founder-review-needed: yes
date: 2026-06-22
source-plan: tasks/plan-hrv-dual-source-attribution-2026-06-22.md
source-pr: "#55"
---

# Assumption Prioritization: HRV Dual-Source Attribution

This matrix prioritizes the risky assumptions in PR #55 before implementation continues. Scores are qualitative, using Impact and Risk from the PM assumption-prioritization skill.

| # | Assumption | Impact | Risk | Category | Experiment |
|---|---|---:|---:|---|---|
| A1 | Garmin Connect HRV samples in HealthKit can be identified by bundle identifier. | High | High | Test first | On a real device with Garmin-to-Health sync, inspect HRV sample source bundle identifiers without logging personal health values. Success: at least one Garmin-origin HRV sample is classified as Garmin. |
| A2 | Apple Watch HRV samples can be reliably classified as Apple Health, not Garmin. | High | Medium | Test early | Add pure classifier tests for Apple bundle patterns and run a real-device spot check with Apple Watch HRV if available. Success: Apple-origin HRV never receives Garmin attribution. |
| A3 | Most-recent HRV sample is the right deterministic rule when multiple sources exist. | Medium | High | Design experiment | Create fixture data with mixed Garmin and Apple samples. Compare most-recent vs majority-source results. Success: chosen rule is documented and produces predictable attribution. |
| A4 | Adding `hrvSource` to stored snapshots will not break existing local decoded data. | High | Low | Proceed with tests | Add Codable tests for old snapshots without `hrvSource`. Success: old payload decodes to `.unknown`. |
| A5 | Recovery and Today can consume source-aware HRV without broad model churn. | Medium | Medium | Test through Story 3 | Implement a small pure resolver and pass source through `RecoverySnapshot`. Success: no unrelated service protocol or preview breakage. |
| A6 | `Garmin` and `Apple Health` labels are sufficient for v1.0.4, without device model. | High | Medium | Founder/Garmin acceptance | Keep `Garmin` for v1.0.4 and track device model separately. Success: screenshots are accepted for ticket 213145/213165 or no issue is raised before reply. |
| A7 | Simulator/demo screenshots can prove UI placement, while real device validation proves source detection. | Medium | Medium | Split validation | Use pure tests and demo mode for layout, real device for source bundle proof. Success: both evidence types are captured separately. |
| A8 | This can fit in v1.0.4 build 17 without delaying the Garmin brand-compliance response too much. | High | Medium | Scope gate | Execute one story at a time and stop after Story 4 if Story 5 evidence is enough. Success: no new scope beyond source-aware attribution. |

## Priority Order

1. A1: Garmin HealthKit bundle provenance.
2. A4: Backward-compatible snapshot decoding.
3. A2: Apple source classification.
4. A3: Mixed-source precedence rule.
5. A5: Threading source through recovery and Today.
6. A6: Label sufficiency for Garmin review.
7. A7: Evidence split between demo screenshots and real device source proof.
8. A8: v1.0.4 schedule fit.

## PM Gate

The first implementation story should validate A1 and A4 before touching UI. If A1 fails, the PR needs a different source-detection strategy before any Garmin attribution is shown for HealthKit HRV.
