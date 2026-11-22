---
name: RunSmart Coach Experience v2: UX spec for the gated flows, plus a per-story gap review
status: draft (UX pass, for review alongside the plan)
updated: 2026-11-20
sources:
  - runsmart-audit/coach-experience-v2-full-plan.md (v1.1, 33 stories): the plan this spec serves. Not edited.
  - runsmart-coach-mode/EXPERIENCE.md: the coach-mode MVP experience spine. Its voice rules, key strings and decisions carry over unless this doc flags a conflict.
  - runsmart-coach-mode/PRD-coach-mode-mvp.md (v7 final) and epics-and-stories.md (v6 final)
  - runsmart-audit/hebrew-localization-estimate-2026-11-19.md (week-start and RTL notes)
---

# RunSmart Coach Experience v2: UX spec and gap review

## How to read this

- **Scope.** This doc has four parts:
  - Part 1 is the full UX spec for the three UX-gated areas in the plan: (A) Coach Today, (B) the workout builder, and (C) AI draft → review → publish, with the athlete side.
  - Part 2 is a gap review of all 33 stories, by story ID.
  - Part 3 is a ranked gap list for the whole plan.
  - Part 4 lists the decisions only the product owner can make.
- **Story IDs** (C7.x, C8.x, C9.x, L1–L4) and migration IDs (M1–M12) are copied verbatim from the plan. This doc does not rewrite acceptance criteria (AC). It adds **"AC additions"**, and the plan owner decides whether to fold them in. Where the plan and an earlier locked decision disagree, the conflict is flagged ([CONFLICT]) and not silently resolved.
- **Tags:**
  - **[ASSUMPTION]**: not decided; a default is proposed.
  - **[CONFLICT]**: the v2 plan contradicts a locked MVP decision.
  - **[UX ADDITION]**: copy or behavior the plan doesn't mention, needing no new data.
  - **[PROPOSED]**: beyond the plan's scope; needs a product decision and possibly data.
- **Names.** Coach **Dana** coaches about 8–20 mostly beginner runners. Athlete **Yoni** is one of them. Other athletes in examples: Noa, Avi, Maya. In copy, `{Coach}` is the coach's display name and `{Athlete}` is the athlete's first name.
- **Platform.** iPhone only, SwiftUI, existing design system (`ContentCard`, `NeonButtonStyle`). Copy rules: sentence case, no all-caps. The pilot UI is English. Hebrew/RTL is a later project, so this doc gives **RTL-readiness notes only**: use leading/trailing, not left/right.
- **Flag.** Everything in this doc sits behind `coachV2Enabled` (C7.0) unless marked "flag-off". Part 2 covers the flag-off and mixed-version behavior per story.

### Carry-over rules from the MVP spine (apply to every v2 surface)

1. **"Your coach" is always the human.** The engine is "RunSmart", never "your coach" or "AI coach".
2. **Attribute every change to who made it:**
   - "From {Coach}" for a workout the coach created.
   - "Edited by {Coach}" for a RunSmart workout the coach changed.
   - "Adjusted by RunSmart for {Coach}'s plan" for AI changes.
   - "Changed by {Athlete}" for an athlete change (see the [CONFLICT] in Part 3, G2).
3. **Say only what is true.** "{Coach} can see this" holds once consent exists. "{Coach} saw this" appears only after a real coach action, such as marking a flag handled or writing feedback.
4. **Coach words are the coach's words.** No feedback text and no health detail in push bodies. Nothing is written by the AI in the coach's name, and nothing is sent automatically.
5. **Missed is neutral for the athlete.** The athlete sees "Not logged", never "Missed", and no red. The coach sees the factual "Missed".
6. **The AI defers on judgment calls.** Pain goes to a doctor or physio, and plan disputes go to the coach.
7. **No pressure to stay or leave.**
8. **Post-run promise:** "{Coach} will review this run" changes to "Shared with {Coach}" after 72 hours without feedback.

### Shared visual grammar (behavioral; tokens to be defined in a later DESIGN.md)

**Adherence glyphs.** Glyphs never rely on color alone: each state has its own shape, and color is a second channel.

| State | Glyph | Color (secondary) | Coach label | Athlete label |
|---|---|---|---|---|
| Done | filled circle ● | green | "Done" | "Done" |
| Partial (below 80% of planned distance or duration) | half-filled circle ◐ | yellow | "Partial" | "Partly done" |
| Missed (day over, nothing linked) | hollow circle with a diagonal slash ⊘ | red | "Missed" | "Not logged" (no red, neutral grey) |
| Rest or nothing planned | short dash – | grey | "Rest" | "Rest" |
| Planned (today, not done yet) | hollow ring ○ with emphasis outline | none | "Not done yet" | n/a |
| Extra (run with no planned workout) [UX ADDITION, from the MVP week-strip markers] | filled circle with a small + | green | "Extra run" | "Extra run" |
| Removed by coach [UX ADDITION, MVP "skipped by coach"] | dash with a lock | grey | "Removed by you" | "Rest (from {Coach})" |

**Source and lock glyphs on workout chips:**
- Coach workout: lock glyph, labeled "Set by {Coach}" (VoiceOver: "Set by Dana, locked").
- RunSmart workout: no glyph.
- Changed by the athlete: a person glyph.

---

# Part 1: UX spec for the three gated areas

## A. Coach Today: "who needs me today" (C7.1, with C7.2, C7.4 coach side, C7.5 settings, C7.6 tap target)

### A.1 Flow A: Dana's lunch-break check (Dana, a weekday at 12:40, standing in a queue, one hand)

1. Dana opens the Coach tab. The top of the screen reads **"Today, Tue 24 Nov"**, with one summary line: **"3 athletes need you"**.
2. The first group is **"Pain or something off (1)"**. Yoni's row shows a **Pain** chip (icon plus text) and "Knee, after Sunday's long run". His dots show done, done, done, rest, done, partial, then today's ring.
3. She taps Yoni and the athlete detail opens on the flagged run, showing the flag note, "Effort 8/10" and Yoni's run note. The flag dot clears from the Today row because opening the athlete marks it seen (C7.2). The flag itself stays open until she marks it handled.
4. She writes a short note ("Take Wednesday as rest; we'll look Thursday"), then taps **Mark handled**. A toast says "Marked handled · Undo".
5. Back on Today, Yoni has moved down to **"New to review"**, because the pain flag is resolved but there's still a reply she hasn't read. Avi is under **"Missed yesterday (1)"**, and Noa is under **"Behind this week (1)"** with "1 of 3 this week".
6. **Climax:** when every row in the need groups has been opened or handled, the header changes to **"You're caught up for today"**. Under it: "11 on track · 2 rest days".

**Failure path.** Dana is underground with no signal. Today shows the last snapshot with **"Offline · updated 12:31"**, and Mark handled queues with a "Waiting to sync" clock. If the queued action later fails (for example, Yoni has left), a banner says: "1 action couldn't be saved: Yoni is no longer linked to you."

### A.2 Screen inventory (Coach Today)

| ID | Surface | Reached from | Purpose | Story |
|---|---|---|---|---|
| T1 | Coach Today (top of the Coach tab) | Coach tab; push `coachEveningSummary`; badge | Who needs me today, in one screen | C7.1 |
| T2 | Today filtered: "Missed today" | Evening summary push tap | Act on the 20:00 list | C7.6 |
| T3 | Athlete detail (existing `CoachAthleteDetailView`), opened on the relevant day or run | Row tap; push `coachRunFinished` / `coachPainFlag` / `athleteCoachReply` | Act on the reason the row was urgent | C7.1, C7.4, C7.7 |
| T4 | Flag detail block (inside T3, on the run or day) | T3 | Read the flag, mark it handled, write a note | C7.4 |
| T5 | Coach notification settings | Coach tab → ⋯ → "Notifications" | Toggles and quiet hours | C7.5 |
| T6 | Push pre-permission card (coach) | First open of T1 with `coachV2Enabled` | Ask before the system prompt | C7.10 |
| T7 | Existing roster (Needs attention / On track / No plan yet) | Below T1, or "All athletes" | Full list; flag-off fallback | existing |

### A.3 Layout and anatomy (T1)

The screen runs top to bottom in this order:

1. **Header.** "Today, {weekday} {d} {Mon}" (iOS Large Title), then a summary line:
   - "{n} athletes need you", or
   - "You're caught up for today", or
   - "No athletes yet".
2. **Push pre-permission card**, once (T6).
3. **Groups.** Each group has a text header with a count, and none relies on color. Order (plan C7.1 AC 2, extended):
   1. **Pain or something off** (open `athlete_run_flags`, oldest first)
   2. **Missed today**, shown only after the cutoff. Before the cutoff, today's not-done workout counts as "Planned", and yesterday's misses appear as **"Missed yesterday"**. [ASSUMPTION: cutoff = 20:00 athlete-local, the same moment the evening summary counts misses.]
   3. **Behind this week**: 2 or more missed this week, or the 80% rule failing for the week to date.
   4. **New to review** [UX ADDITION, from the MVP urgency tier "New run to review" / "Changed something"]: new runs, replies, goal changes, or athlete changes to coach workouts since the last visit, with nothing else urgent.
   5. **On track**, collapsed by default and showing a count: "On track (11)". Tap to expand.
   6. **Rest today**, collapsed.
   7. **No plan yet**, collapsed.
4. **Row anatomy** (top line, then second line, then the dots):
   - Leading: avatar monogram, with a "new" dot overlaid on the monogram's trailing-top corner.
   - Name, with the reason chip trailing.
   - Second line: today's workout plus status, e.g. "Tempo 6 km · Not done yet", "Easy 5 km · Done 5.2 km" or "Rest".
   - Third element: the 7 dots, oldest at the leading edge and today at the trailing edge, with "{x} of {y} this week" trailing.
   - "{n} new" text label next to the new dot (C7.2 AC 2). The dot never appears without the text.
5. **One reason chip per row**, the most urgent:
   - "Pain"
   - "Something off"
   - "Missed today" / "Missed yesterday"
   - "Behind"
   - "Reply"
   - "New run"
   - "Changed goal"
   - "Changed your workout"

   A secondary reason appears only as text in the second line.
6. **Sorting inside a group:** more urgent first (pain before off; more misses first), then the oldest unhandled item first, then name.
7. **No re-sorting while Dana is looking** (MVP rule). The list refreshes on pull-to-refresh, on re-entry, and when the app returns to the foreground. If data changed in the background: a pill "New updates · Refresh" at the top.
8. **Row actions:**
   - Tap opens T3 on the reason's day or run.
   - Trailing swipe offers "Mark handled" (only on flag rows) and "Write feedback".
   - Every swipe action is also a VoiceOver custom action and is reachable from T3.

### A.4 Data rules the UI depends on

- **Dates.** Dots use the **athlete's** local calendar dates. The plan stores UTC run dates, and `CoachAthleteList` already has the helpers. Weekday labels are rendered in the coach's locale.
- **Week start.** The athlete's training week decides "this week". [ASSUMPTION: follow the app's existing week-start rule; the localization estimate notes that `WorkoutAdherence` uses Sunday only for region IL, and the product owner should pick explicitly. See Part 3, G14.]
- **Unloaded runs are never "missed".** If the runs RPC fails but the workouts RPC succeeds, dots render as "unknown" (dotted outline) with a banner "Runs didn't load, so some days may look empty. Try again." This stops a false red wall of misses.
- **"New since last visit" (C7.2)** counts runs, flags and replies. [UX ADDITION: also count goal changes and athlete changes to coach workouts, so the MVP digest items have a live home.] An athlete is "seen" when Dana opens their detail (T3), not when the Today list scrolls past them.

### A.5 States (T1, T2, T5)

