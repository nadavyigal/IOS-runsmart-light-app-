# Training Load — build plan

Drafted 2026-08-30, from the founder's Garmin Connect screenshots (Load Focus /
Exercise Load / Training Load tabs).

---

## The headline: most of the maths already exists

`IOS RunSmart app/Services/TrainingLoadCalculator.swift` already computes exactly
what Garmin's "Training Load" tab shows:

| Garmin screenshot | RunSmart today |
|---|---|
| Acute Load `500` | `TrainingLoadMetrics.acuteLoad` — 7-day summed session load |
| Chronic Load `317` | `TrainingLoadMetrics.chronicLoad` — 28-day total ÷ 4 |
| Load Ratio `1.5 - High` | `TrainingLoadMetrics.acwr` = acute ÷ chronic |
| Optimal Range band `0.8–1.5` | `status(for:)` bands at 0.8 / 1.3 / 1.5 |
| "Consider adding more time to recover" | `.elevated` / `.highRisk` statuses |

Covered by 7 passing tests in `TrainingLoadCalculatorTests.swift`. **This is an
extension job, not a new feature.** Do not rewrite the calculator.

### One deliberate difference, and why to keep it

Garmin derives exercise load from **EPOC**, which needs a full heart-rate stream.
RunSmart uses **session-RPE (Foster)**: `minutes × RPE`, with an average-HR band
fallback. That is a peer-reviewed method, and critically it works for a runner
with no wearable at all.

Do not chase EPOC parity. Garmin's partner APIs do **not** expose Acute Load,
Training Status, Training Readiness, Recovery Time, or Endurance Score, so this
could never be imported even with Garmin approved. Computing it in-app is the
only available path, and it has the better property: **it works for 100% of
users, not just Garmin owners.** That is the differentiator worth stating in the
UI.

---

## What is genuinely missing

The calculator returns a **single snapshot for "now"**. Every screenshot is a
**4-week daily time series**. That gap is the actual work.

1. No historical series — cannot draw the timeline chart
2. No Load Ratio chart with the optimal-range band
3. No Load Focus (Anaerobic / High Aerobic / Low Aerobic split)
4. No per-activity Exercise Load list
5. No dedicated screen — load only appears inside `RecoveryInsightPlanCard`

### The data constraint that shapes everything

`RecordedRun` carries `averageHeartRateBPM` — a single scalar, **not** a
heart-rate stream. Consequences:

- Stories 1–3 are fully buildable today.
- **Load Focus (Story 4) is not**, honestly, from average HR alone: assigning a
  whole run to one zone by its average is not a zone distribution and would be a
  fabricated chart. It needs real time-in-zone.
- Good news: `HealthKitSyncService.averageHeartRateBPM(for:store:)` already
  queries `.heartRate` samples and discards the distribution. Story 4 extends an
  existing query rather than building new plumbing.

---

## Stories

One at a time; lint + tests green before moving on.

### Story 1 — Daily load series (no UI)
Add `TrainingLoadCalculator.series(runs:days:now:calendar:)` returning
`[DailyTrainingLoadPoint]` (date, acuteLoad, chronicLoad, acwr, status), one
point per day over a 28-day window, each computed from that day's trailing
7-/28-day windows.

Keep it pure and deterministic with injected `now`/`calendar`, matching house
style.

**Tests:** a known 28-run fixture producing a known series; a rest-day gap
carrying acute load downward; fewer than 4 runs yielding `.insufficientData`
for every point; the 28-day boundary excluding older runs.

*No UI. This story is safe to land alone.*

### Story 2 — Training Load screen, Acute Load tab
New `Features/TrainingLoad/TrainingLoadView.swift`, reachable from the Activity
tab. Renders the Story 1 series as the timeline: line for acute load, shaded
optimal-range band, current value plus its status word, and the plain-language
recommendation.

Reuse `ContentCard` / `SectionLabel` / `MetricBars` and the existing
`DesignSystem` accents. Do not introduce a charting dependency without asking —
Swift Charts is first-party and already available on the deployment target.

**Tests:** view-model mapping from series to chart points, band bounds, and the
status→copy mapping. **Empty state must follow the pattern just landed in
`WellnessTrendsView`:** say why it is empty and how far along it is, never a bare
"need more data".

### Story 3 — Load Ratio tab
Toggle mirroring the screenshot: ratio line, 0.8–1.5 optimal band, and the
Acute/Chronic pair beneath. Pure presentation over Story 1's data.

**Tests:** ratio series mapping; divide-by-zero when chronic is 0; the four
status bands at their exact boundaries.

### Story 4 — Load Focus (gated on real HR zones)
**Do not start before Stories 1–3 ship.** Requires:
1. Extending `HealthKitSyncService` to retain an HR sample distribution per workout.
2. A zone model (max-HR or HRR based) — needs the runner's max/resting HR, which
   means an onboarding or profile input.
3. Only then the three-bar Anaerobic / High Aerobic / Low Aerobic split.

If the zone inputs are not available, **ship Stories 1–3 and omit Load Focus**
rather than approximating it from average HR.

### Story 5 — Exercise Load list
Per-activity load scores, the input side of the acute number.
`TrainingLoadCalculator.sessionLoad(for:)` already returns exactly this value, so
this is a list view over existing data.

---

## Sequencing recommendation

Ship **Story 1 + 2** as the first release. That alone reproduces the primary
screenshot, and it is the smallest thing that is genuinely useful. Story 3 is a
cheap follow-on. Treat 4 and 5 as separate decisions.

## Things to get right

- **Attribution:** this is RunSmart-computed, not Garmin-derived. Do **not** put
  Garmin attribution on it, and do not let it inherit the Wellness screen's
  Garmin branding. It is also the honest answer to "why does RunSmart need
  Garmin at all" — for this feature, it does not.
- **Localization:** RunSmart ships a String Catalog (en + he, 358 keys). Use
  literal `Text("…")`, including interpolation, so SwiftUI extracts keys.
  Passing a computed `String` into `Text` silently bypasses the catalog.
- **RTL:** Hebrew is a shipped language. A left-to-right time axis must be
  checked under RTL before release.
- **Naming:** do not call anything "Training Readiness". That name belongs to a
  Garmin metric RunSmart cannot obtain, and it is already mislabelled on the
  Wellness screen (tracked in the Garmin resubmission draft).

## Open question for the founder

Garmin's bands are personalised to fitness level and training history; RunSmart's
are fixed at 0.8 / 1.3 / 1.5. Fixed bands are defensible and standard for ACWR,
but a returning-from-injury runner will read "high risk" sooner than Garmin would
tell them. Personalising the bands is a real piece of work — flagging it as a
decision, not silently choosing.
