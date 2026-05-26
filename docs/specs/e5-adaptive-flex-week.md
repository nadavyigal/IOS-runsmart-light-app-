# Spec: E5 — Adaptive Plan / Flex Week

*Priority: P2 — first V1.2 epic*
*Retention link: Personalization accuracy + safety confidence*
*Strategy doc: `docs/product-strategy-2026-05.md` (Epic E5)*

---

## Product Brief

### Idea
Give the runner a one-tap way to tell RunSmart "I'm tired" / "I'm traveling" / "I missed a workout" and have the AI restructure the rest of the current week in seconds, with a plain-language rationale for every change. Replaces manual plan-dragging with adaptive coaching.

### Runner Problem
Life happens. The runner gets bad sleep, travels, gets sick, or misses Tuesday's workout. Today's app forces them to either push through (risking injury), skip silently (breaking the plan and the habit), or manually drag workouts around. None of these feel like coaching — they all feel like managing software.

Beginners especially can't tell *how* to restructure: do I just shift everything one day? Do I drop the long run? Do I do the missed workout tomorrow on top of tomorrow's workout? Wrong answer = injury or burnout.

### Target User
Primary: **Rookie** runner past day 7 — has a plan, has hit at least one life disruption, doesn't know how to react.
Secondary: **Striver** with a wearable — wants the AI to act on the readiness data they already see, not just display it.

### Daily Use Moment
Sunday night the runner sees a hard week ahead but they're already exhausted from this week. OR: Wednesday morning they wake up and realize they have to travel Thursday-Friday for work. OR: They missed yesterday's tempo and the app still shows it as the next thing to do.

They open the app, tap one button, pick a reason, and get a coach-rewritten week back in under 5 seconds. They tap Confirm. The plan is updated. Trust is reinforced.

### Desired Outcome
"I'm tired / traveling / missed a day" becomes a first-class app action, not a workaround. The user trusts that the rewritten week is safe, smart, and personal — not a generic shift. Plan abandonment after disruption drops.

### Why iOS Native
The trigger needs to be one-tap from Today and Plan tabs. The diff preview needs SwiftUI animation to make the change feel intentional. The new plan must save locally first (offline-tolerant), then sync to Supabase. Push notification on completion is native.

### Non-Goals
- Not a full plan regeneration (that already exists via `regenerateTrainingPlan`). Flex Week only touches the current ISO week + maybe early next week.
- Not a manual editor — users do not drag workouts around. They state intent; AI executes.
- Not multi-week restructure (defer to V1.3+).
- No new readiness inputs — uses existing Garmin/manual readiness signals.
- No editing of completed workouts. Only future workouts in the current week.
- No race-week or taper-week restructure logic in V1 (flag it but skip rewriting if `plan.isTaperWeek == true` — fall back to coach message).

### Success Signals
- Tap-to-restructured-plan in under 5 seconds (AI timeout 4s, fallback ≤ 1s).
- Restructure is meaningful: at least one workout changes intensity, distance, day, or is replaced with rest — never a no-op.
- Coach rationale is shown for every changed workout ("Moved Thursday's tempo to Saturday because you're traveling Thursday-Friday").
- User confirms before changes commit. Cancel is always one tap.
- Safety bounded: weekly mileage cannot increase by more than the 10% rule allows; no two hard sessions back-to-back; no replacing rest with hard effort.
- The change appears in Today, Plan, and weekly summary immediately after confirm.

---

## User Flow

### Entry points
1. **Plan tab** — primary entry. A "Need to adjust?" pill at the top of the current week, always visible.
2. **Today card** — secondary. A "Not feeling 100%?" link below the rationale, only shown when readiness < 60 or user has previously skipped a workout this week.
3. **Missed workout card** — when a workout was scheduled yesterday and not completed, the PlanExplanationCard already shows "Reschedule" — wire this into the same flex-week flow.

