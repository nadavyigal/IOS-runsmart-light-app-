# Coach Mode pilot: two-phone test guide

Coach Mode is on in every TestFlight build and off in the App Store build
(`IOS RunSmart app/Services/Coach/CoachModeService.swift`). Use two phones: one signed in
as the coach, one as the athlete. Both install the same TestFlight build.

## 1. Before you start (once)

1. **Two accounts.** Make two RunSmart accounts with different emails, for example
   `you+coach@...` and `you+athlete@...`. Sign up for both in the app.
2. **Make the coach account a coach.** In the Supabase SQL editor for the Run-Smart project:

   ```sql
   select id, email from auth.users where email = 'you+coach@example.com';
   ```

   Then, with that id:

   ```sql
   insert into coach_profiles (user_id, display_name)
   values ('<id from above>', 'Dana');
   ```

   The display name is what athletes see ("Coached by Dana"). To undo:
   `delete from coach_profiles where user_id = '<id>';`
3. **Install the TestFlight build** on both phones. Sign in with the coach account on
   phone A and the athlete account on phone B.
4. **Athlete phone:** allow location while running, so the run has a route.

## 2. Test script

Tick each line. If something is wrong, note the step number, the phone, and take a screenshot.

### Coach setup (phone A)
1. A **Coach** tab shows. Open it.
2. "How do you want to coach?" Pick **Group Plan**, then fill goal, distance, race date,
   level and runs per week, and save. (Run the test a second time with a fresh coach
   account and **Individual Plans** if you want to cover both.)
3. The plan mode now shows as "Set for the pilot" and can't be changed.
4. The **Invite** card shows a code and a link. Optional: write a **welcome note**.
5. Tap **Share** and send the link to phone B (Messages or WhatsApp).

### Athlete joins (phone B)
6. Tap the link. RunSmart opens on the join screen with the code filled in.
   (If the link opens Safari instead, type the code in Settings, "Join a coach".)
7. The consent screen lists what the coach can see. Accept.
8. Group Plan: "This replaces your current plan" appears, and the plan becomes the group plan.
9. **Today** shows "Coached by Dana" under the title. The welcome note shows if the coach wrote one.
10. **Plan** shows "Dana's plan: {goal}" (group) or "Dana's plan for you" (individual).
    Tapping it opens **My coach**.

### Run and feedback
11. Phone B: record a short outdoor run (at least about 1 km, so the route survives the
    privacy trim). Save it.
12. The run summary shows "Dana will review this run".
13. Phone A: Coach tab, the athlete appears in the list with this week's adherence.
    Open the athlete: this week's strip shows the run.
14. Open the day: planned vs actual, and the **map** with "Start/end hidden for privacy".
    The start and end of the route are cut off.
15. Tap **Write feedback** on the run, use a quick chip plus your own words, and send.
    Try one note in Hebrew too. "Sent. {Athlete} will see this in the app."
16. Also write a **Week note** from the athlete screen.
17. Phone B: Today shows a badge and the coach cards ("Dana on your ... run",
    "Dana's note for this week"). Tap **Read**: the run opens with the note pinned above
    the stats. The badge goes down.
18. Phone B: open the run and turn on "Hide map from Dana".
    Phone A: refresh the day; it now says "Map hidden" and the stats still show.
    Phone B: unhide, then phone A shows the map again.

### Offline and edits
19. Phone A: airplane mode on, write a note, send. "Not sent. Saved on this phone."
    Airplane mode off, reopen the athlete: the note sends by itself.
20. Phone A: tap your own note, edit it, save. It shows "Edited" on both phones.

### Leaving
21. Phone B: My coach, **Leave coach**, confirm.
22. Phone B: no "Coached by", no coach cards, no badge, solo plan title. Old notes still
    show on their runs, read-only, with Dana's name.
23. Phone A: the athlete disappears from the list. Opening an old link to them says they
    are no longer in your group.

## 3. What to send back

For each problem: step number, which phone, what you expected, what happened, a
screenshot. Paste them into a Claude session and say "pilot QA findings".
