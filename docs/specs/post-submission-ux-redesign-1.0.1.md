# Post-Submission UX Redesign — RunSmart iOS 1.0.1

**Status:** Approved  
**Date:** 2026-05-31  
**Target release:** 1.0.1 fast follow  
**Branch:** feature/ux-redesign-1.0.1  

## Objective

A first-time user can understand the product loop in one session: see what to do today → run → review report → adjust plan if needed. Achieved by simplifying the information architecture across Today, Plan, Report, and Profile without removing any existing features or changing backend schema.

## Constraints

- No new backend schema or data models.
- Reuse existing services and data paths throughout.
- Run tab is out of scope — stays unchanged.
- First-Time Setup v2 is out of scope for 1.0.1 — deferred to next release.
- App Store build has already been submitted on a separate branch. This work happens on a new branch and must not disturb submission artifacts.

---

## 1. Today v2

### Goal
Answer one question first: "What should I do today?" The first viewport must contain only what is needed to act. Everything else scrolls below.

### First viewport (exact top-to-bottom order)

1. **Header row**
   - Left: greeting text ("Good morning / afternoon / evening, [name]") + streak subtext ("🔥 N day streak") below it
   - Right: Coach icon button — `Image(systemName: "sparkles")`, 34×34, `accentPrimary` tint, `RoundedRectangle(cornerRadius: 10)` background at `accentPrimary.opacity(0.12)` — taps to `router.openCoach(context: .today)`
   - Implementation: modify the existing `header` computed var in `TodayTabView`

2. **Compact 7-day week strip**
   - Existing `TodayWeekStripSection` — moved above the decision card, no internal changes

3. **Today decision card**
   - Existing `TodayWorkoutRecommendationCard` — no internal changes
   - Includes: workout type label, title, chips (distance, pace, intensity), metric tiles, CTA button, Modify/Route/Skip row

### Below fold (scroll reveals, all kept, same logic as current)

In order:
- `SafetyExplanationCard` (conditional)
- `PlanExplanationCard` "Why this workout?" (conditional)
- `TodayRouteRecommendationCard` (conditional, when `showsTodayRoute`)
- `FlexWeekTodayLink` (conditional)
- Latest run preview row — single tappable row (date + distance + pace), taps to `router.selectedTab = .report`. Replaces `RecentRunReportsCard` list. Only shown when `runReports` is non-empty.
- `UpcomingRunsCard`
- `WeeklyProgressCard` or `Beginner5KHabitCard` (existing conditional logic)
- `WeatherConditionsCard` (moved from last position, kept)
- Challenge card (`ChallengeProgressCard` or `ChallengeInviteCard`, existing conditional logic)
- `TodayWellnessTrendCard` (Striver-only, unchanged)

### Removed entirely from TodayTabView

| Component | Reason |
|---|---|
| `TodayCoachHeroCard` | Replaced by ✦ header icon |
| `InsightCard` ("Coach Insight") | Duplicate coach entry point |
| `TodayConversationPreview` | Coach accessible via header icon |
| `TodayQuickActions` | Record Run is the decision card CTA; Add Activity moves to Plan |
| `quickStats` mini-stat strip | Streak moves to header; HRV/recovery live in Report > Progress |

### Bottom padding fix
Change `padding(.bottom, 24)` → `padding(.bottom, 140)` to match Plan and Profile and clear the floating tab bar.

---

## 2. Plan v2

### Goal
Lead with the current week. Coach becomes a contextual entry point, not a briefing card.

### First viewport (exact top-to-bottom order)

1. **Header** — existing `RunSmartTopBar(title: "Plan")`
2. **Current week section** — existing `PlanCurrentWeekSection` (moved to position 2, was position 4)
3. **Flex Week adjust pill** — existing `FlexWeekAdjustPill` (moved up with the week section)
4. **"Explain this week" compact button** — new compact row replacing `PlanBriefingCard`
   - Style: `background: accentPrimary.opacity(0.08)`, `border: accentPrimary.opacity(0.2)`, height 44, rounded rect 10
   - Label: `Image(systemName: "sparkles")` + "Explain this week" left-aligned, chevron right
   - Action: `router.openCoach(context: .plan)`
5. **Segmented picker** — existing `SegmentedPillPicker` (Monthly | Weekly | Progress)
6. **Segment content** — existing month/week/progress views unchanged

### PlanExplanationCard — conditional display
Only show when the plan actually changed. Hide when `explanation.trigger == .normal && explanation.isOnTrack`. This guard applies to both `PlanTabView` and `TodayTabView` — current code in both views always shows it.

### PlanBriefingCard
Remove entirely. The "Explain this week" compact button covers the same function with less noise.

### PlanCoachNotesCard + InsightCard on Plan
Remove `InsightCard` from Plan (duplicate). Keep `PlanCoachNotesCard` — it's below fold and shows specific upcoming workout notes, which is distinct from the coach entry point.

### Add Activity
`PlanActionGrid` already has an "Add Run" tile that calls `openAddActivity()`. Rename tile title from "Add Run" to "Add Activity" and update detail text to "Log manually or sync". No functional change.

---

## 3. Report v2

### Goal
Report is the canonical home for all activity history, AI-generated reports, and progress trends. Duplicate report lists in Today and Profile are removed.

### Structure

**Above segments (unchanged):**
- `RunSmartHeader(title: "Report")`
- Stats hero card (last 14 days total km, run count, time pills)

**Segmented control — three segments:**

#### Runs segment (default)
- The existing top-level `All / Runs / Workouts` filter pills are removed. The three segment tabs (Runs | Reports | Progress) replace them as the primary navigation. All recorded runs are shown in this segment without further sub-filtering.
- Existing activity list (`ActivityRow` items with delete, tap to report detail)