| State | Treatment and exact copy |
|---|---|
| Loading, first ever | 4 skeleton rows with the header. No spinner over the whole screen. |
| Loading, refresh | Keep the current content and show the system refresh control. Rows don't jump. |
| Empty, 0 athletes | Illustration-free card: "No athletes yet" / "Share your invite link. Athletes show up here once they join." Button: "Share invite link" (existing `CoachInviteSection`). |
| Empty, athletes but none has a plan | Header "Nobody has a plan yet". Rows under "No plan yet" with "Waiting for a plan". |
| Nothing urgent (success / climax) | Header "You're caught up for today". Sub-line: "{n} on track · {m} rest days". On track stays collapsed. |
| Partial data | Runs failed: dots dotted, plus the banner above. Flags failed: banner "Pain flags didn't load. Try again." The flag group is not shown as empty. |
| Error, nothing cached | "Couldn't load your athletes." Button "Try again". |
| Error, cache exists | Cached list, plus a banner "Couldn't refresh · showing {time}". Button "Try again". |
| Offline | Cached list, plus a non-dismissable strip "Offline · updated {HH:mm}" (plan AC 4: "Updated …"). Mark handled and feedback queue with a "Waiting to sync" clock glyph. |
| Permission: push denied (coach) | One line in T5: "Notifications are off for RunSmart. Turn them on in Settings." Button "Open Settings". Never re-prompt. |
| Revoked link mid-session | The row disappears on refresh. If T3 is open: "{Athlete} is no longer linked to you." Button "Back to Today". |
| Athlete on an app build without v2 (mixed versions) | Row note "Effort, notes and flags aren't available. {Athlete} needs the latest RunSmart." [ASSUMPTION: needs a client-capability field; see G4.] |
| Flag-off (`coachV2Enabled` false) | T1 hidden. The existing roster (T7) is the Coach tab, exactly as in 1.2.6. |
| T2 filtered | Chip at the top: "Missed today · {n}" with a ✕ "Show all". If it's empty by the time Dana opens it (someone logged a run late): "Everyone on the 20:00 list has logged a run since." |
| T5 loading or saving | Toggles disabled with an inline spinner. On failure: "Couldn't save. Try again". The toggle reverts. |

### A.6 Key copy (exact strings)

