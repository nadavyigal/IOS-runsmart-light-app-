# Coach Mode status (pre-pilot, 21 stories)

Last checked: 2026-11-18. Source of the plan: `COACH-MODE-ALL-PROMPTS.md`.
"Checked in code" means the story's key pieces exist on `main` (or on the PR branch), read against the prompt's acceptance criteria. It is a code read, not a device test.

| # | Story | State | PR | Checked in code |
|---|---|---|---|---|
| 0.1 | Completed runs mark the planned workout done | merged | [#182](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/182) | integer `actual_pace`, pending-completion retry queue |
| 1.1 | Close cross-user data leaks | merged | [#183](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/183), [#184](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/184) | `20261114120000_close_cross_user_rls_leaks.sql`, `rls_leaks.sql` test |
| 0.2 | Runs link to their workout, imports re-match | merged | [#185](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/185) | `runs.workout_id` migration, 30-day backfill flag, tests |
| 1.2 | Coach role and invite code | merged | [#186](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/186) | `coach_profiles`, `coach_invites`, `get_or_create_my_invite`, Coach tab, invite error state |
| 1.3 | Athlete joins by code, with consent | merged | [#187](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/187) | `coach_athlete_links`, `lookup_invite`, `join_coach` |
| 1.4 | Invite link opens the join screen | merged | [#195](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/195) | `/join/{CODE}` handling, paste fallback |
| 1.5 | Leave coach; account deletion cleans up | merged | [#193](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/193) | `leave_coach`, delete-account cleanup of links, feedback, drafts, routes |
| 1.7 | Coach picks Plan Mode and Group Plan Settings | merged | [#197](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/197) | plan mode migration, 16-week rule |
| 3.5 | AI speaks as the coach's assistant | merged | [#198](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/198), [#200](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/200) | `CoachAssistant.swift`, "That's {Coach}'s workout" |
| 6.1 | In-app runs upload their route after consent | merged | [#199](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/199) | route upload outbox; switched on after 6.4 |
| 1.8 | Group Plan joiner gets the group plan | merged | [#202](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/202) | `GroupPlanJoin.swift`, "This replaces your current plan" |
| 2.2 | Coach reads linked athletes' plans and runs | merged | [#201](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/201) | `20261117164500_coach_read_rpcs.sql` |
| 6.4 | Start/end privacy zone | merged | [#203](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/203) | `PrivacyZoneRouteUploadPreparer`, "Start/end hidden for privacy" |
| 2.3 | Coach athlete list with adherence | merged | [#204](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/204) | `CoachAthleteList.swift`, "No plan yet" |
| 2.4 | Athlete detail, planned vs actual | merged | [#206](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/206) | extra run, matched by date, missed, partial |
| 3.1 | Coach writes feedback | merged | [#207](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/207) | `coach_feedback`, add/edit RPCs, outbox |
| 3.2 | Athlete sees coach feedback | merged | [#208](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/208) | `my_coach_feedback`, `mark_feedback_read`, badge, 72 h line |
| 6.2 | Coach sees route map | merged | [#209](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/209) | `coach_get_run_route`, "Map hidden" / "No map" |
| 6.3 | Athlete hides one run's map | merged | [#212](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/212) | `set_run_route_hidden`, A9/A10 toggle, hide-before-upload |
| 3.3 | Coach visible on Today and Plan | merged | [#211](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/211) | `get_my_coach`, `CoachPresence` |
| 3.4 | Coach welcome note | merged | [#213](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/213) | welcome template, per-athlete override, Today welcome card |

Follow-up PRs, not stories: [#210](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/210) (3.2 follow-up, Plan scroll targets) and [#214](https://github.com/nadavyigal/IOS-runsmart-light-app-/pull/214) (CI port clash), both merged.

## Not started

None. All 21 stories are merged.

## Migrations not applied yet (apply in this order, then mirror each to `Running-coach-/v0/supabase/migrations/`)

1. `20261118100000_coach_feedback.sql` (3.1)
2. `20261118120000_athlete_feedback_read.sql` (3.2)
3. `20261118140000_coach_run_route.sql` (6.2)
4. `20261118160000_get_my_coach.sql` (3.3)
5. `20261118170000_set_run_route_hidden.sql` (6.3)
6. `20261118180000_coach_welcome_note.sql` (3.4)