#### Reports segment
- AI-generated run reports list (moved from `RecentRunReportsCard` in Today and Profile)
- Each row: run title, date, distance, score badge (if generated), "Generate" chip (if not)
- Taps to existing `RunReportDetail` sheet
- Empty state: "Complete a run and tap Generate to get your first AI coach report."

#### Progress segment
- Zone analysis card (existing, moved from Report bottom)
- Training load card (existing `RecoveryPlanCard` / `TrainingLoadSnapshot`)
- Run trend chart (existing `RunTrendChartCard`)
- Weekly stats (existing `WeeklyRecapView` content, currently unused in this tab)

### Coach entry point in Report
Each report row in the Reports segment shows a small "Explain this run ✦" link. Taps to `router.openCoach(context: .report)` — pass run context so Coach has the run data. Use existing `CoachEntryPoint` mechanism.

### Removed from Today and Profile
- `RecentRunReportsCard` removed from `TodayTabView` (replaced by single latest-run preview row)
- `RecentRunReportsCard` removed from `ProfileTabView`

---

## 4. Profile v2

### Goal
Profile is account/settings-oriented. First viewport shows identity and connected services.

### Section order (new)

1. Header (`RunSmartTopBar(title: "Profile", showSettings: true)`)
2. `identityHeader` (unchanged)
3. `statsBar` (unchanged)
4. `connectedSection` ← **moved up** (was near bottom)
5. `trainingDataCard` (training preferences)
6. `coachSettingsGrid`
7. `coachSparkCard`
8. `optimizationCards`
9. `achievementsGallery`
10. ~~`RecentRunReportsCard`~~ ← **removed**

No new components required. Only reorder and remove.

---

## 5. Coach consolidation

One visible Coach entry point per root screen. All open `CoachFlowView` as a sheet using existing `router.openCoach(context:)`.

| Screen | Entry point | Context |
|---|---|---|
| Today | ✦ icon in header | `.today` |
| Plan | "Explain this week" compact button | `.plan` |
| Report | "Explain this run" link on report rows | `.report` |
| Flex Week | Existing contextual entry | unchanged |
| Profile | `coachSparkCard` kept as-is — it's below fold and low-risk | `.profile` |

`TodayCoachHeroCard`, `InsightCard` (Today and Plan), and `TodayConversationPreview` are the components eliminated. No changes to `CoachFlowView` internals.

---

## 6. Floating tab bar safe area

**Problem:** Today uses `padding(.bottom, 24)` while Plan and Profile use `padding(.bottom, 140)`. On 6.1, 6.5, and 6.9-inch devices the final Today content is hidden behind the floating `CustomTabBar`.

**Fix:** Change Today `.padding(.bottom, 24)` → `.padding(.bottom, 140)`.

**Acceptance:** Final card in Today scroll is fully visible above the tab bar on all three device sizes in Simulator.

---

## 7. Run tab

**Unchanged.** Out of scope. The Run tab is a focused single-purpose recording screen with no first-viewport noise problem.

**Post-run bridge (small wire-up):** Implement: after a run completes, wire the "View Report" CTA in `PostRunSummaryView` (or wherever it is surfaced) to set `router.selectedTab = .report` instead of opening a sheet, so the user lands in the canonical Report home. Current behaviour: CTA opens a sheet. `PostRunLearningCard` (workout-save card shown after the summary) is unrelated to this routing — no changes needed there.

---

## 8. First-Time Setup v2

**Out of scope for 1.0.1.** Deferred to next release. No partial implementation. Existing onboarding flow unchanged.

---

## Implementation sequence

1. **Today v2 + bottom-nav safe area** — highest user-visible impact, fixes "too much at once" feedback
2. **Report v2** — segmented structure + move report lists from Today and Profile
3. **Coach consolidation** — remove duplicate entry points across Today and Plan
4. **Plan v2** — week-first reorder + compact coach button
5. **Profile v2** — section reorder + remove reports card
6. **Post-run bridge** — verify Report tab routing from post-run summary

---

## Test plan

### Fresh user flow
- Sign in → existing onboarding → generate plan → land on Today
- Verify first viewport: header with streak + Coach icon, week strip, decision card

### Today states
- No plan: decision card shows "no plan" state, Coach icon still present
- Active workout day: Start Run CTA visible in first viewport
- Rest day: rest state card
- Completed run today: latest run preview row visible below fold
- Low recovery: SafetyExplanationCard below decision card

### Coach
- Tap ✦ icon on Today → Coach sheet opens with `today` context
- Tap "Explain this week" on Plan → Coach sheet opens with `plan` context
- Tap "Explain this run" on Report row → Coach sheet opens with `report` context
- Verify no duplicate Coach cards visible on any root screen

### Report segments
- Runs segment: activity list shows, all recorded runs visible with no sub-filtering (filter pills removed)
- Reports segment: generated reports appear, "Generate" chip appears for runs without reports
- Progress segment: zone analysis, load card, trend chart all render

### Profile
- Connected services visible in first viewport (above fold on 6.1-inch)
- No run reports list visible anywhere on Profile

### Visual QA
- Simulator screenshots on 6.1, 6.5, 6.9-inch: Today, Plan, Report, Profile
- Floating tab bar does not cover bottom content on any device size

### Regression
- Build passes (no new compiler errors)
- Existing analytics events fire: `tab_viewed`, `coach_thread_opened`, `run_completed`, `plan_generated`
- Run tab unaffected

---

## Analytics events (no changes needed)

Existing events cover this sprint. No new instrumentation required. Verify `coach_thread_opened` fires correctly from the new header icon and Plan compact button entry points.