| Where | String |
|---|---|
| T1 header line | "{n} athletes need you" / "1 athlete needs you" / "You're caught up for today" |
| Group headers | "Pain or something off ({n})", "Missed today ({n})", "Missed yesterday ({n})", "Behind this week ({n})", "New to review ({n})", "On track ({n})", "Rest today ({n})", "No plan yet ({n})" |
| Today status | "Not done yet", "Done {x} km", "Partial {x} of {y} km", "Missed", "Rest", "Extra run {x} km" |
| New marker | "{n} new" (C7.2) |
| Pain chip | "Pain" / "Something off". Flag note preview in the row: first 60 characters, coach-only. |
| T4 flag block | Title "Pain · {Mon d}" or "Something off · {Mon d}". The athlete's note is shown verbatim. Button "Mark handled". Secondary button "Write to {Athlete}". |
| Mark handled toast | "Marked handled · Undo" (5 s) |
| Resolved flag in T3 | "Handled by you · {Mon d}" |
| Push, run finished (C7.5) | "{Athlete} finished a {x} km run" (the plan's string). No pace, HR, effort, notes or flags. |
| Push, pain flag | "{Athlete} flagged something after a run". The body never says "pain" or names a body part (plan §3.6: no health detail). |
| Push, reply (C7.7) | "{Athlete} replied to your note" |
| Push, evening summary (C7.6) | "{n} athletes missed today's workout: {A}, {B}, {C}". With more than 3 names: "{A}, {B} and {k} more". |
| T6 pre-permission | Title "Know when your athletes run". Body "Get a ping when someone finishes a run or flags pain, and a summary at 20:00." Buttons "Turn on" / "Not now". |
| T5 settings | Section "Notify me when": "An athlete finishes a run", "An athlete flags pain or something off", "Evening summary at 20:00". Section "Quiet hours": "From 21:30", "To 07:00", footer "Pushes during quiet hours arrive when quiet hours end." |

### A.7 Edge cases

1. **Two coach phones, or iPhone plus a later iPad.** Seen-state is server-side (M3), so opening Yoni on one device clears the marker on the other after a refresh.
2. **Athlete in another time zone.** "Today" for the row follows the athlete's date. The header date follows the coach. If they differ, the row's second line is prefixed with the athlete's weekday: "Wed · Tempo 6 km".
3. **Imported runs (Garmin, HealthKit).** They count for dots. Imports older than 24 h don't trigger a push (plan C7.5) but do set "new".
4. **Several runs on one day.** Sum them against the planned workout using the existing "Matched by date" rule. The extra glyph appears only when nothing was planned.
5. **Flag without a run** (`run_id` null in M1). It's shown on the day it was created, with the chip "Something off".
6. **Multiple open flags.** The chip shows "Pain · 2". T3 lists both, and each has its own Mark handled.
7. **Athlete deletes the run that carried a flag.** The flag stays (it is health signal), shown on the day as "Run deleted".
8. **Athlete hides the note from the coach.** `has_note` is false. Dana sees nothing, with no "hidden" indicator (consistent with the MVP rule for hidden maps: don't reveal the athlete's privacy setting).
9. **Athlete leaves while a flag is open.** The row disappears and queued Mark handled actions fail softly (see the failure path).
10. **30 athletes** (plan AC 4). The list is lazy, and groups collapse beyond 8 rows with "Show all {n}".
11. **Undo of Mark handled.** The undo restores the open state locally. The RPC is delayed 5 s in the outbox, so no server "un-resolve" RPC is needed. [ASSUMPTION]

### A.8 Accessibility

- **Row as one element.** Each row is one VoiceOver element: "{Name}. {reason}. Today: {workout}, {status}. Last 7 days: {n} done, {n} partial, {n} missed, {n} rest. {n} new." Example: "Yoni. Pain flagged Sunday. Today: Tempo 6 km, not done yet. Last 7 days: 4 done, 1 partial, 0 missed, 1 rest. 2 new."
- **Per-day sentences (plan AC 4, "each dot is read as a sentence").** These sit on the dots strip as an **adjustable element**: swipe up or down to step through days, e.g. "Sunday 22 November: Long run 10 km, done 10.4 km." This avoids 7 stops × 20 rows.
- **Custom actions:** "Mark handled", "Write feedback", "Open {Name}".
- **Group headers** carry the header trait, so the rotor jumps between groups.
- **Dynamic Type at XXL and accessibility sizes.** The dots wrap to their own line, and the reason chip moves under the name. At AX3 and up, dots become a text line, "4 done · 1 partial · 1 rest", and are not shrunk.
- **Targets:** every chip and button is at least 44×44 pt. The row is the target, and the dots are not individually tappable.
- **Reduced motion:** no row animations on refresh. The "caught up" state is a plain cross-fade, or instant.
- **Color:** every state has a glyph and a text label (grammar table). Red is never the only signal.

### A.9 RTL-readiness notes

- Dots run oldest to newest from the **leading** edge, so they mirror in RTL. The week reads right-to-left in Hebrew.
- Chips trail the name.
- Swipe actions are on the **trailing** edge.
- Mixed-direction names and notes use natural alignment.
- Numbers ("6.2 km", "4 of 5") stay LTR runs inside RTL text.
- No hard-coded left/right in layout code.

### A.10 AC additions

- **C7.1**
  - (a) Glyph and label per state, as in the grammar table (not color-only).
  - (b) Group headers with counts, in the order in A.3.
  - (c) The "Missed today" cutoff rule.
  - (d) Failed runs data renders "unknown", never "missed".
  - (e) No re-sort while visible.
  - (f) The XXL/AX layout rules in A.8.
  - (g) Empty, caught-up, offline, error and partial states with the A.5 copy.
  - (h) Flag-off shows the 1.2.6 roster unchanged.
  - (i) The design works before C7.4 ships: the pain group is simply absent.
- **C7.2**
  - (a) Seen = opening athlete detail, synced server-side.
  - (b) The "new" dot is always paired with "{n} new" text.
  - (c) [UX ADDITION] Goal changes and athlete changes to coach workouts count as "new".
- **C7.4 (coach side)**
  - (a) Mark handled has a 5 s undo.
  - (b) A resolved flag shows "Handled by you · {date}".
  - (c) Multiple flags are listed separately.
  - (d) The push carries no health words.
- **C7.5**
  - (a) Settings copy as in A.6.
  - (b) A denied-permission state with "Open Settings".
  - (c) A pre-permission card before the system prompt.
- **C7.6**
  - (a) Tap opens T2 with a clear filter and a "Show all" control.
  - (b) If T2 is already empty when opened, use the A.5 copy.

---

## B. Coach workout builder (C8.2, C8.3, C8.4, C8.9, C8.10, C8.11)

### B.1 Flow B: Dana sets Tuesday track night for the group (Dana, Sunday evening on the couch, about 20 minutes)

1. Dana opens Yoni → **Plan** tab. The 4-week calendar (C8.9) shows this week and the next 3. RunSmart workouts have no glyph, and her own have a lock.
2. She taps next **Tuesday** → "Add workout". The editor sheet opens with the date preset to "Tue 1 Dec".
3. She picks **Intervals**, and the step builder appears, prefilled with a starter structure:
   - Warm-up 15 min easy
   - Repeat 6 × (Run 800 m, Recover 90 s jog)
   - Cool-down 10 min easy
4. She sets the work pace to "3:50–4:00 /km". The preview line updates: **"About 8.5 km · 52 min"**. Beneath it: "Yoni sees: Warm-up 15 min · 6 × 800 m at 3:50–4:00 /km, 90 s jog · Cool-down 10 min".
5. She adds a note ("Stay relaxed on the first two"), taps **Save**, then in the overflow menu taps **Save as template**, named "Track 6×800".
6. From **Templates**, she taps "Track 6×800" → **Assign** → date "Tue 1 Dec" → selects "All athletes". The review says: **"Add for 10 athletes. Replaces their planned workout that day. 2 can't get it: Noa (no plan yet), Avi (already has your workout that day)."**
7. She taps **Add for 10**. Result: **"Added for 10. Skipped 2."**, with each skipped name and a reason.
8. **Climax:** Tuesday evening, her Today shows ten "Done" dots on the track workout. Yoni's run detail says "Done 6 × 800 m · avg 3:56 /km" [needs splits; see G11], and Yoni's live-run guide called out "Rep 3 of 6" the whole way.

**Failure path.** Dana drags Thursday's tempo onto Friday, but Friday already has a RunSmart easy run. A sheet asks "Friday already has Easy 5 km. **Swap days** / **Replace it** / Cancel". She picks Swap, and the toast reads "Moved to Friday · Undo".

### B.2 Screen inventory (builder)

| ID | Surface | Reached from | Purpose | Story |
|---|---|---|---|---|
| B1 | Athlete calendar (this week + next 3) | Athlete detail → "Plan" | See and rearrange 4 weeks | C8.9 |
| B1a | Agenda view (vertical list by week) | B1 at XXL type, or the "List" toggle | Same data, readable at large type | C8.9 AC 4 |
| B2 | Workout editor (sheet) | B1 day → "Add workout"; chip → "Edit"; Templates → "New" | Create or edit a simple workout | C8.2, C8.4 |
| B3 | Step builder (inside B2 when type = Intervals or Tempo-structured) | B2 | Warm-up, work, recover, cool-down, repeats | C8.3 |
| B4 | Step editor (sheet over B3) | Tap a step | One step's target | C8.3 |
| B5 | Move picker | Chip context menu "Move to…"; drag fallback | Pick a new date | C8.4, C8.9 |
| B6 | Conflict sheet | Move or assign onto an occupied day | Swap / Replace / Cancel | C8.4, C8.11 |
| B7 | Delete confirm | Chip menu "Delete" | Confirm | C8.4 |
| B8 | Templates list | Coach tab → "Templates"; B2 → "Add from template" | Search, edit, delete, assign | C8.10 |
| B9 | Assign flow, 3 steps (workout → date → athletes) plus review | B8 "Assign"; Coach tab "+ Workout for several athletes" | Add to many athletes | C8.11 |
| B10 | Assign result | After B9 | Who got it and who was skipped, and why | C8.11 |
| B11 | Edit-conflict banner | Save returns `edit_conflict` | Resolve | C8.4 AC 3 |
| B12 | Read-only workout (past or completed) | Tap a past chip | Planned vs actual | existing detail |

### B.3 B1 calendar behavior

- **Layout.**
  - Default: one row per week, labeled "This week" / "Next week" / "Week of {d Mon}", with 7 day cells.
  - Each cell holds one chip: a type icon, a short metric ("6 km", "45 min", "6×800"), a lock glyph if it's a coach workout, and a completion glyph for past days.
  - Today's cell has an outline.
  - Past days are dimmed and read-only.
- **Agenda switch.** At Dynamic Type XL and up, or by the toolbar toggle "List", the view switches to B1a: one row per day, "Tue 1 Dec · Intervals 6×800 m · Set by you".
- **Interactions:**
  - Tap a chip to open B2 (editable) or B12 (past or completed).
  - Tap an empty future cell for "Add workout".
  - Long-press a chip for a context menu: "Edit", "Move to…", "Duplicate to…", "Save as template", "Delete".
  - Long-press-drag a future chip to another future cell (C8.9 AC 2), with a light haptic on pickup and on drop.
  - Dropping onto an occupied cell opens B6. Dropping onto a past cell isn't possible: it snaps back with "Can't move to a past day".
- **Range.** Today through today+27. Drafted future weeks beyond that are reached through Draft review (C).
- **Pending sync.** A chip shows a clock glyph and "Waiting to sync" until the outbox flushes. The athlete doesn't see it until then.

### B.4 B2 editor: fields, defaults, validation

| Field | Control | Default | Validation (exact message) |
|---|---|---|---|
| Date | Date picker, today…+27 (or plan end) | The tapped day | "Pick today or a later day" |
| Type | Segmented / menu: Easy, Long, Tempo, Intervals, Recovery, Race, Rest | Easy | none |
| Target | Segmented "Distance" / "Time" | Distance | Distance 0.5–50 km: "Enter a distance between 0.5 and 50 km". Time 5 min–5 h: "Enter a time between 5 minutes and 5 hours". |
| Pace range (optional) | Two pace wheels "from" / "to", per km | Empty, labeled "Any pace". [ASSUMPTION: show "Easy pace" if the athlete's easy pace is known.] | "The faster pace should come first" when from > to |
| Note to {Athlete} (optional) | Multiline, ≤500 [ASSUMPTION; reuse the `notes` column] | Empty | Counter appears at 450. Over 500 blocks Save: "Keep notes under 500 characters". |
| Steps | B3, when type = Intervals (or "Add steps" on Tempo/Long) | Starter structure (B.1 step 3) | See B3 |

- **Header:** "New workout for {Athlete}" or "Edit {weekday}'s workout".
- **Primary action:** "Save" (disabled until valid). Secondary: "Cancel". Swipe-down with unsaved changes asks "Discard changes?" (Discard / Keep editing), as in the MVP sheet rule.
- **Editing a RunSmart workout** shows the inline line "Saving makes this your workout. RunSmart won't change it." (C8.4 AC 1: saving sets the lock). [UX ADDITION]
- **Editing today's workout:** "{Athlete} may already be out running. Changes show on their next refresh."
- **Rest type** hides the target and pace fields. The note stays.
- **Units** follow the app's unit setting. [ASSUMPTION: km in the pilot.]

### B.5 B3 step builder (C8.3)

- **Step kinds:**
  - **Warm-up**, **Run** (work), **Recover** (jog, walk or stand), **Cool-down**.
  - **Repeat** block (2–30 times). It contains one or more steps, with no nested repeats in v2. [ASSUMPTION; confirm against the existing `workout_structure` shape, the plan's VERIFY.]
- **Each step:** distance or time, plus an optional pace range. Recover adds a kind (Jog / Walk / Stand).
- **List display** (start-aligned, top to bottom):

      Warm-up · 15 min · easy
      ┌ Repeat 6×
      │  Run · 800 m · 3:50–4:00 /km
      │  Recover · 90 s · jog
      └
      Cool-down · 10 min · easy

- **Add:** "Add step" (menu: Warm-up, Run, Recover, Cool-down, Repeat).
- **Reorder:** drag handles, plus VoiceOver custom actions "Move up" / "Move down".
- **Delete:** swipe a step, with undo in the toast.
- **Preview (C8.3 AC 2):** "About {x} km · {y} min".
  - If any step has no pace, use the athlete's easy pace for estimating and mark it: "About 8.5 km · about 52 min (estimated with Yoni's easy pace)".
  - If no pace is known at all: "About 8.5 km · time depends on pace".
- **Athlete-facing text summary,** also written to the text field old clients and the text-parsing guide read [UX ADDITION, needed for mixed versions and the `StructuredWorkoutFactory` fallback]: "Warm-up 15 min · 6 × 800 m at 3:50–4:00 /km, 90 s jog · Cool-down 10 min". It's shown read-only under the preview as "{Athlete} sees:".
- **Validation:**
  - "Add at least one Run step"
  - "A repeat needs at least one step"
  - "Repeats must be between 2 and 30"
  - "This workout is over 4 hours. Check the steps." (soft warning; Save is still allowed)
- **Starter templates in the add menu:** "Intervals (6 × 800 m)", "Tempo (20 min)", "Run–walk (8 × 1 min run, 1 min walk)". Run–walk is beginner-first. [UX ADDITION; it serves the beginner pilot population]

### B.6 Move, delete, undo, conflicts (C8.4, C8.9)

- **Move (B5):** a date picker, today…+27. On save, the toast says "Moved to {weekday} · Undo".
- **Conflict (B6)** when the target day has a workout:
  - Title "{Weekday} already has {type} {metric}"
  - Buttons: "Swap days" (default), "Replace it", "Cancel".
  - If the occupant is a **completed** workout or a past day, the drop isn't offered.
  - If the occupant is a **coach** workout, "Replace it" reads "Replace your {type}".
  - [ASSUMPTION: one workout per day. Two-a-days are v2+. Confirm the `workouts` table allows only one row per date per plan in practice.]
- **Delete (B7):**
  - "Delete {weekday}'s {type} for {Athlete}?" / "{Athlete} will see a rest day." Buttons "Delete" (destructive) and "Cancel".
  - Then a toast "Deleted · Undo" (5 s).
  - The deleted day shows to the athlete as "Rest (from {Coach})". [ASSUMPTION; otherwise RunSmart could fill the gap, which contradicts the lock intent.]
- **Undo.** For move, delete and swap, it is client-side: the outbox holds the RPC for 5 s. [ASSUMPTION; no server undo RPC.] After the 5 s window, undo is by editing again. Edits have no undo; Cancel before saving is the undo.
- **Edit conflict (B11)**, when `edit_conflict` comes back (stale revision): banner "This workout changed on another phone." (plan string), with buttons "Load latest" (discards the local edit after showing what changed) and "Keep mine" (re-saves against the new revision). [ASSUMPTION: "Keep mine" is allowed, since there is only one coach per athlete and the conflict is with herself.]
- **Athlete completed it while Dana was editing.** Save returns past/completed, and the copy is: "{Athlete} already ran this workout, so it can't be changed."

### B.7 Templates (C8.10) and assign (C8.11)

- **B8 list:**
  - Search field "Search templates".
  - Rows: name, summary ("6 × 800 m · about 52 min").
  - Swipe actions: "Assign", "Delete". Tap opens the editor.
  - Empty state: "No templates yet" / "Save any workout as a template from its ⋯ menu."
  - No search results: "No templates match '{q}'."
- **Template edits** apply to future assignments only. The editor footer says: "Changes apply to workouts you add from now on. Workouts already given to athletes don't change."
- **Delete template:** "Delete '{name}'? Workouts you already added stay as they are."
- **B9 assign:**
  1. Workout: template or "New workout" (B2 inline).
  2. Date.
  3. Athletes: "Select all" plus group chips (after C8.14), then rows with eligibility labels computed before submit:
     - "Can't add: no plan yet"
     - "Can't add: already has your workout that day"
     - "Can't add: already ran that day"
     - "Replaces: Easy 5 km" for eligible athletes with a RunSmart workout that day.

     Ineligible rows are shown but not selectable, with the reason as text.
  4. Review: "Add '{name}' on {weekday d Mon} for {n} athletes. It replaces their planned workout that day." Button "Add for {n}".
- **Pace for many athletes** [CONFLICT with "each athlete at their own level" (MVP thin group plan); see G9]. When more than 1 athlete is selected and the workout has pace targets, the review warns: "One pace range for everyone. Beginners may find {pace} too fast." [ASSUMPTION; until effort-based targets exist, recommend effort words ("easy", "comfortably hard", "hard") as a pace-free option.]
- **B10 result** (all-or-nothing per C8.11 AC 2):
  - Success: "Added for {n}. Skipped {k}.", then a list of skipped athletes with reasons and an "Open {Athlete}" action.
  - Failure: "Couldn't add the workout. Nothing changed for anyone. Try again."
- **Push to athletes** for an assign: exactly one per athlete, batched with any other plan changes (see C.6).

### B.8 States (builder)

| Surface | Empty | Loading | Error | Offline | Partial / other |
|---|---|---|---|---|---|
| B1 calendar | Athlete has no plan: "{Athlete} doesn't have a plan yet." Buttons "Draft a plan with AI" (C8.6) / "Add a workout" | Skeleton weeks | "Couldn't load {Athlete}'s plan. Try again" | Cached plus "Offline · changes will sync". Edits queue with the clock glyph. | Plan ends before 4 weeks: weeks after the end show "Plan ends {date}" |
| B2 editor | n/a | Save: button spinner | Validation inline; server: "Couldn't save. Try again" (draft kept) | Save queues: toast "Saved on this phone. It'll reach {Athlete} when you're online." | Link revoked on sync: banner "{Athlete} is no longer linked. This change wasn't saved." with "Discard" |
| B3 steps | Starter structure, never empty | n/a | Validation | Same as B2 | Unknown legacy structure from AI workouts: show the text summary read-only plus "Rebuild as steps" |
| B8 templates | See B.7 | Skeleton rows | "Couldn't load templates. Try again" | Cached, read-only: "Templates can be edited when you're online" [ASSUMPTION] | n/a |
| B9/B10 assign | No eligible athletes: "No one can get this workout on {date}." with reasons | "Adding for {n}…" (blocking, ≤10 s) | See B.7 | Blocked: "Adding to several athletes needs a connection." [ASSUMPTION: no outbox for multi-assign; all-or-nothing needs the server.] | Some ineligible: listed in review and result |

### B.9 Accessibility (builder)

- **Every drag has a non-drag path:** "Move to…" in the context menu and as a VoiceOver custom action on each chip (C8.9 drag).
- **Chip label:** "Tuesday 1 December. Intervals, 6 by 800 meters. Set by you, locked. Not started." Completed: "Done, 8.4 kilometers."
- **Step rows** read as sentences: "Repeat 6 times: run 800 meters at 3 minutes 50 to 4 minutes per kilometer, then recover 90 seconds jogging." The repeat block is a container, so VoiceOver can enter and exit it.
- **Pace wheels** have adjustable labels: "From pace, 3 minutes 50 seconds per kilometer".
- **Large type.** The calendar switches to agenda at XL and up. The editor is a single column, and the preview line wraps.
- **Targets:** at least 44 pt for chips, step rows, steppers and the drag handle.
- **Reduced motion:** the drag lift shadow is kept, but no spring animations. The undo toast stays at least 5 s, and while VoiceOver is on it stays until dismissed or the next action. [ASSUMPTION]
- **Toasts** are announced via VoiceOver announcement.

### B.10 RTL-readiness notes (builder)

- The week grid runs from the leading edge, so day order mirrors in RTL.
- The repeat bracket sits on the leading edge.
- Pace "3:50–4:00 /km" and "6 × 800 m" are LTR runs inside RTL text.
- Drag direction is semantic: "next day" is trailing.
- Context menus are not affected.

### B.11 AC additions

- **C8.2**
  - (a) Field set, defaults and validation strings per B.4.
  - (b) An offline save shows "Waiting to sync" on the chip, and the toast copy.
  - (c) Editing a RunSmart workout shows the lock line.
  - (d) A text summary is written for old clients.
  - (e) Rest type hides targets.
- **C8.3**
  - (a) Step kinds and repeat limits per B.5.
  - (b) The estimate rule when pace is missing.
  - (c) An "{Athlete} sees:" line.
  - (d) VoiceOver sentences and reorder actions.
  - (e) The run–walk starter.
- **C8.4**
  - (a) Swap / Replace / Cancel on occupied days.
  - (b) 5 s undo for move, delete and swap.
  - (c) A deleted day shows "Rest (from {Coach})" to the athlete.
  - (d) Copy for the completed-meanwhile case.
  - (e) "Load latest" / "Keep mine" on `edit_conflict`.
  - (f) [CONFLICT] The 48 h "Updated by {Coach}" marker vs the MVP's permanent "Edited by {Coach}" tag. See G7.
- **C8.9**
  - (a) Agenda view at XL and up, or by toggle.
  - (b) A "Move to…" non-drag path.
  - (c) Past cells are not drop targets.
  - (d) Pending-sync glyph.
- **C8.10**
  - (a) Template edits don't touch assigned workouts, and the copy says so.
  - (b) Empty and no-results states.
- **C8.11**
  - (a) Eligibility shown before submit, with reasons.
  - (b) "Replaces: …" per athlete.
  - (c) A one-pace warning when assigning to more than 1 athlete.
  - (d) No offline multi-assign.
  - (e) One batched athlete push.

---

## C. AI draft → coach review/edit → publish, and the athlete side (C8.6, C8.7, C8.8, C8.5, C7.9, C7.7, C7.3, C7.4, C7.8)

### C.1 Flow C1: Dana drafts Yoni's 10K plan (Dana, Sunday evening, about 15 minutes)

1. In Yoni's detail → Plan, Dana taps **"Draft a plan with AI"**.
2. The setup sheet is prefilled from Yoni's goal or group settings: goal "10K", race date "15 Mar", runs per week "3", level "Beginner", start "Tomorrow, Mon 23 Nov". Then she taps **Draft plan**.
3. The progress card reads "Drafting Yoni's plan… this can take up to a minute. You can leave this screen." She checks Today while it runs.
4. The "Draft ready" banner appears on Yoni's row and in the detail. The **Draft review** opens with the header strip **"Draft · Yoni can't see this"**, then week cards: "Week 1 · 3 runs · 12 km", and so on.
5. She opens week 3, changes Thursday to her "Run–walk 8 × 1 min" template, and deletes a Saturday long run. The edited workouts get a "Your change" marker inside the draft.
6. She taps **Review and publish**. The summary sheet (C8.7 AC 2) reads:
   **"Publish to Yoni?** 12 weeks · 46 workouts · starts Mon 23 Nov. Replaces 18 upcoming workouts. Completed runs stay as they are. Yoni gets a notification."
   Below it, a **"This week for Yoni"** before/after list: "Tue: Easy 5 km → Easy 4 km", "Thu: Tempo 5 km → Run–walk 8 × 1 min".
7. She taps **Publish to Yoni**. A success haptic, then: "Published. Yoni sees it now."
8. **Climax:** Monday morning, Yoni's Today shows "Dana updated your plan · 2 changes this week". His Plan header reads "Dana's plan: 10K". In Dana's detail, the plan carries "Published Sun 22 Nov · version 1".

**Failure path.** The AI draft fails: "Couldn't draft. Try again" (plan string), with nothing written. On the third failure in a row: "Still not working. You can build the plan yourself from the calendar."

### C.2 Flow C2: Yoni lives with Dana's plan (Yoni, a beginner, weeks 1–3)

1. Yoni taps the push "Dana updated your plan". The Today card opens a **change list** for the next 7 days, then "Got it".
2. On Thursday's workout he sees **"From Dana"**, a lock labeled "Set by Dana", Dana's note in her words, and the steps: "Run 1 min, walk 1 min · 8 times". The live-run guide follows the steps.
3. After the run, the summary asks **"How hard was it?"** (1–10). Under it is the line "Shared with Dana" (eye glyph). Next comes the **"Something off?"** row: he taps it, picks **Pain**, and writes "left knee, last 2 reps". A footer reads "Dana will see this. If the pain is sharp or doesn't go away, check with a doctor or physio."
4. He asks RunSmart "can you move Saturday's long run?" The reply is: **"That's Dana's workout."**, with a link "Read Dana's note".
5. Wednesday: Dana's note "Take Wednesday as rest; we'll look Thursday" arrives, and he taps **Reply**: "Thanks, knee feels better today". The note shows his reply beneath it, marked "Sent".
6. **Climax:** his run shows **"Dana saw this"** under the flag (after Dana marked it handled). The run's status line says "Dana will review this run", and a day later "Dana on your Thursday run".

**Failure path.** He tries to change his goal to a half marathon and gets the sheet: **"Ask Dana to change your plan"** (C8.5 AC 4). See C.5 for the exact copy, and the [CONFLICT] in G3.

### C.3 Screen inventory (draft → publish, athlete side)

| ID | Surface | Reached from | Purpose | Story |
|---|---|---|---|---|
| D1 | Draft setup sheet | B1 empty state; athlete detail → Plan → "Draft a plan with AI" | Inputs for the AI | C8.6 |
| D2 | Drafting progress (card, in place) | D1 | Long wait, leavable | C8.6 |
| D3 | Draft review (week list → week detail) | D2 done; "Draft ready" banner; athlete detail | Edit before publishing | C8.7 |
| D4 | Publish summary sheet | D3 "Review and publish" | Informed consent for the change | C8.7 AC 2 |
| D5 | Published versions (light) | Athlete detail → Plan → "Versions" | See what's live and when | C8.7 AC 4 [UX ADDITION] |
| P1 | Athlete Plan header | Plan tab | "{Coach}'s plan: {title}" | C8.8 |
| P2 | Today plan-update card plus change list | Today; push `athletePlanPublished` | What changed | C8.8 |
| P3 | Locked workout detail | Plan / Today | "From {Coach}", note, steps, lock | C8.8, C8.5 |
| P4 | AI lock reply | RunSmart chat / flex-week | "That's {Coach}'s workout" | C8.5, C8.8 AC 4 |
| P5 | Goal-change sheet (Phase 1 warning, then the Phase 2 block) | Goal wizard; "Build my plan" | Warn or redirect | C7.9, C8.5 |
| P6 | Reply under a coach note | Feedback card / run detail | One-level reply | C7.7 |
| P7 | Post-run effort, note and "Something off?" | Run summary; run detail | Share how it felt | C7.3, C7.4 |
| P8 | Join consent (v2 copy) | Join link | Opt-in | C7.8 |
| P9 | One-time sharing notice (existing athletes) | Today, first open after update | Re-consent | C7.8 |
| P10 | Athlete push pre-permission | After P8/P9 | Reach the athlete | C7.10 |

### C.4 Coach side: D1–D5 details

**D1 setup.**
- Fields (prefilled, all editable):
  - Goal (5K / 10K / Half / Marathon / General fitness), with the race date optional for "General fitness".
  - Runs per week (2–6).
  - Level (Beginner / Intermediate / Advanced).
  - Start date (default: tomorrow; options: Tomorrow, Next {week-start day}, Pick a date).
  - Optional "Notes for RunSmart": "e.g. knee history, prefers mornings", ≤300 characters. [PROPOSED; drop it if the prompt contract forbids free text.]
- Constraints shown inline:
  - "Plans can be up to 16 weeks." (`GroupPlanRules`)
  - Race too soon: "{Goal} needs at least {n} weeks. Pick a later race date or a shorter goal." (per-distance minimums)
- Button: "Draft plan". Sub-line: "{k} of {N} AI drafts left today" (C8.6 AC 5).

**D2 progress.**
- Inline card on the athlete detail with indeterminate progress: "Drafting {Athlete}'s plan… this can take up to a minute. You can leave this screen."
- When it's done while Dana is elsewhere in the app: an in-app banner "{Athlete}'s draft is ready · Review".
- When the app is backgrounded: no push to the coach [ASSUMPTION]. The draft is waiting the next time she opens the app.

**D3 review.**
- Header strip (persistent, not color-only, with an eye-slash glyph): "Draft · {Athlete} can't see this".
- Week cards: "Week {n} · {dates} · {runs} runs · {km} km". Phase labels come from `training_phase` when present ("Base", "Build", "Taper").
- Tapping a week opens 7 day rows using the same chips and editor as B1 and B2 (C8.7 AC 1).
- Edited items carry the marker "Your change". The AI's own items have no marker.
- Toolbar:
  - "Review and publish" (primary).
  - Overflow menu: "Redraft with AI" (uses one draft from the daily cap; confirm "Redraft? Your changes to this draft will be lost."), "Discard draft" (confirm "Discard this draft? {Athlete}'s current plan doesn't change.").
- **One open draft per athlete** [ASSUMPTION]. Starting a new draft while one exists asks "You already have a draft for {Athlete}. Open it / Start over".
- Drafts persist across sessions. Draft edits **need a connection** (consistent with the MVP assumption "draft edits blocked offline").

**D4 publish summary.**

| Line | Copy |
|---|---|
| Title | "Publish to {Athlete}?" |
| Scope | "{w} weeks · {n} workouts · starts {weekday d Mon}" |
| Replaces | "Replaces {k} upcoming workouts." If any of those were the coach's own earlier workouts: "Including {j} you set before." |
| Kept | "Completed runs stay as they are." |
| Athlete-edited items [depends on G2] | "{m} workouts {Athlete} changed will be replaced." |
| Next 7 days diff | List "Tue: Easy 5 km → Easy 4 km" (max 7 rows; "No changes this week" if none) |
| Notify | "{Athlete} gets a notification." [ASSUMPTION per Q6: always one push per publish] |
| Buttons | "Publish to {Athlete}" (primary) / "Keep editing" |
| Success | Toast "Published. {Athlete} sees it now." Success haptic. |
| Error | "Couldn't publish. Nothing changed for {Athlete}. Try again." (atomic, C8.7 AC 5) |
| Stale | `p_revision` mismatch: "This draft changed on another phone. Load latest." |
| Link gone | "{Athlete} is no longer linked to you, so this draft can't be published." Button "Discard draft" |

**Publish-time rules:**
- **Start date.** Workouts before the start date stay as they are. If start = today and today's workout is already completed, today is kept.
- **Plan changed since drafting.** If the athlete's plan changed after the draft was made (a goal change, or a run completed on a day the draft changes), show the banner "{Athlete}'s plan changed since this draft. Check this week before publishing." [ASSUMPTION]

**D5 versions.** A list: "Version 2 · published Sun 22 Nov · live", "Version 1 · published 8 Nov · replaced". Read-only, with no revert in v2. [ASSUMPTION; revert = draft from version is v2+.]

### C.5 Athlete side: P1–P10 details and exact copy

| Surface | Copy and behavior |
|---|---|
| P1 Plan header | "{Coach}'s plan: {title}" (C8.8 AC 1). Sub-line "Race {d Mon} · Week {n} of {w}". "Coached by {Coach}" with avatar stays. |
| P2 Today card | "{Coach} updated your plan · {n} changes this week" (MVP string, extended). With no changes in the next 7 days: "{Coach} updated your plan". Tap opens the change list ("Thu: Tempo 5 km → Run–walk 8 × 1 min"). Button "Got it". C8.8's "Plan updated by {Coach}" is replaced by the MVP string for consistency. [UX choice; flag to the plan owner] |
| Athlete push, publish | "{Coach} updated your plan" → P2. At most one per publish, batched with single-workout changes within 10 min (see C.6). |
| P3 workout tags | Created by the coach: "From {Coach}". RunSmart workout edited by the coach: "Edited by {Coach}". Lock glyph with the label "Set by {Coach}". Recently changed (48 h, C8.4 AC 4): a "New" or "Updated" pill next to the permanent tag, not replacing it. [See G7] |
| P3 coach note | Shown verbatim, signed "— {Coach}", collapsed after 3 lines with "More". |
| P3 steps | "Warm-up 15 min · easy", "6 × (800 m at 3:50–4:00 /km · 90 s jog)", "Cool-down 10 min". The total line comes from the coach preview. |
| P3 actions on locked rows (C8.5 AC 3) | Hidden: "Move", "Push to tomorrow", "Remove", "Swap". Kept: "Start run". [CONFLICT: MVP lets the athlete change it with a confirm. See G2. Recommended default: keep "Skip this one" and "Move to another day" with the confirm "{Coach} set this workout. Change it anyway? {Coach} will see the change.", tag "Changed by you", coach digest line.] |
| P4 AI lock reply | "That's {Coach}'s workout." plus the link "Read {Coach}'s note" (only when a note exists). Nothing else: no offer to change it, no "ask in chat". |
| P5 Phase 1 warning (C7.9) | Title "Change your goal?" Body "{Coach} set your plan. Changing your goal replaces {k} workouts {Coach} set, and {Coach} will see the change." Buttons "Change anyway" / "Cancel". The count is mandatory (MVP FR-2e test). Group plan variant: "{Coach} set your group's plan. Changing your goal gives you your own plan and {Coach} will see the change." |
| P5 Phase 2 block (C8.5 AC 4; also on `plan_locked_by_coach`) | Title "Ask {Coach} to change your plan". Body "{Coach} manages your goal and plan. To change your race, date or runs per week, ask {Coach}." Buttons: "Reply to {Coach}'s latest note" (only if one exists, opens P6) / "OK". [CONFLICT with the MVP goal-change rule and with "no contact destination"; see G3] |
| P6 reply | Under a note: the "Reply" button. Composer placeholder "Reply to {Coach}…", limit 1000, counter from 900, Send. After send, the reply shows under the note: "You · {time}" with "Sent" or "Waiting to send" (outbox). [ASSUMPTION: the athlete may add several replies to one note; no edit or delete in the pilot.] The coach replies by writing a new note (no reply-to-reply, C7.7 AC 4). After leaving: the reply button is hidden, and the note and replies stay read-only (C7.7 AC 5). |
| Athlete push, new note (C7.7 AC 3) | "{Coach} left you a note" → the note. Never the note text. |
| P7 effort | "How hard was it?" 1–10, labels at 1 "Very easy", 5 "Steady", 10 "All out" (reuse the existing `RPESelector` labels if they exist). Visibility line under it: "Shared with {Coach}" with an eye glyph (only when linked plus v2). |
| P7 note | Field "Note" with the helper "{Coach} can see your note." Toggle "Hide note from {Coach}" (C7.3 AC 4), next to the existing "Hide map from {Coach}". |
| P7 "Something off?" (C7.4) | Collapsed row "Something off?". Expanded: chips "Pain" / "Something else", an optional field "What's going on? (optional)" ≤500, button "Send to {Coach}". After sending: "Sent to {Coach}" plus the safety line "If the pain is sharp or doesn't go away, check with a doctor or physio." (MVP voice rule 7). An unhandled flag can be removed: "Remove flag". After the coach marks it handled: "{Coach} saw this". Never "{Coach} will call you" or any response-time promise. |
| Post-run status (MVP) | "{Coach} will review this run" → after 72 h without feedback: "Shared with {Coach}". |
| P8 join consent v2 (C7.8 AC 1) | See below. |
| P9 one-time notice (C7.8 AC 2) | See below. |
| P10 athlete pre-permission | Title "Get {Coach}'s notes and plan updates". Body "We'll only notify you when {Coach} writes to you or changes your plan." Buttons "Turn on" / "Not now". |

**P8 join consent, v2 copy.** It extends the MVP A3 screen, keeping its structure and the "If you leave" sentence:

> **Share with {Coach}?**
> {Coach} can see:
> • Your training plan
> • Your runs: distance, time, pace and average heart rate
> • Route maps of runs you record in RunSmart, with the start and end trimmed for privacy
> • How hard each run felt (effort 1–10)
> • Notes you add to your runs. You can hide any note from {Coach}.
> • Pain or "something off" flags you send
>
> {Coach} can also set and change your upcoming workouts. RunSmart won't change workouts {Coach} sets.
>
> Not shared: your chats with RunSmart, and health data such as sleep or HRV.
>
> If you leave, {Coach} will no longer see your runs. You keep any feedback {Coach} has already given you. You can leave anytime in Settings.
>
> [ Share ]  [ Not now ]

[ASSUMPTION: whether "{Coach} can see when you read their messages" must be added depends on C8.12's read counts. Recommended: add it when C8.12 ships. See G12.]

**P9 one-time notice for existing athletes:**

> **{Coach} can now see how your runs felt**
> From now on, {Coach} can see:
> • How hard each run felt (effort 1–10)
> • Notes you add to runs. You can hide any note from {Coach}.
> • Pain or "something off" flags you send
>
> Notes you wrote before today stay on this phone.
> [ OK ]  [ Leave {Coach} ]

- Both buttons are the same size, with no pressure styling (MVP leave rules).
- "Leave {Coach}" opens the existing leave sheet (A13), not an instant leave.
- The "Notes you wrote before today stay on this phone" line holds only if Q8's recommended default is taken (no note backfill). If RPE is backfilled, add: "Effort from your last 14 days is shared too."
- **Sync gate:** no sharing of effort or notes until the notice is acknowledged (`ack_coach_consent(2)`). [UX ADDITION; see G5]

### C.6 States (draft → publish, athlete side)

| Surface | Empty | Loading | Error | Offline | Partial / other |
|---|---|---|---|---|---|
| D1 | n/a (prefilled). No goal known: fields empty with the hint "Pick a goal for {Athlete}". | n/a | Cap reached: "You've used today's {N} AI drafts. Try again tomorrow, or build the plan yourself." | "Drafting needs a connection." (button disabled) | Group target: see G8 |
| D2 | n/a | Indeterminate card (≤60 s typical) | "Couldn't draft. Try again" (plan string). Third failure in a row adds the "build yourself" line. | Lost connection mid-draft: the server keeps going, and the card says "We'll show the draft when you're back online." | Over 90 s: "Taking longer than usual. You can leave; we'll keep it." |
| D3 | Draft with 0 workouts is impossible (validation). An all-weeks-deleted draft can't publish: "Add at least one workout to publish." | Skeleton weeks | "Couldn't load the draft. Try again" | Read-only from cache with "Editing a draft needs a connection." | Stale-plan banner (C.4) |
| D4 | n/a | "Publishing…" (blocking, ≤10 s) | Atomic error copy | Publish disabled: "Publishing needs a connection." | Link gone / stale revision copy |
| P2 | No card when nothing was published | n/a | n/a | Card shows after the next sync | Multiple publishes before Yoni opens the app: one card covering the latest version, changes compared with what Yoni last saw [ASSUMPTION] |
| P3 | n/a | Existing | Workout removed by the coach while open: "{Coach} changed this workout. See the latest." | Cached workout; edits by the coach arrive on sync | Structure unreadable (newer format): show the text summary |
| P6 | n/a | Send spinner | "Couldn't send. We'll try again." (outbox) | "Waiting to send" | Link revoked before flush: "You're no longer linked to {Coach}, so this reply wasn't sent." |
| P7 | n/a | n/a | Flag fails: outbox retry, "Waiting to send" | Queued | Run has no server row (C7.3 "only runs with a server row"): hide the visibility line and "Something off?" falls back to a run-less flag with the note "about today's run" [ASSUMPTION] |
| P8/P9 | n/a | n/a | Ack fails: notice shows again next open | Notice waits for a connection | Coach not on v2: hide the new bullets [see G4] |

**Notifications and batching (athlete).**
- A coach's single-workout edits (C8.2, C8.4) and assigns (C8.11) go live immediately per the plan.
- The athlete push is **debounced**: one "{Coach} updated your plan" push, 10 minutes after the coach's last change to that athlete, covering all changes. [ASSUMPTION; prevents 6 pushes during one editing session.]
- Athlete pushes respect the athlete's own quiet hours (`notification_prefs` is per user). [ASSUMPTION; the plan only defines coach quiet hours in C7.5.]

### C.7 Edge cases

1. **Coach publishes while Yoni is mid-run on today's workout.** The run completes against the workout it started with. Publish never touches completed rows, and today is untouched unless the coach chose start = today and it's not completed. The run still links by date.
2. **Yoni completed a workout the draft moves.** The completed row is kept, and the draft's workout on that day is skipped with the D4 note "1 workout skipped: {Athlete} already ran on Tue".
3. **Re-publish (C8.7 AC 4)** replaces coach workouts from the previous version, including single edits Dana made after version 1, unless the new draft started from the live plan. Recommendation: **"Draft a new version" starts from the live published plan, not from a fresh AI draft** ("Edit plan" vs "Redraft with AI"). See G10.
4. **Yoni leaves with a draft open.** Publish shows the link-gone copy, and the draft is kept for 30 days and then purged. [ASSUMPTION; purge on account deletion per the plan.]
5. **Yoni changes his goal (Phase 1, C7.9) while Dana is reviewing a draft.** The stale-plan banner appears. On publish, Dana's plan wins, and "Custom goal" disappears.
6. **Athlete on the App Store build (flag off) gets a published plan.** They see the workouts as ordinary workouts:
   - no "From {Coach}" tag
   - steps are visible only via the text summary
   - edits are silently reverted by the trigger
   - deletes error

   See G4. Recommended: block coach writes to such athletes in the pilot.
7. **Pain flag on a day before a locked hard workout.** RunSmart cannot adjust it (lock), so the athlete needs a self-serve way to not do it. Today: simply don't run, and it shows "Not logged" (neutral). Better: "Skip this one" (G2).
8. **Reply-length overrun** pasted from WhatsApp: the counter turns to an error at 1001 and Send is disabled: "Keep replies under 1000 characters".
9. **Coach note in Hebrew in the English pilot.** The note renders with natural direction per paragraph (MVP Q18).

### C.8 Accessibility (C)

- **D3 week cards:** "Week 3, 30 November to 6 December, Build phase, 3 runs, 15 kilometers, 2 of your changes."
- **Draft banner:** "Draft. Yoni can't see this." It's announced on screen open.
- **D4:** the next-7-days diff reads per row: "Tuesday: was easy 5 kilometers, now easy 4 kilometers." The primary button is focused last, never first, so a long summary is read before acting. [ASSUMPTION]
- **P7:** effort as an adjustable control: "Effort, 7 of 10, hard". "Something off?" is a disclosure button with expanded/collapsed state. Pain and Something else are a radio group.
- **Lock glyph:** always paired with the visible text "Set by {Coach}".
- **Reply composer:** labeled "Reply to {Coach}". The character count is announced at 900 and 1000.
- **Large type:** D4 scrolls with the buttons pinned, and the P3 step list wraps. No truncation of the coach's note at AX sizes, so "More" expands inline.
- **Reduced motion:** the publish success is a haptic plus text with no confetti, and P2 doesn't animate in.

### C.9 RTL-readiness notes (C)

- Diff arrows "→" must be directional glyphs that mirror (use a "before → after" component, not a literal arrow character in strings).
- The week list is not mirrored in order, but its content alignment is leading.
- The em dash in the "— {Coach}" signature becomes leading-aligned.
- The consent bullet list is leading-aligned.
- Coach names inside RTL strings are wrapped in direction isolates.

### C.10 AC additions

- **C8.6**
  - (a) D1 fields, defaults, and the cap counter "{k} of {N} AI drafts left today".
  - (b) Leavable progress with an in-app "ready" banner.
  - (c) One open draft per athlete.
  - (d) "Build it yourself" after 3 failures.
  - (e) Inline 16-week and minimum-weeks messages.
- **C8.7**
  - (a) The D3 persistent "Draft · {Athlete} can't see this" strip.
  - (b) "Your change" markers.
  - (c) The D4 summary lines, including the next-7-days diff and "Including {j} you set before".
  - (d) Start-date choice.
  - (e) The stale-plan banner.
  - (f) Link-gone and stale-revision copy.
  - (g) Draft edits need a connection.
  - (h) A Versions list (read-only).
- **C8.8**
  - (a) Use the MVP card string "{Coach} updated your plan · {n} changes this week".
  - (b) A change list with "Got it".
  - (c) "From {Coach}" (created) vs "Edited by {Coach}" (edited) are both permanent tags.
  - (d) The 10-minute push debounce across single edits.
  - (e) The lock reply links the note only if one exists.
- **C8.5**
  - (a) The P5 block copy, with the reply link when a note exists.
  - (b) The action set on locked rows as decided in Q1.
  - (c) 1.2.6 clients: confirm with a manual TestFlight check what the user sees on `workout_locked` / `plan_locked_by_coach`, and document it (see G4).
- **C7.9**
  - (a) The P5 warning includes the count of coach workouts (MVP FR-2e test).
  - (b) "{Coach} will see the change" requires a coach-side signal: either a C7.2 "new" marker or a C7.6 summary line (G6).
- **C7.7**
  - (a) Multiple athlete replies per note are allowed.
  - (b) No edit or delete.
  - (c) The athlete push "{Coach} left you a note" carries no text.
  - (d) Link-revoked-before-flush copy.
- **C7.3**
  - (a) The "Shared with {Coach}" line under effort.
  - (b) The note helper and the hide toggle.
  - (c) No sharing until P9 is acknowledged.
  - (d) The visibility line is hidden for runs without a server row.
- **C7.4**
  - (a) The safety line.
  - (b) "Remove flag" until handled.
  - (c) "{Coach} saw this" after resolve.
  - (d) A run-less flag fallback.
- **C7.8**
  - (a) The P8 and P9 copy above.
  - (b) Equal-weight buttons.
  - (c) "Leave {Coach}" opens the existing leave sheet.
  - (d) Sharing starts only after the ack.

---

# Part 2: Per-story UX gaps (all 33 stories)

Format: what the story doesn't yet say that the UX needs. "→ Part 1 §x" means it is specified above, and the plan owner should fold it into the AC. G-numbers refer to Part 3.

## Phase 1 (11)

**C7.0 `coachV2Enabled` gate**
- **Flag-off behavior isn't specified per surface.** Rule: with the flag off, the app is byte-for-byte 1.2.6 behavior, with no v2 strings, sheets or permission prompts.
  - Missing: what a flag-off athlete sees when their **coach** is on v2 (G4), and what a flag-off coach sees when the athlete is on v2 (pain flags exist server-side, but the coach can't see them, so the athlete's "{Coach} will see this" is untrue).
- **Needs a capability signal** (for example `app_capabilities` or a `client_version` written at sign-in) so each side can tell whether the other can see v2 data. [PROPOSED; G4]
- **TestFlight-to-App-Store transition:** when v2 ships publicly, every linked athlete gets P9 once. Make sure P9 isn't shown twice to TestFlight testers who already acknowledged it (server-side `consent_version` handles this; state it in the AC).

**C7.10 Remote push foundation**
- **Permission timing and copy:**
  - Athlete: after P8 or P9 is acknowledged, with the P10 pre-permission.
  - Coach: on first Coach Today, with T6.

  The AC currently says "after sign-in", which would prompt with no context. → Part 1 §A.6, §C.5.
- **Permission denied:** never re-prompt. One line plus "Open Settings" in coach T5 and athlete My coach.
- **Multiple devices:** a token per device, and pushes go to all of them. Sign-out on one device must not unregister the others.
- **Tap routing when the target is gone** (athlete left, workout deleted, flag resolved): open the nearest valid screen with a one-line notice, e.g. "{Athlete} is no longer linked to you." / "This workout was changed."
- **Athlete notification prefs** exist only as `athlete_coach_note`. No toggles exist for plan published or broadcast, and athlete quiet hours aren't defined. (G13)

**C7.1 Coach Today with 7-day dots**: specified in Part 1 §A. Gaps in the story text:
- **Color-only dots** (AC 1 lists only colors). Add glyphs and labels (Part 1 grammar table).
- **"Missed today"** before the day ends is undefined. The cutoff is in §A.3 (G15).
- **Partial-data rule:** failed runs must not show as missed.
- **Missing urgency tier:** "New to review" (MVP tier) and "No plan yet".
- **Empty, caught-up, error and offline copy.**
- **Order dependency:** pain sorting depends on C7.4, while C7.1's deps say "none". The design works without it (the group is absent). (G25)
- **Week start** (G14).
- **"Each dot is read as a sentence"** is better implemented as an adjustable strip plus a row summary (§A.8).

**C7.2 "New since last visit" markers**
- **The dot must be paired with text** ("{n} new").
- **Seen = opening detail**, not scrolling past the row.
- **Missing event kinds:** goal changes and athlete changes to coach workouts (MVP digest items with no live home otherwise; G6).
- **No "mark all seen"** [ASSUMPTION: not needed at 20 athletes].

**C7.3 Sync RPE + run notes and share with coach**
- **Privacy:** AC 2 backfills notes written under the "stays on this device" promise (G5). Recommend: no note backfill, and RPE backfill only after the P9 ack.
- **"Shared with {Coach}" visibility line** under effort, and a helper under the note field.
- **The hide-note toggle** needs exact placement and copy: "Hide note from {Coach}".
- **What the coach sees for a hidden note:** nothing (don't reveal).
- **Runs with no server row:** hide the visibility line. Coach copy in day detail: "Effort 7/10"; note in quotes with "— {Athlete}".
- **Can the athlete edit a note after the coach has read it?** [ASSUMPTION: yes; the coach sees the latest version, with no history.]

**C7.4 "Pain / something off" flag**
- **Label mismatch:** "Other" (AC 1) vs the `off` kind. Use "Something else" in the UI.
- **Missing the safety line** (MVP voice rule 7).
- **No response-time promise.**
- **Athlete can "Remove flag"** until it's handled.
- **Athlete sees "{Coach} saw this"** after resolve.
- **Run-less flag entry point:** `run_id` is nullable, but there's no UI for "my knee hurts and I didn't run". Recommend: a "Something off?" entry on Today, under the coached-by line. [PROPOSED; small]
- **Does RunSmart's AI react to a pain flag?** For example, it can't suggest rest when tomorrow is locked. (G21)
- **Pain flags in quiet hours** (plan open question 3; default: don't break quiet hours).

**C7.5 Coach push: run finished + quiet hours + prefs**
- **Default for "run finished"** with 20 athletes (G13; Q6).
- **Settings entry point** isn't defined: Coach tab → ⋯ → Notifications.
- **Push copy** includes distance only (OK). Confirm the athlete's display name is the first name.
- **Deferred pushes delivered at quiet end** should be **collapsed** into one: "While you were offline: 4 runs, 1 flag". Otherwise 07:00 brings a burst. [UX ADDITION]
- **Coach time zone source:** device tz, updated on app open [ASSUMPTION].
- **A run-finished push for an athlete with a hidden map or note** still sends. Fine, but the body must stay generic.

**C7.6 Evening missed-workouts summary**
- **[CONFLICT] with the MVP 20:00 digest**, which covered ran / missed / milestones / changed goal / athlete edits. v2 covers misses only and skips at zero. Copy elsewhere promises "{Coach} will see the change" (C7.9) and MVP Story 4.1 promises a digest line for athlete edits. (G6)
  - Recommend one 20:00 push: "Today: {n} missed · {k} flags open · {m} changed their plan" (counts only, with names inside the app). Skip only when every count is zero.
- **Tap target T2** with the filter-clear control.
- **20:00 falls inside nobody's quiet hours by default.** But a coach with quiet hours starting 19:00 gets it at 07:00, stale: "Yesterday: …" prefix.

**C7.7 Athlete replies to a coach note (one level)**
- **Multiple replies per note?** [ASSUMPTION: yes]
- **Edit or delete a reply?** [ASSUMPTION: no]
- **How does the coach answer a reply?** Recommend: a new note, with "Reply" on the coach side opening the composer prefilled with a quote line. [UX ADDITION]
- **Push copy** carries no text: "{Athlete} replied to your note" / "{Coach} left you a note".
- **Reply to a welcome note** (FR-19) or a broadcast: not allowed for broadcasts (C8.12 AC 4). Welcome note: [ASSUMPTION: allowed, it's a coach_feedback row?] VERIFY that the welcome note is a feedback row.
- **The P5 block offers "Reply to {Coach}'s latest note"** as the only channel to ask for a plan change (G3).

**C7.8 Consent copy v2 + notice for existing athletes**
- **Exact copy:** Part 1 §C.5 (P8, P9).
- **Missing:**
  - "RunSmart won't change workouts {Coach} sets" (the lock is a material change to how the plan behaves).
  - Read receipts once C8.12 ships (G12).
  - Equal-weight buttons.
  - "Leave {Coach}" goes through the existing leave sheet.
  - **Sharing starts only after the ack** (G5).
- **What if the athlete never opens the app?** Then nothing new is shared, which is correct: the v2 client is what syncs.
- **Leave sheet (MVP A13) needs a matching update:** "{Coach} won't see your effort, notes or flags", plus the lock line from G17.

**C7.9 Goal-change warning for coached athletes**
- **[CONFLICT] with MVP copy:** the MVP requires the **count** of coach workouts in the warning (FR-2e test). The C7.9 string omits it. Merged copy is in §C.5 P5.
- **"{Coach} will see the change" must be true:** a C7.2 marker plus a C7.6 summary line (G6).
- **Group variant copy**, per §C.5.
- **"Runs per week only" changes** stayed on the group plan in the MVP. Does that still hold? [ASSUMPTION: yes; no warning for runs/week-only.]
- **After C8.1, C7.9 becomes C8.5's block for coach-published plans.** What about plans with a few coach-edited workouts that aren't coach-published? The trigger blocks deactivation if any locked future workout exists, so even one coach edit blocks the athlete's goal change. (G3)

## Phase 2 (14)

**C8.1 Schema for coach-authored workouts + DB-enforced lock**
- **Silent revert:** the trigger keeps OLD planned fields on UPDATE without raising, so a 1.2.6 athlete's move appears to succeed locally and then snaps back after the next sync, with no explanation. Needs at least a known-issue line for pilot athletes and a v2 client message. (G4)
- **Athlete-path edits:** if Q1 allows athlete Skip/Move, the trigger needs an athlete-RPC path that sets "changed by athlete" while keeping the AI lock. (G2)
- **No `edited_by` / `changed_by` field** for the "Changed by {Athlete}" tag (an MVP open item). (G2, G7)
- **Delete leaves a gap** that the AI could refill: confirm `flex_week` won't add workouts on a coach-deleted day in a coach-published plan. [ASSUMPTION; UX shows "Rest (from {Coach})"]

**C8.2 Coach creates a simple workout from scratch**: specified in §B. Gaps:
- **Field limits and validation strings.**
- **Pace optional, plus the beginner-friendly "Any pace".**
- **Offline "Waiting to sync".**
- **"From {Coach}" vs "Edited by {Coach}" tags** (G7).
- **Athlete notification** for a single new workout: currently none is defined. Recommend the debounced "{Coach} updated your plan" (§C.6).
- **Text summary written for old clients** (G4).
- **"Add workout" on a day that already has one:** goes to the conflict sheet B6.

**C8.3 Structured intervals (steps and repeats)**: specified in §B.5. Gaps:
- **Repeat limits; nested repeats** (no).
- **Estimate rule when pace is missing.**
- **The run–walk starter** for beginners.
- **VoiceOver sentences and non-drag reorder.**
- **What the athlete sees on an old build:** text only.
- **The live guide when the athlete runs without GPS** (treadmill): time-based steps only. [ASSUMPTION; existing guide behavior, VERIFY]
- **Coach can't see per-rep results** (no splits in `runs`) (G11).

**C8.4 Edit, move, delete upcoming workouts**
- **Swap / Replace on occupied days.**
- **Undo.**
- **Copy when the athlete completed it meanwhile.**
- **Resolve options on `edit_conflict`.**
- **[CONFLICT]:** "Updated by {Coach}" for 48 h vs the MVP's permanent "Edited by {Coach}" (G7).
- **Athlete notification** (debounced).
- **Deleting a workout in a group-plan context** affects only this athlete; say so in the confirm when the athlete is on a group plan: "Only {Athlete}'s plan changes."

**C8.5 AI and athlete-side respect coach locks**
- **[CONFLICT]:** hiding athlete actions contradicts the MVP resolution (athlete may change a coach workout after a confirm; lock clears; "Changed by"). (G2, Q1)
- **The block copy** "Ask {Coach} to change your plan" implies a contact channel, but the MVP resolved that there is none (G3). §C.5 P5 gives copy with the reply-link fallback.
- **1.2.6 failure presentation** on `workout_locked` / `plan_locked_by_coach` is unknown and must be observed and documented (G4).
- **The lock reply** links the note only if one exists. No "ask in chat".

**C8.6 AI drafts a plan for the coach**: specified in §C.4. Gaps:
- **Setup fields and defaults; start date.**
- **Leavable progress and the ready banner.**
- **Cap copy.**
- **One draft per athlete.**
- **Failure escalation.**
- **"Or group" is unspecified** (G8).
- **Free-text "Notes for RunSmart"** [PROPOSED].
- **Does the draft use the athlete's history** (paces, recent volume)? The coach should see "Based on Yoni's last 4 weeks: 3 runs/week, about 12 km/week". [ASSUMPTION; transparency for the coach]

**C8.7 Coach reviews, edits, publishes; athlete sees published only**
- **Persistent draft banner.**
- **Next-7-days diff in the summary.**
- **Start-date choice.**
- **Stale-plan banner.**
- **Link-gone, stale-revision and offline copy.**
- **Re-publish semantics** (G10): add "Edit plan" (a draft from the live version) next to "Redraft with AI".
- **Versions list.**
- **What "replaces 18 upcoming workouts" means** when some were athlete-changed (G2).

**C8.8 Athlete side of published plans**
- **Card string:** align with the MVP's "{Coach} updated your plan · {n} changes" (G7).
- **Change list.**
- **Push debounce.**
- **Multiple publishes before the athlete opens the app:** one card.
- **The group-plan athlete header** when the coach publishes an individual plan to one group member: "{Coach}'s plan for you: {goal}" (MVP Individual title).

**C8.9 Coach 2–4 week calendar**
- **Agenda at XL and up.**
- **Non-drag "Move to…".**
- **Drop rules (past days).**
- **Pending-sync glyph.**
- **Week start (G14).**
- **"2–4 weeks" in the title vs a fixed "this + next 3":** recommend fixed 4 with scroll. [ASSUMPTION]
- **Weeks beyond the plan end.**

**C8.10 Workout templates library**
- **Template edits don't affect assigned workouts** (copy).
- **Empty and no-results states.**
- **Template naming default:** the summary.
- **Are starter templates (run–walk, etc.) seeded?** [UX ADDITION, recommended: 3 built-ins, not deletable, marked "RunSmart"]

**C8.11 Assign to group or multiple athletes**
- **Eligibility shown before submit.**
- **"Replaces: …".**
- **[CONFLICT-ish]:** a single pace for beginners at different levels (G9).
- **Offline is blocked.**
- **A batched athlete push.**
- **Skip reason "already ran that day".**
- **Coach-chosen behavior for an athlete with a rest day** that date [ASSUMPTION: allowed, shown as "Replaces: Rest"].

**C8.12 Broadcast message to group**
- **Read counts ("Read by 7 of 10")** are a new form of tracking that isn't in the consent copy (G12).
- **Push body:** include the text or not? [ASSUMPTION: include the first 80 characters; broadcasts are logistics ("Meet at the park 07:00"), not health or feedback. This is an exception to MVP rule 5, so flag it.]
- **Edit or delete a sent broadcast?** [ASSUMPTION: delete only, within 15 min.]
- **Where athletes see past broadcasts:** a "Messages from {Coach}" list in My coach.
- **Empty state for the coach:** "Send one message to all your athletes."
- **Confirm before sending to many:** "Send to {n} athletes?"
- **Athlete opt-out toggle** for broadcast pushes.

**C8.13 Coach self sign-up + profile**
- **Entry copy:** "I'm a coach" in Settings is fine. Add one explanatory screen, "Coach with RunSmart: invite athletes, see their runs, build their plans. Free for now.", then display name (prefilled from `profiles.name`) and bio (≤300, counter).
- **Avatar:** `avatar_path` is added, but there's no upload UI in the AC. Monogram fallback. [ASSUMPTION: upload is in scope if the column ships]
- **Can a coached athlete become a coach**, or a coach join another coach? [ASSUMPTION: yes for both roles on one account; the Coach tab and My coach are independent.] (G18)
- **Stopping coaching** and deleting the coach profile: no flow (G16).
- **Bio moderation:** none in the pilot; it's shown to athletes on consent.
- **Flag-off:** the Settings entry is hidden.

**C8.14 Unlock Plan Mode + multiple groups**
- **Group-switch flow for an athlete:** can a coach move an athlete between groups? What happens to their plan? [ASSUMPTION: move = no plan change; only new joiners get group settings.]
- **The invite screen with several groups:** one code per group, with the group name shown on the athlete's consent ("Join {Coach}'s {Group} group").
- **The roster filter control** and its empty state.
- **Mid-plan joiners** of a group whose members have coach-published plans: what do they get? (G8)
- **Mode-change confirm copy:** "This applies to athletes who join from now on. Current athletes keep their plans."
- **Deleting a group** with athletes in it.

## Phase 3 (4)

**C9.1 8–12 week history**
- **Empty state:** fewer than 2 weeks of data: "Trends appear after 2 weeks of runs."
- **Missing RPE weeks:** "No effort logged", not 0.
- **Charts need VoiceOver summaries:** "Weekly distance, 8 weeks: from 10 to 18 kilometers, highest in week 6." Use the audio graphs (`accessibilityChartDescriptor`).
- **Segmented control labels.**

**C9.2 Training load for coaches**
- **Chip copy:** "Load jump", which is coach-only. Tap explains: "This week's load is {x}× the 4-week average." No medical language.
- **Never shown to the athlete.**
- **Threshold** is pending (plan Q5).
- **Beginners** with tiny bases trigger false jumps (e.g. 2 → 6 km). Recommend a minimum chronic-load floor before the chip shows. [ASSUMPTION]

**C9.3 AI weekly coach summary**
- **"Sunday evening" in Israel is the start of the week, not the end** (G14). Recommend: "end of the coach's training week".
- **AI text attribution:** label it "Summary by RunSmart".
- **Each athlete line links to the athlete.**
- **Loading and failure states:** "Couldn't make this week's summary. Try again".
- **Cost-guard copy:** "You can refresh the summary once a day."
- **The push** says "Your week with {n} athletes is ready" with no health detail.

**C9.4 AI-drafted notes from the summary**
- **MVP rule 6** ("never put words in the coach's mouth") is satisfied only if the coach edits or explicitly sends.
- **Require at least one visible review step:** the draft opens in the composer, never with a send-from-list shortcut.
- **"Drafted with RunSmart" hint:** coach-only, as the plan says.
- **Confirm that athletes are never told it was AI-drafted.** [Decision for the owner; it's ethically fine either way, but should be deliberate.] (G22)

## Later (4)

**L1 iPad layout**
- **Keep the T1 / B1 / D3 specs** compatible with a split view: list in the sidebar, detail in the content area.
- **Keyboard shortcuts** for the next/previous athlete.
- **No UX gaps for now** beyond keeping layout code size-class-driven, not device-driven.

**L2 Push workouts to watch**
- **The step model (§B.5)** should map 1:1 to WorkoutKit's warm-up / blocks / cool-down. Keep that constraint when C8.3 finalizes the shape.
- **No other gaps for now.**

**L3 Payments ($9/athlete via coach)**
- **Consent and leave copy** will need payment lines, and "free for now" must not be promised in copy.
- **v2 copy must avoid "free".** [UX ADDITION]
- **No other gaps for now.**

**L4 Group wall / community**
- **C8.12 broadcasts are read-only by design.** Keep "Messages from {Coach}" separate from any future wall, so moderation scope stays clear.
- **No other gaps for now.**

---

# Part 3: Gaps across the whole plan, ranked by impact

| # | Impact | Gap | Recommended default |
|---|---|---|---|
| G4 | **High** | **Mixed versions and flag-off.** Base coach mode is public (1.2.6), and v2 is TestFlight-only. Two kinds of pairs break:<br>• **v2 coach + App Store athlete.** The athlete sees coach workouts as plain workouts with no "From {Coach}", sees intervals only if text exists, has moves silently reverted by the trigger, and gets an unknown error on delete or regenerate.<br>• **v2 athlete + non-v2 coach.** The athlete is told "{Coach} will see this" for flags and effort the coach can't see.<br>There is no capability field, so neither side can tell. | Add a client capability (`coach_v2` boolean written at sign-in) [PROPOSED]. In the pilot, **coach writes and athlete sharing UI activate only when both sides are v2-capable**. Otherwise the coach row says "{Athlete} needs the latest RunSmart", the builder is disabled for that athlete, and the athlete hides the v2 sharing lines. Always write a text summary of structured workouts. Check what 1.2.6 shows on `workout_locked` and document it. |
| G2 | **High** | **[CONFLICT] Athlete control over coach workouts.** MVP (resolved): the athlete may change a coach workout after a confirm; the lock clears; "Changed by {Athlete}"; a digest line. v2: actions are hidden, and the trigger silently keeps the coach's fields. Beginners with a pain flag before a locked hard session have no self-serve option except not running. | Allow **"Skip this one"** and **"Move to another day"** on coach workouts, with the confirm "{Coach} set this workout. Change it anyway? {Coach} will see the change." Mark it "Changed by you" / "Changed by {Athlete}". It **stays locked against the AI**, which needs an athlete RPC path plus a `changed_by` field. Content edits (distance, steps) stay coach-only. (Q1) |
| G3 | **High** | **[CONFLICT] Goal change.** MVP: applies immediately, with coach workouts replaced after a counted warning. v2 after C8.1: blocked whenever any locked future workout exists (even one coach edit), with "Ask {Coach} to change your plan" and no channel to ask (MVP resolution: no contact destination). | **Block only for coach-published plans** (C8.7), with the P5 copy and a "Reply to {Coach}'s latest note" link when a note exists. For AI plans with a few coach-edited workouts, keep the MVP behavior: a counted warning, then replace (needs the trigger to allow it via an athlete goal-change RPC). (Q2) |
| G5 | **High** | **Privacy of default-on sharing.** C7.3 AC 2 backfills 14 days of notes that were written under the "notes stay on this device" promise. Nothing gates sync on the P9 acknowledgment. Read receipts (C8.12) aren't in consent. | **No note backfill. RPE backfill (14 days) only after the P9 ack. No sharing of any kind until `ack_coach_consent(2)`.** P9 copy states "Notes you wrote before today stay on this phone." Add the read-receipt line when C8.12 ships. (Q7) |
| G1 | **High** | **[CONFLICT] Draft-then-publish scope.** MVP: every coach edit goes into a draft, with one Publish and a change summary; nothing autosaves to the athlete. v2: single-workout create, edit, move, delete and assign go **live immediately**, and only AI plans use draft and publish. | Accept live single edits (the expected coach behavior, and simpler), but keep the MVP's athlete experience through a **debounced single push plus a change-list card** ("{Coach} updated your plan · 3 changes this week"), 10 minutes after the last change. Draft and publish stay for whole plans. (Q3) |
| G8 | **High** | **Group AI drafts and group joiners.** C8.6 says "athlete (or group)", and M7 has `group_id`, but the MVP rule is "thin group plan; each athlete's plan generated at their own level". It's undefined how one group draft becomes per-athlete plans, and what a mid-plan joiner gets when the group's members have coach-published plans. | **v2: per-athlete drafts only.** Group-wide work is done with templates plus assign (C8.11). New joiners get the group's AI plan from the current week (MVP), not another athlete's coach plan. Revisit group drafts after TF-3. (Q5) |
| G6 | Medium | **Coach-side signal for promised events.** Copy promises "{Coach} will see the change" (C7.9) and MVP Story 4.1 promises digest lines for athlete edits, goal changes, milestones and leavers. v2's C7.6 summary covers only misses and skips at zero. | 20:00 push with counts: "Today: {n} missed · {k} flags open · {m} changed their plan". Names appear in-app (T1 "New to review"). Skip only when all counts are zero. C7.2 counts goal changes and athlete changes. |
| G21 | Medium | **Pain flag vs AI and locks.** After a pain flag, RunSmart can't adapt the locked workouts and has no defined behavior (MVP rule: the AI defers pain to a doctor or physio, and plan disputes to the coach). | No AI plan changes on a flag. The athlete sees the safety line and "{Coach} will see this". RunSmart chat, if asked, says: "That's {Coach}'s workout. Your flag was sent to {Coach}. If the pain is sharp or doesn't go away, check with a doctor or physio." The athlete can always skip (G2). |
| G13 | Medium | **Notification defaults and athlete prefs.**<br>• "Run finished" defaults ON (the plan) vs the MVP's "per-run pushes opt-in, off".<br>• Pain during quiet hours is open.<br>• Athlete quiet hours and toggles (plan published, broadcast) are undefined.<br>• A 07:00 burst after quiet hours.<br>• Permission prompt timing is "after sign-in". | Run finished ON for the pilot (≤20 athletes), with the 30-minute dedupe. Pain never breaks quiet hours. Collapse deferred pushes into one at quiet end. Athletes get toggles for coach notes, plan updates and broadcasts, plus the same quiet hours. Pre-permission screens (T6, P10). (Q6) |
| G10 | Medium | **Re-publish semantics.** A new AI draft republished over version 1 wipes Dana's single edits made after version 1. There is no "edit the live plan as a draft". | Add an "Edit plan" action (a draft cloned from the live published version) next to "Redraft with AI". D4 says "Including {j} you set before." |
| G14 | Medium | **Week start.**<br>• `WorkoutAdherence` uses Sunday only for region IL.<br>• "Behind this week", the calendar rows and the Sunday-evening weekly summary all depend on it.<br>• In Israel, Sunday evening is the end of day 1 of the week. | One explicit training-week start per athlete, defaulting to the region rule as today. The weekly summary runs at the end of the coach's week (Saturday evening for IL). Document it in C7.1, C8.9 and C9.3. |
| G7 | Medium | **Tag and copy drift.** v2 uses "From {Coach}", "Updated by {Coach}" (48 h) and "Plan updated by {Coach}". The MVP uses "Edited by {Coach}" (permanent, FR-17) and "{Coach} updated your plan · {n} changes". | Permanent tags: "From {Coach}" (created), "Edited by {Coach}" (edited RunSmart workout), "Changed by {Athlete}". A 48 h "Updated" pill is extra, not a replacement. Card: the MVP string. |
| G9 | Medium | **One pace for many beginners** (C8.11) vs "each athlete at their own level". | Warn on multi-assign with pace. Offer effort-word targets ("easy", "comfortably hard", "hard") as a pace-free option [PROPOSED; small `workout_structure` field]. Per-athlete pace scaling is later. |
| G16 | Medium | **The coach ends a relationship.** There is no coach-side "remove athlete", no "stop coaching", and no coach-profile deletion flow. The effects on locked workouts, drafts and the athlete's view are undefined. | Add "Remove {Athlete}" with the same server effects as the athlete leaving (locks cleared, access revoked). The athlete sees a neutral in-app line once: "You're no longer coached by {Coach}. Your plan stays and RunSmart keeps adapting it." No push. [PROPOSED] (Q8) |
| G11 | Medium | **No per-rep results for the coach.** `runs` has no splits, so after building a 6×800 the coach can't see how the reps went. That undercuts the builder's payoff. | Accept for v2 (show totals only). Note it as the first Phase-3 candidate ("Rep times on structured runs"). [PROPOSED] |
| G18 | Low | **Self sign-up edge cases:** dual role (coach and coached), avatar upload UI missing, bio shown on consent unmoderated, entry hidden flag-off. | Allow dual roles. Add avatar upload only if `avatar_path` ships, otherwise a monogram. No moderation in the pilot. |
| G12 | Low | **Broadcast details:** read receipts not in consent, push body text, edit or delete, archive, and the athlete opt-out. | See C8.12 in Part 2: first 80 characters in the push, delete within 15 minutes, "Messages from {Coach}" in My coach, consent line. |
| G17 | Low | **Leave copy update.** The plan's Q7 default (future coach workouts stay, unlocked) matches the MVP sheet ("Workouts {Coach} set are no longer protected, so RunSmart may adjust them"). It needs new lines for effort, notes and flags, and for replies. | Add "{Coach} won't see your effort, notes or flags" to "What stops". Add "Your replies to {Coach}'s notes" to "What stays". Drafts for that athlete are purged after 30 days. |
| G15 | Low | **"Missed today" timing.** It's undefined before the day ends, and athlete and coach time zones can differ. | A cutoff at 20:00 athlete-local, matching the summary. Before it: "Not done yet". Rows prefix the athlete's weekday when the dates differ. |
| G22 | Low | **AI-drafted coach notes** (C9.4) vs MVP rule 6. | Allowed only through the composer with an explicit Send. The owner confirms that athletes aren't told about AI drafting. |
| G25 | Low | **Order and dependencies.** C7.1 sorts by pain (C7.4) but has no deps. C7.6/C7.7 push copy depends on C7.10. | Design C7.1 to degrade gracefully (done in §A). State the dependency in the AC. |
| G19/G20 | Low | **Undo and offline gaps.** There is no undo anywhere in the plan. `coach_resolve_flag`, multi-assign and drafts have no offline story. | A 5-second client-side undo for move, delete and mark-handled (outbox delay). Mark handled is outboxed. Multi-assign and draft edits need a connection, with explicit copy. |
| G24 | Low | **The 72-hour review promise** isn't mentioned in v2. | Keep the MVP behavior on v2 run screens next to the new "Shared with {Coach}" effort line. Don't add a second "shared" line: when the run has a review promise, show only one status line. |

---

# Part 4: Questions only Nadav can answer (each with a recommended default)

1. **Can athletes skip or move a workout their coach set?** (G2)
   - Default: **yes, skip or move only**, with a confirm.
   - It's tagged "Changed by {Athlete}", stays protected from RunSmart, and the coach sees it.
   - Changing distance or steps stays coach-only.
2. **Goal change on a coach plan: block it or replace after a warning?** (G3)
   - Default: **block only when the coach published the whole plan**, with "Ask {Coach} to change your plan" plus a reply link.
   - Otherwise keep the MVP rule: a warning with the count, then replace.
   - There is still no in-app "request a change" channel in v2.
3. **Should a coach's single-workout edits go live right away, or wait for a Publish?** (G1)
   - Default: **live right away**.
   - The athlete gets one bundled "{Coach} updated your plan" push 10 minutes after the coach stops editing.
   - Draft and publish are only for whole plans.
4. **Pilot pairing rule for app versions.** (G4)
   - Default: **v2 coach tools and sharing switch on only when both coach and athlete run a v2 build**. Pilot athletes join the TestFlight.
   - Otherwise the coach sees "{Athlete} needs the latest RunSmart".
5. **AI drafts for a whole group in v2?** (G8)
   - Default: **no, one athlete at a time**.
   - Groups get shared workouts through templates and "assign".
   - New group joiners get the group's RunSmart plan from the current week.
6. **Notification defaults.** (G13; plan open questions 3 and 6)
   - Default: coach "run finished" **on** (with the 30-minute limit).
   - Pain flags **don't** break quiet hours.
   - Every plan publish notifies the athlete **once**.
   - The 20:00 push shows counts for misses, open flags and plan changes.
7. **Backfill on update.** (G5; plan open question 8)
   - Default: **no backfill of past notes**, since they were written as private.
   - Effort from the last 14 days syncs only after the athlete taps OK on the new sharing notice.
   - Nothing is shared before that.
8. **Can a coach end the relationship from their side?** (G16)
   - Default: **yes, "Remove {Athlete}"**, with the same effects as the athlete leaving.
   - The athlete sees one neutral in-app line, with no push.

---

# Appendix: Consistency check against locked MVP decisions

| Locked MVP decision | v2 plan | Status |
|---|---|---|
| Draft-then-publish with a change summary | Only for AI plans; single edits are live | **[CONFLICT] G1** |
| Plan Mode Group/Individual; group changes apply to new joiners only | C8.14 unlocks the mode; new joiners only | Consistent. Add the confirm copy (C8.14). |
| One coach per athlete | Implied (`is_active_coach_of`) | Consistent |
| Mid-plan joiners start at the current week | Not restated; unclear with coach-published plans | Gap G8 |
| Goal change applies immediately; coach workouts replaced after a warning | Phase 1 warning (no count); Phase 2 blocked | **[CONFLICT] G3**, plus the missing count |
| Route maps shared, in consent copy | Kept; consent adds effort, notes and flags | Consistent (P8 copy) |
| On leave the coach loses all access; past feedback readable | `leave_coach` clears locks; replies read-only | Consistent. Leave sheet needs new lines (G17). |
| Athlete edits a coach workout: lock clears, "Changed by {Athlete}", digest | Athlete actions hidden; trigger silently reverts | **[CONFLICT] G2** |
| AI on a coach workout: "That's {Coach}'s workout" plus a note link only | Same string; "Ask {Coach} to change your plan" on goal change | Consistent for workouts. The goal-change copy implies a channel (G3). |
| 72 h "{Coach} will review this run" → "Shared with {Coach}" | Not mentioned | Keep (G24) |
| Coach presence felt throughout | Strengthened (published plan header, notes, replies, "saw this") | Consistent |
| 20:00 digest (ran, missed, milestones, goal changes, athlete edits) | 20:00 misses-only push, skipped at zero | **Gap G6** |
| "Edited by {Coach}" permanent tag (FR-17) | "From {Coach}" + a 48 h "Updated by {Coach}" | Drift G7 |
| Athlete sees "Not logged", never red or "Missed" | Dots are coach-only; athlete UI unchanged | Consistent. Keep athlete copy neutral. |
