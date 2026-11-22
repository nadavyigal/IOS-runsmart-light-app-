# Coach Experience v2: success metrics and analytics events

**Owner:** story C0.2 (refined plan S3). **Written:** 2026-11-21. **Sources:** v1.3 section 7.1 (metrics) and section 3.8 (events).

**What this is.** The definitions Nadav reads at each TestFlight gate (TF-1a, TF-1b, TF-2) and at the stop/go after TF-2. v2 sets no new targets: "watch" means review at each gate and at the end of the pilot. PRD v7.2 targets still apply where cited.

**How events get built.** Analytics is PostHog. The app calls `AnalyticsService.track(_ event:, properties:)` in `IOS RunSmart app/Services/Analytics/AnalyticsService.swift` (verified: the file exists and `track` calls `PostHogSDK.shared.capture`). No new vendor and no new table. C7.0 creates an empty typed `CoachV2Analytics` wrapper (no events). **Each story adds its own events in its own PR**, reviewed with the code that fires them. Nothing in this file is implemented yet.

**Property rules (v1.3 section 3.8).**
- Allowed: internal uuids, enums, counts and durations.
- Never: names, note, flag or reply text, or RPE values tied to a person.

**Server-side facts are not duplicated as events.** They come from existing tables: `coach_notification_log` (pushes sent, by kind), `coach_athlete_events`, `coach_feedback`, `coach_feedback_replies`, `athlete_run_flags`, `coach_plan_versions`.

---

## 1. Success metrics

| ID | Name | Definition | PostHog events used | Other sources | Release that can first measure it |
|---|---|---|---|---|---|
| SM-V1 | Coach daily use | Days per week each coach opens Coach Today. Validates C7.1. PRD SM-2 (at least 2 a week) is the floor. | `coach_today_viewed` | none | R1 (TF-1a) |
| SM-V2 | Time to handle a pain flag | Median `minutes_open` on `flag_resolved`, per coach. Watch. | `flag_resolved(minutes_open)` | `athlete_run_flags` | R1 (TF-1a) |
| SM-V3 | Consent outcome | For P9: athletes who acked vs athletes who tapped "Leave {Coach}", per coach. Counter-metric for PRD SM-C1 (opt-out). | `consent_v2_shown`, `consent_v2_acked`, `consent_v2_leave_tapped` | none | R1 (TF-1a) |
| SM-V4 | Coach involvement | Coach-built or coach-edited workouts plus feedback per active athlete per week. Extends PRD SM-3 (at least 1 per active athlete per week). | `coach_workout_saved`, `coach_assign_done` | `coach_feedback` | R3 (TF-2) |
| SM-V5 | Replies | Replies per coach note. Answers open question Q3 (one-level reply vs full chat). | `coach_note_reply_sent` | `coach_feedback`, `coach_feedback_replies` | R1 (TF-1a) |
| SM-V6 | Draft usefulness | Share of AI drafts that are published, and edits per published draft. Watch. | `plan_draft_requested`, `plan_draft_result`, `plan_published(edits_in_draft)`, `plan_draft_discarded` | `coach_plan_versions` | R4+ (after TF-2 decision) |

### Counter-metrics

| ID | Name | Definition | PostHog events used | Other sources | Release that can first measure it |
|---|---|---|---|---|---|
| SM-VC1 | Notification fatigue | Share of coaches or athletes who turn off any coach push kind, plus pushes per coach per day. If more than one pilot coach turns off "run finished", revisit the D6 default with Nadav. | `notification_pref_changed(kind, enabled)` | `coach_notification_log` | R2 (TF-1b) |
| SM-VC2 | Athlete overrides | `athlete_changed_coach_workout` plus `goal_change_confirmed`, per coach workout. PRD SM-C2. | `athlete_changed_coach_workout(action)`, `goal_change_confirmed(k)` | none | R3 (TF-2) |

**PRD SM-8 (data leakage) stays the headline risk metric.** It is not an event metric; it is checked by the RLS and leakage tests.

---

## 2. Events by story (v1.3 section 3.8)

Each story adds its events in its own PR. The "Feeds" column shows which metrics use the event.

| Story | Release | Events (client) | Feeds |
|---|---|---|---|
| C7.0 | R1 | none. Creates an empty `CoachV2Analytics`. | none |
| C7.1 | R1 | `coach_today_viewed(athlete_count, need_count)`, `coach_today_row_opened(reason)` | SM-V1 |
| C7.3 | R1 | `run_rpe_set(shared)`, `run_note_saved(shared)`, `run_note_hidden_toggled(hidden)`, `rpe_backfill_done(count)` | none directly |
| C7.4 | R1 | `flag_created(kind, has_run)`, `flag_removed`, `flag_resolved(minutes_open)` | SM-V2 |
| C7.7 | R1 | `coach_note_reply_sent` | SM-V5 |
| C7.8 | R1 | `consent_v2_shown(surface)`, `consent_v2_acked(surface)`, `consent_v2_leave_tapped(surface)` | SM-V3 |
| C7.10 | R2 | `push_permission_prompted(role)`, `push_permission_result(role, granted)`, `push_opened(kind)` | none directly |
| C7.11 | R1 | `coach_removed_athlete`, `athlete_left_coach` | none directly |
| C7.14 | R2 | `notification_pref_changed(kind, enabled)` | SM-VC1 |
| C7.16 | R1 | `milestone_shown(kind)`, `praise_sent(kind)` | none directly |
| C8.2, C8.3, C8.4, C8.11 | R3 (C8.3, C8.11 are R4+) | `coach_workout_saved(action, source_before, has_steps)`, `coach_assign_done(added, skipped)` | SM-V4 |
| C8.15 | R3 | `athlete_changed_coach_workout(action)` | SM-VC2 |
| C7.9, C8.5 | R3 | `goal_change_warned(k)`, `goal_change_confirmed(k)`, `goal_change_blocked` | SM-VC2 |
| C8.6, C8.7 | R4+ | `plan_draft_requested`, `plan_draft_result(ok, seconds)`, `plan_published(weeks, workouts, edits_in_draft)`, `plan_draft_discarded` | SM-V6 |
| C8.12 | R4+ | `broadcast_sent(recipients)` | none directly |
| C9.3, C9.4 | R4+ | `weekly_summary_opened`, `ai_note_draft_sent(edited)`, `ai_label_shown` (athlete side) | none directly |

C7.13 (the old "analytics" story) no longer exists as its own PR. The refined plan folds it into the stories above (S3).

---

## 3. Rules for the story that fires an event

- Add the event to `CoachV2Analytics` in the same PR as the code that fires it, and tick "analytics" in the PR's cross-cutting checklist (v1.3 section 1.1).
- Properties follow the rules at the top of this file. A test or review check confirms no name, note text or RPE-per-person value is sent.
- Update this file in the same PR if an event's name or properties change from the table.
- Do not read production PostHog or Supabase from an agent session. Nadav reads the numbers.