### Sheet flow (full-screen cover)
1. **Reason picker** — 3 cards, large tap targets:
   - "I'm tired" (uses today's readiness as evidence)
   - "I'm traveling" — opens a day picker (which days are blocked)
   - "I missed a workout" — pre-selects the most recent missed workout
2. **AI restructure (loading state)** — skeleton card with "Coach is rewriting your week…" copy. Max 4s before fallback.
3. **Diff preview** — current week vs. proposed week, with rationale per change:
   - Each changed row shows: `[old workout]` → `[new workout]` + 1 sentence "why"
   - Unchanged rows shown muted at the bottom
   - Big "Confirm New Week" button + "Keep Original Plan" secondary button
4. **Confirm state** — checkmark + "Your week is updated" + auto-dismiss after 1s back to Plan tab with the new week highlighted

### Failure states
- AI timeout (>4s): show a deterministic fallback restructure (rules-based: shift missed workout +1 day, mark traveling days as rest, swap tomorrow's hard for easy if "tired") with rationale "Coach is taking a careful path — here's a safe adjustment based on standard recovery rules."
- Network offline: queue the request; show "We'll restructure when you're back online" and apply the deterministic fallback immediately so the runner still has a plan for today.
- Edge function error: show error toast + keep original plan, never partially apply.

---

## Stories

### Story 1: `FlexWeekReason` model + reason picker UI
Add the domain model and the first sheet screen.

**Acceptance criteria:**
- `FlexWeekReason` enum: `.tired`, `.traveling(blockedDays: [Date])`, `.missedWorkout(workoutID: UUID)`
- `FlexWeekRequest` struct: `reason: FlexWeekReason`, `currentWeek: [PlannedWorkout]`, `readinessContext: ReadinessContext?`
- `FlexWeekReasonPicker` SwiftUI view with three large tap targets.
- "Traveling" expands inline to a day-of-week multi-select.
- "Missed workout" pre-selects the most recent missed workout, with a chip showing which one.
- Cancel button always visible; tapping it dismisses the sheet without side effects.
- Dynamic Type tested at largest accessibility size.

---

### Story 2: `flex_week` edge function intent
Add a new intent to `supabase/functions/coach_message/index.ts` that takes the current week + reason + readiness context and returns a restructured week with per-change rationale.

**Acceptance criteria:**
- New intent `flex_week` follows the same pattern as `weekly_summary` and `run_debrief`.
- Request payload includes: `reason` (string), `current_week` (array of workout DTOs), `readiness_context` (object with body battery, HRV, sleep, recent runs), `blocked_days` (array of ISO dates if traveling), `missed_workout_id` (string if missed).
- Response payload: `restructured_week` (array of workout DTOs, same shape as current_week, with optional `original_workout_id` linking back), `changes` (array of `{workout_id, change_type, rationale}`), `safety_warnings` (array of strings, optional).
- Safety constraints encoded in the prompt: never exceed +10% weekly mileage vs. original; no back-to-back hard sessions; if `is_taper_week` is true on any input workout, return original week unchanged with rationale "Taper week — locking the schedule."
- Validate response shape before returning to client (mirror `weekly_summary` field validation).
- Timeout: 4s from client.
- Unit tests for the edge function: tired-reason path, traveling path, missed-workout path, taper-week guard.

---

### Story 3: Service layer — `flexCurrentWeek(request:) async -> FlexWeekOutcome`
Wire the edge function into the iOS service layer.

**Acceptance criteria:**
- New method on `WebParityProviding` (or `PlanProviding`) protocol: `func flexCurrentWeek(_ request: FlexWeekRequest) async -> FlexWeekOutcome`.
- `FlexWeekOutcome` includes: `restructuredWeek: [PlannedWorkout]`, `changes: [FlexWeekChange]`, `safetyWarnings: [String]`, `source: .ai | .deterministicFallback | .offlineQueued`.
- Default extension returns `.deterministicFallback` so mocks compile.
- Live `SupabaseRunSmartServices` implementation:
  - Builds payload from `FlexWeekRequest` + current readiness
  - Calls `coach_message` with intent `flex_week`
  - 4s timeout sentinel like `WeeklySummaryTimeoutError`
  - On timeout/error: calls local `DeterministicFlexWeekBuilder.restructure(...)`
  - Caches outcome in UserDefaults for offline replay
- Unit test: timeout returns deterministicFallback, AI happy path returns .ai, malformed AI response falls back without crashing.

---

### Story 4: `DeterministicFlexWeekBuilder` (rules-based fallback)
Pure Swift logic that produces a safe restructure when AI is unavailable.

**Acceptance criteria:**
- Static `restructure(week:reason:)` returning `(restructuredWeek, changes)`.
- Rules:
  - **Tired**: if today is a hard workout, downgrade to easy (same distance, intensity → easy). If today is rest, no change. Add "RECOVERY" rationale.
  - **Traveling(days)**: for each blocked day, mark workout as rest. Try to shift one moved workout to a non-blocked day if total weekly mileage allows (≤ +10%). Never compress two hard sessions back-to-back.
  - **MissedWorkout(id)**: if missed workout is easy, drop it. If hard, attempt to insert tomorrow only if tomorrow is currently easy/rest. Never double up two hard days.
- Always returns at least one `FlexWeekChange` (no no-ops).
- Unit tests for each rule + edge cases (taper week, race week, all-blocked week).

---

### Story 5: Diff preview UI (`FlexWeekDiffView`)
Side-by-side or stacked diff of original vs. proposed week with per-change rationale.

**Acceptance criteria:**
- Each changed row shows: original workout (strikethrough), new workout (highlighted), 1-sentence coach rationale below.
- Unchanged rows shown muted at the bottom in a collapsible "No change" section.
- `safety_warnings` appear as an info banner at the top (yellow, not red — informational).
- "Confirm New Week" primary button; "Keep Original" secondary.
- Loading state (skeleton) shown during the AI call.
- Cancel from the navbar always available, never destructive.

---

### Story 6: Apply restructure to the local + remote plan
On confirm, update the plan in TrainingPlanRepository and Supabase.

**Acceptance criteria:**
- New method on `TrainingPlanRepository`: `applyFlexWeek(authUserID:outcome:) async -> Bool`.
- Updates plan workouts in place: changes `workout_type`, `distance_km`, `target_pace`, `scheduled_date`, `intensity` per the outcome.
- Marks each changed workout with `adjusted_at: Date` and `adjusted_reason: String` for audit trail.
- Posts `NotificationCenter.default.post(name: .runSmartPlanDidChange)` so Today, Plan, and weekly summary reload.
- Idempotent: re-applying same outcome is a no-op (compare hash).
- Failure path: rollback local changes if remote update fails, surface error toast.

---

### Story 7: Entry point wiring
Add the entry points to Plan tab, Today card, and missed-workout card.

**Acceptance criteria:**
- `PlanTabView`: "Need to adjust?" pill at top of current week, opens FlexWeek sheet.
- `TodayTabView`: "Not feeling 100%?" link below rationale, shown only when `readiness < 60` OR there's at least one skipped/missed workout this week.
- `PlanExplanationCard`'s "Reschedule" button (when `.missedWorkout` explanation): opens FlexWeek sheet with `.missedWorkout` reason pre-selected.
- Sheet is a `.fullScreenCover` (per app shell pattern from CLAUDE.md non-Coach modal conventions).
- Tested: opening from each entry point produces the same sheet behavior.

---

### Story 8: Analytics + adjustment history
Track usage to inform V1.3 decisions.

**Acceptance criteria:**
- PostHog event `flex_week_triggered` with `reason`, `source: ai|fallback|offline`, `entry_point`.
- PostHog event `flex_week_confirmed` with `changes_count`, `time_to_confirm_seconds`.
- PostHog event `flex_week_cancelled` (split: cancelled at picker vs. cancelled at diff).
- Plan model gains a `adjustment_history` array (capped at last 10) so we can show "You've flexed this week 2 times" if it happens more than once in 7 days (signal for V1.3 to surface coach intervention).

---

## Acceptance Checklist (before marking done)

- [ ] `FlexWeekReason`, `FlexWeekRequest`, `FlexWeekOutcome`, `FlexWeekChange`, `FlexWeekRecord` models added
- [ ] All four reasons supported: `.tired`, `.traveling`, `.missedWorkout`, `.sick(daysOut:)`
- [ ] `flex_week` edge function intent deployed and tested in Supabase (all 4 reason paths)
- [ ] `flexCurrentWeek` service method wired with 4s timeout + deterministic fallback
- [ ] `DeterministicFlexWeekBuilder` covers all 4 reason paths with unit tests
- [ ] `FlexWeekReasonPicker` and `FlexWeekDiffView` render correctly at smallest + largest Dynamic Type
- [ ] Plan tab + Today + PlanExplanationCard entry points wired
- [ ] `applyFlexWeek` updates local repo + remote with rollback on failure
- [ ] Local push notification scheduled on confirm (30s delay, skipped if foregrounded)
- [ ] Profile → Notifications toggle for "Plan adjustment confirmations" — default ON
- [ ] Notification posted on apply; Today + Plan + Weekly Progress reload
- [ ] Taper week guard returns original week unchanged
- [ ] 10% mileage rule enforced (AI prompt + deterministic fallback)
- [ ] No back-to-back hard sessions ever produced
- [ ] Sick reason: no hard sessions within 48h of last sick-rest day
- [ ] `GentleCoachInterventionCard` shown on 3rd flex in 7 days
- [ ] "Talk to Coach" path pre-seeds coach context with last 3 adjustments
- [ ] PostHog events firing: triggered / confirmed / cancelled / intervention_shown / intervention_action
- [ ] Xcode build clean, no warnings; tests pass on iPhone 17 simulator
- [ ] Dark mode + Dynamic Type verified

---

## Files Likely Touched

**New:**
- `IOS RunSmart app/Models/FlexWeek.swift` — models (`FlexWeekReason`, `FlexWeekRequest`, `FlexWeekOutcome`, `FlexWeekChange`, `FlexWeekRecord`)
- `IOS RunSmart app/Features/Plan/FlexWeekReasonPicker.swift`
- `IOS RunSmart app/Features/Plan/FlexWeekDiffView.swift`
- `IOS RunSmart app/Features/Plan/GentleCoachInterventionCard.swift`
- `IOS RunSmart app/Services/DeterministicFlexWeekBuilder.swift`
- `IOS RunSmart appTests/FlexWeekTests.swift`

**Modified:**
- `supabase/functions/coach_message/index.ts` — add `flex_week` intent (all 4 reasons)
- `IOS RunSmart app/Services/RunSmartServices.swift` — protocol + default extension (`flexCurrentWeek`, `adjustmentHistoryWithin`)
- `IOS RunSmart app/Services/Supabase/SupabaseRunSmartServices.swift` — live implementation + local push scheduling
- `IOS RunSmart app/Services/Supabase/TrainingPlanRepository.swift` — `applyFlexWeek` method
- `IOS RunSmart app/Features/Today/TodayTabView.swift` — "Not feeling 100%?" entry point
- `IOS RunSmart app/Features/Plan/PlanTabView.swift` — "Need to adjust?" pill
- `IOS RunSmart app/Features/Today/PlanExplanationCard.swift` — wire Reschedule into FlexWeek sheet
- `IOS RunSmart app/Features/Profile/...` — Notifications toggle for "Plan adjustment confirmations"
- `IOS RunSmart app/Models/RunSmartModels.swift` — `adjustment_history`, `adjusted_at`, `adjusted_reason` on PlannedWorkout

**Estimated scope:** 9 stories, ~4–6 implementation sessions if one story per session per CLAUDE.md "one story at a time" rule.

---

## Resolved Decisions (2026-05-26)

1. **"I'm sick" is a fourth V1 reason.** Adds heavier safety constraints than "I'm tired" — no hard sessions for the next 3–7 days, downgrade tomorrow + day-after to easy/rest, and surface the multi-day implication explicitly in the diff preview.
2. **Push notification on confirm defaults to ON.** Copy: "Your week is updated — tap to see tomorrow." User can disable in Profile → Notifications. Requires existing notification permission (no new prompt).
3. **Gentle coach intervention at 3+ flexes in 7 days.** When the user opens the FlexWeek reason picker for the 3rd time in 7 days, prepend a soft coach card to the picker: *"This is the third time this week the plan hasn't fit your life. Want to talk it through?"* with two CTAs: "Talk to Coach" (opens Coach sheet pre-seeded with the adjustment history) and "Just adjust this week" (continues to reason picker). Non-blocking — never prevents the adjustment.

---

## Additional Specs From Resolved Decisions

### Reason: `.sick(daysOut: Int?)` — Story 1 + 2 + 4 extension
- Picker UI: "I'm sick" card with optional follow-up "How many days do you think?" (3, 5, 7, "not sure")
- Edge function `flex_week` intent treats `.sick` as: replace all workouts for `daysOut` (or default 4 if "not sure") with rest. After the sick window, downgrade the first workout back to easy. Rationale per change is explicit about the illness recovery: "Rest for the next 4 days while you recover — your first run back is an easy 20 min to test how you feel."
- Deterministic fallback: same pattern as edge function but rules-based.
- Safety: never allows a hard session within 48 hours of the last sick-rest day.

### Push notification on confirm — Story 6 extension
- After `applyFlexWeek` succeeds, schedule a local `UNUserNotificationContent` push for 30 seconds out (gives user time to put the phone down).
- Content: title "Your week is updated", body summarizes tomorrow's workout (e.g., "Tomorrow: easy 30 min run").
- Profile → Notifications toggle: "Plan adjustment confirmations" — default ON.
- Skip notification if app is foregrounded.

### Gentle intervention — Story 7 + new Story 9
- New service method `adjustmentHistoryWithin(_ window: TimeInterval) async -> [FlexWeekRecord]`.
- `FlexWeekReasonPicker` checks count of records in last 7 days. If ≥ 2 prior (so this triggers on the 3rd), render a `GentleCoachInterventionCard` at the top of the picker.
- New PostHog event: `flex_week_intervention_shown` and `flex_week_intervention_action: {talk_to_coach | continue_to_picker | cancelled}`.

### Story 9 (new): Gentle coach intervention
**Acceptance criteria:**
- `FlexWeekRecord` model with `reason`, `confirmedAt`, `changesCount`.
- `adjustmentHistoryWithin(_:)` queries the existing `adjustment_history` array (Story 8) from the active plan.
- `GentleCoachInterventionCard` SwiftUI view: soft tone, non-blocking, two CTAs.
- "Talk to Coach" path: dismisses FlexWeek sheet, opens Coach modal with pre-seeded message "It looks like this week has been disrupted a few times. Want to revisit your goals or check on your training load?" — coach context includes the last 3 adjustment reasons.
- "Just adjust this week" path: dismisses the card, continues to reason picker normally.
- Snapshot test for the card at smallest + largest Dynamic Type.
