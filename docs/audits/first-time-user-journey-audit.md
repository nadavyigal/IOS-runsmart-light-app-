# RunSmart iOS First-Time-User Journey Audit

**Date:** 2026-07-13
**Build audited:** `main` @ 7b15df1 (1.0.8 / 22 line), Debug build on iOS 26.5 simulator (iPhone 17 Pro, fresh device)
**Method:** Fresh-install walkthrough in three modes — real mode (no flags), onboarding replay (`-RUNSMART_RECORD_ONBOARDING`), and demo mode (`-RUNSMART_DEMO_MODE`) — followed by targeted code inspection of every observed problem. No production accounts were created; no real health data was used; no production code was modified.
**Persona:** Recreational runner, 2–3 runs/week, has tried generic plans, curious about AI coaching but does not yet trust it. Will abandon quickly if value or next step is unclear.
**Screenshots:** `docs/audits/assets/ftux-2026-07-13/` (referenced below as `[shot: name]`).

**Simulator-only limitations (documented, not skipped):**

- Sign in with Apple cannot complete on a simulator without an Apple Account (`ASAuthorizationError 1000`). The full authenticated path (real plan generation, FirstRunActivationSheet, morning check-in) was therefore assessed by code inspection, and is marked as such.
- The Terms of Service link opened Safari at `runsmart-ai.com` but the page did not render in the simulator; whether it loads on device is unverified.
- Garmin OAuth requires the registered `runsmart://` callback and a real Garmin account; assessed by code inspection and prior QA evidence in task memory.
- Demo mode presents a week-3 established user, not a true first-run state, so first-value moments were cross-checked against the real-mode code paths.

---

## 1. Executive verdict

RunSmart's first impression is visually strong and unmistakably a running product, but the very first ask is trust (Sign in with Apple) before any value is shown, and the first failure a user can hit — auth error — is surfaced as a raw `com.apple.AuthenticationServices` error string. Onboarding itself is genuinely good: six short steps, a skippable HealthKit ask with honest disclosure, and no name/email collection. The product promise ("a clear daily answer: what to run today") is real once inside — the Today tab, "Why this workout?" card, and coach context chips are the most credible AI-coaching surfaces I have seen at this stage of a product. The single most likely abandonment point is the gap between finishing onboarding and seeing a plan: generation is asynchronous, can take up to 45 seconds, has no dedicated waiting state, and its failure banner points to a "Training Data" screen a new user cannot find. The second-most likely is the sign-in wall itself. The largest product risk is trust erosion by inconsistency: the same workout is labeled "Easy" and "Zone 3-4", the same screen says "Week 3" and "Week 4", the aha moment says "six weeks" above a chart that says "8 weeks", and the workout breakdown can render "21000 × 400 m" from a string-parsing bug. The strongest asset is explainability — RunSmart repeatedly tells the user *why* ("Coach is counting today's imported activity before nudging the rest of the plan"; "this run was too short to change training load") — and that is exactly the differentiation a skeptical runner needs. Fix the contradictions and the post-onboarding gap before spending on acquisition; the core loop underneath is sound.

---

## 2. First-time-user narrative

**Minute 0 — App Store & icon.** The listing promises "a clear daily answer: what to run today." Good hook, matches my problem. The lime "RS" icon is distinctive.

**Minute 0–1 — First screen** `[shot: 02-first-screen]`. A dark, confident brand screen: "Personal coaching before and after runs. Smart reports. Adaptive plan guidance." Three bullets follow. The first says "Run guidance and cue previews" — I don't know what a "cue preview" is. The third bullet is "HealthKit reads approved data and can save completed GPS runs" — that reads like it was written for an Apple reviewer, not for me. There is exactly one button: **Sign in with Apple**. No browse, no demo, no "see a sample plan." *Interest is moderate; trust is being asked for before value is shown.*

**Minute 1 — Sign-in.** I tap Sign in with Apple. On this simulator it fails (expected without an Apple Account), and the app prints **"The operation couldn't be completed. (com.apple.AuthenticationServices.AuthorizationError error 1000.)"** in red above the button. As a real user hitting any SIWA failure, this reads as "this app is broken." Tapping *Terms of Service* throws me out of the app into Safari. *First doubt.*

**Minutes 2–4 — Onboarding** (via replay mode; identical UI to the real path). Goal → Experience → Weekly rhythm → "Privacy" → Apple Health → Ready. Honestly pleasant: each step is one decision, subtitles explain *why* ("This controls how aggressively the plan progresses"), and the progress bar is visible. Two stumbles: the fourth step is titled **Privacy** but is actually coaching tone + reminders, ending in a strange "Confirm Privacy" button — what privacy did I just confirm? And there is no visible back control anywhere; if I fat-fingered my goal I'd assume I have to live with it. On the Apple Health step I tapped **Connect Apple Health** twice and nothing visibly happened `[shot: 06-health-after-tap]` (in the real path a HealthKit sheet appears, but code confirms any *failure* is silent — the button just resets). I used the honest "Continue without connecting" escape hatch. The "Ready" step says "RunSmart is building your plan. Next, commit to your first run."

**Minute 4 — Aha moments.** A "First Timer" identity card ("Everyone starts somewhere. Yours starts now.") — warm but generic. Then a goal timeline that *is* personalized to my 5K goal — except the headline says "**Six weeks** from now, you could be lining up at your first 5K" directly above a milestone dot reading "5K ready **in 8 weeks**", and the subtitle claims "we know you'll finish." *A skeptic notices: the coach contradicts itself on its very first prediction, then overpromises.*

**Minutes 4–5 — The gap (code-inspected; real path).** After the aha moments, the app fires plan generation and polls for up to 45 seconds for a first workout. If it arrives, a well-designed "Your first run is ready" sheet offers **Start Now** or **Remind Me Tomorrow** — a genuinely good activation moment. If generation is slow or fails, I land on Today/Plan with no plan, a transient banner ("Plan Update Delayed — Open Training Data to retry"), and no idea that "Training Data" lives behind Profile. The Plan tab in that state is a bare calendar with zero markers. *This is the highest-stakes moment in the product and it has the weakest state design.*

**Minutes 5–10 — Today tab (demo mode)** `[shots: 11-demo-today2]`. Once populated, Today is the best screen in the app: greeting, streak, week strip, today's workout with duration/pace/intensity, and — the standout — a **"Why this workout?"** card: "Imported 5.0 km from Garmin today. Coach is counting today's imported activity before nudging the rest of the plan." That one sentence is the product's whole differentiation. But it is subtitled "Imported activity · **Heuristic**" — developer taxonomy leaking into the exact surface meant to build trust. Scrolling further: a "NEXT RUNS" section listing runs already marked *Done*; a "WEEK IN REVIEW" card saying "**Week 4** of your plan" while the header pill says "**Week 3**"; HRV "trending up" (good news) drawn in alarming red bars while Readiness gets green.

**Minute 10 — Workout detail.** Tapping today's workout opens a rich sheet with plan tools and coach actions (Reschedule, Amend, Choose Route, Adjust Plan) — excellent adaptability affordances. The "Workout Breakdown" however shows "**Repeats: 21000 × 400 m** · Target 4:45/km" for a workout whose card says 8 × 400m at 5'15"/km. Three contradictions in one sheet.

**Minutes 10–15 — Running** `[shots: 20-run-tab, 21-after-start, 22-run-recording]`. This flow is the app's craftsmanship peak. The Run tab honestly states "GPS ready to request"; tapping Start Run triggers the location dialog with a clear purpose string, and the run **starts automatically after approval** — no second tap. Live screen: huge numbers, honest "Map appears when GPS points are available" placeholder, GPS accuracy surfaced in words ("Route recording looks solid"), three large buttons. Pause froze the timer correctly and swapped in Resume/Finish/Discard. Finish asked "Finish this run?" with both Save and Keep Recording visible.

**Minutes 15–18 — Post-run.** Summary shows distance, moving time, pace, route map, and an unset "How did that feel?" 1–10 scale. When I rated 7/10, the Coach Analysis panels updated live ("This was a stronger effort. Keep the next run controlled." / "Hydrate, refuel, and keep the next 24h lighter") — the app visibly reacted to my input. The run report's **"Coach Learned"** card was the single most trust-building moment of the session: "Coach learned this is too short to change training load by itself." An AI coach that declines to over-read a 0.35 km run is a coach I might believe. But the same screen: pace says 7:24 after the live screen said 5:13; the analysis quote rounds 0.35 km to "0.4 km"; a disabled "Review manually" button sits above a duplicate "Review manually" link; and tapping **Generate Report** produced no spinner, no error, and no report — silence.

**Minute 18+ — Report & Profile** `[shots: 31-report2, 40-profile]`. The Report tab was a *completely blank screen for ~10 seconds* (no loading indicator) before revealing solid content — including my run with "RPE 7/10" persisted. Every history row has an always-visible delete trash can. A stat pill says "SOURCE: **Real**" — hardcoded developer vocabulary. Profile says "**11-week streak**" where Today said "**11 day streak**", and calls me "10K focused · Level 14 · Peak Performer" — I told it I've never run a 5K.

**Would I return tomorrow?** If my first plan generated and I hit the "first run is ready" sheet — probably yes; the streak, the 21-day foundation block, and the promise of a plan that adapts are real pulls. If plan generation hiccupped, or I noticed two of the numeric contradictions, I would quietly not come back.

---

## 3. Journey map

| Stage | User goal | Current experience | User question | Friction | Likely outcome |
|---|---|---|---|---|---|
| App Store → icon tap | Confirm this solves "what should I run today" | Clear subtitle/promise in listing | "Is this a coach or another tracker?" | Low | Installs |
| First screen | Understand the product in 10s | Brand + 3 bullets + SIWA only | "Can I see it before signing in?" | **High** — auth wall before value; compliance copy as a value bullet; "cue previews" jargon | Curious users sign in; skeptics bounce |
| Sign in with Apple | Get in with minimal risk | One tap (device); raw NSError on failure; Terms ejects to Safari | "Is this app finished?" | Medium (High on any failure) | Most proceed; failures churn hard |
| Onboarding (6 steps) | Give just enough to get a plan | Fast, one decision per screen, good "why" subtitles | "How many steps left? Can I go back?" | Low–Medium — no back affordance, no goal validation, "Privacy" mislabel | Completes in <2 min |
| Apple Health step | Decide on data sharing | Honest disclosure + visible skip | "What do I get if I connect?" | Low — but connect failure is silent | Many skip; fine |
| Aha moments | Feel seen; believe the goal | Identity card + goal timeline | "Six weeks or eight?" | Medium — contradiction + overpromise | Mild lift; skeptics notice |
| **Plan generation gap** | See my plan | Async ≤45s; banner on fail points to hidden "Training Data"; bare calendar meanwhile | "Where's my plan?" | **Critical** | Prime abandonment point |
| First-run activation | Know exactly what to do first | "Your first run is ready" sheet, Start Now / Remind Me (code-verified) | "Can I do it later?" | Low — well designed; only reachable if generation succeeds in time | Strong activation *when reached* |
| Today tab | "What should I do today?" | Workout card + Why-this-workout + readiness context | "Why this? Can I trust it?" | Low–Medium — "Heuristic" badge, Week 3/4 conflict, NEXT RUNS shows done runs | Core promise delivered |
| Starting a run | Start moving fast, safely | Just-in-time permission, auto-start, huge targets, honest GPS states | — | **Lowest in app** | Success |
| During run | Glanceable data, safe controls | Big metrics, live map, correct pause/finish semantics | — | Low | Success |
| Post-run | "How did I do? What now?" | Stats + RPE + reactive coach analysis + honest "Coach Learned" | "Why two different paces? Where's my report?" | Medium — pace mismatch, Generate Report silent no-op, template-y insight panels | Value felt but diluted |
| Report/history | Trust the record | 10s blank load; RPE persisted; per-row delete icons; "Source: Real" | "Is it loading or broken?" | Medium | Tolerated |
| Return next day | A reason to come back | Streaks, 21-day foundation, plan pull, local reminders | "Did the coach actually adapt?" | Medium — adaptation is claimed more than shown | 50/50 for skeptics |

---

## 4. Top abandonment risks

Ranked by (likelihood × cost at that funnel position).

1. **Post-onboarding plan-generation gap has no designed state.**
   Severity: **Critical** · Confidence: High · Evidence: code inspection (`RunSmartLiteAppShell.firstRunnableWorkoutAfterPlanGeneration` 45s poll; `RunSmartPlanNotice` transient banner; "Plan Update Delayed… Open Training Data to retry") + direct observation of the empty Plan calendar in the no-plan state.
   Why it matters: this is the moment the product must prove itself; a new user staring at an empty calendar with a vanished banner has no recovery path ("Training Data" is a tile inside Profile).
   Response: dedicated "Coach is building your plan" state on Today/Plan with progress, expected duration, and an inline retry on failure. Never point new users at a screen they haven't seen.

2. **Sign-in wall before any demonstrated value, with a single provider.**
   Severity: **High** · Confidence: High · Evidence: direct observation `[shot: 02-first-screen]`.
   Why it matters: the persona explicitly distrusts AI coaching; the first ask is the highest-trust action in iOS with zero preview. Any SIWA hiccup ends the journey (see #3).
   Response: either a 3-screen value preview (sample Today + sample Why-this-workout) before auth, or move auth *after* goal/experience selection so investment precedes the ask.

3. **Auth failure shows a raw `AuthorizationError 1000` string.**
   Severity: **High** · Confidence: High · Evidence: direct observation (`SignInView.swift:126` — `errorMessage = error.localizedDescription`).
   Why it matters: the first error a user can ever see is developer debris; instant "unfinished app" verdict.
   Response: map SIWA failures to human copy ("Apple sign-in didn't finish. Nothing was created — try again.") and log the raw error to analytics instead.

4. **Numeric contradictions across surfaces destroy coaching credibility.**
   Severity: **High** · Confidence: High · Evidence: direct observation — "Week 3" pill vs "Week 4 of your plan" on the same scroll; card "Easy · 5'15\"/km" vs sheet "Zone 3-4 · Build · 4:45/km"; "This Week … Distance: 86.20km" vs listed workouts summing ~36 km; "11 day streak" (Today) vs "11-week streak" (Profile); live pace 5:13 vs summary 7:24 unexplained.
   Why it matters: a skeptical runner is *looking* for reasons to dismiss the AI. Every contradiction is one. Some are demo-data artifacts, but the surfaces render from independent sources with no consistency layer, so the class of bug ships to production.
   Response: single source of truth per concept (week number, streak, workout intensity, weekly distance); a QA checklist item that any number rendered twice must come from one accessor.

5. **Workout Breakdown fabricates structure and can render "21000 × 400 m".**
   Severity: **High** · Confidence: High · Evidence: direct observation + root cause at `StructuredWorkoutFactory.distanceKm(from:)` — "8 x 400m" → digits "8400" → 8400 km → `reps = km/0.4 = 21000`; default target paces (4:45/5:15) are hardcoded and contradict the card's chips.
   Why it matters: absurd numbers in a "coach" product are fatal to trust (same fabrication class as the WP-37 splits lesson).
   Response: parse structured reps/distance from the workout model, not from a display string; when targets are estimated, label each value ("est."), not just the section.

6. **The aha timeline contradicts itself and overpromises.**
   Severity: **High** · Confidence: High · Evidence: `GoalTimelineMomentView.swift:15` hardcodes "Six weeks from now…" while line 105 renders "in \(timeline.weeks) weeks" (8 for this persona); subtitle "we know you'll finish."
   Why it matters: this is the *first personalized claim* the coach makes.
   Response: derive the headline from the same `timeline.weeks` value; replace the guarantee with a credible framing ("runners who follow this plan usually get there").

7. **Silent failures on explicit user actions (HealthKit connect, Generate Report).**
   Severity: **Medium-High** · Confidence: High · Evidence: direct observation of both `[shots: 06-health-after-tap, 33-after-generate]`; code confirms `connectHealthKit()` has no failure branch and Generate Report showed no progress/error state.
   Why it matters: taps that do nothing teach users the app is unreliable — worse on the two features (health data, AI report) that define the product.
   Response: every async CTA gets working/success/failure states; on failure, say what happened and what to do.

8. **Report tab renders ~10 seconds of pure black with no loading indicator.**
   Severity: **Medium** · Confidence: High · Evidence: direct observation `[shot: 30-report]` vs `[shot: 31-report2]`; no `ProgressView`/skeleton in `ActivityTabView`.
   Response: skeleton rows or spinner; anything but blank.

9. **Onboarding allows silent no-choice progression with a mismatched default goal.**
   Severity: **Medium** · Confidence: High · Evidence: `OnboardingProfile.empty` sets `goal: "10K improvement"` — not one of the five visible options, so nothing is preselected and Continue passes anyway; the page-style TabView also permits undiscoverable swipe navigation (including forward-skips).
   Why it matters: a user who taps through gets a plan built around a goal they never chose; the "personalized" plan is then visibly wrong.
   Response: require a selection on Goal/Experience (or preselect visibly and say "you can change this later"); disable TabView swipe or add an explicit back button.

10. **Trust-surface jargon: "Heuristic", "Fallback", "Source: Real", "AI - GPS - RunSmart", "Confirm Privacy".**
    Severity: **Medium** · Confidence: High · Evidence: direct observation; `PostRunLearningSource` raw values rendered as badges; `ActivityTabView.swift:56` hardcodes `"Real"`.
    Why it matters: the badges sit exactly where the user decides whether the coaching is real; "Heuristic" literally announces "this wasn't AI," and "Real" begs the question "as opposed to what?"
    Response: translate source tiers to user language ("Based on your plan" / "Quick take — full analysis pending") or drop the badge; remove "Source: Real" entirely.

---

## 5. Activation analysis

- **Intended activation moment (by design):** the `FirstRunActivationSheet` — "Your first run is ready" with Start Now / Remind Me Tomorrow, presented immediately after plan generation succeeds. Second-order activation: completing that run and seeing the post-run Coach Analysis react.
- **Actual activation moment observed:** on simulator, unreachable in real mode (SIWA + backend); in demo mode the equivalent moment is the Today tab's workout card plus "Why this workout?". The design intent is right; the reliability of *reaching* it is the problem.
- **Earliest credible value:** the goal-timeline aha moment (~90 seconds in) is the first personalized artifact; the first *actionable* value is the Today card with its explanation.
- **Actions currently required to reach value:** install → sign in with Apple → 6 onboarding steps → 2 aha screens → wait for plan generation → (sheet or Today tab). That is 10–11 decisions/waits.
- **What could be removed or delayed:** the sign-in wall (delay until after goal/experience, or offer preview); the "Privacy"/tone step (fold tone into a later Coach interaction; default to Motivating); the Garmin/rookie-challenge info rows in onboarding (move to post-activation); the second aha screen could merge with the "Ready" step.
- **Motivation sufficiency:** for the persona, motivation survives onboarding (it's short and respectful) but is spent by the time the plan generates. If the first screen after "Start RunSmart" is empty or ambiguous, there is no remaining goodwill. The activation design (sheet + streak + 21-day foundation) is strong enough *if* the pipeline from "Ready" to "first workout visible" is made deterministic and observable.

---

## 6. Strengths

1. **Explainability as a habit — the real differentiator.** "Why this workout?", coach context chips ("Using your current training context: Readiness 82 · 8 recent runs · 3 reports"), "Coach Learned / What happened / Plan impact", weather tied to today's session ("Good conditions for a controlled tempo run"). No generic tracker does this. Visible early (Today tab). Double down: make every recommendation open into a one-line "because…".
2. **Honest AI restraint.** "Coach learned this is too short to change training load by itself" — declining to over-interpret is the single best trust move in the app. Make this pattern universal (low-data days, missing HR, short runs).
3. **The run flow.** Just-in-time location permission with a clear purpose string, auto-start after approval, honest GPS/no-map states, big glanceable metrics, correct pause/finish semantics with visible cancel paths. This is production-quality and safety-conscious. It is, however, only visible *after* activation — consider showing it (video/preview) pre-auth.
4. **Onboarding economy.** Six steps, one decision each, explicit skip on HealthKit, no name/email after SIWA (Apple-rejection lesson properly absorbed). The "why we ask" subtitles are the right pattern.
5. **Adaptability affordances everywhere.** Reschedule / Amend / Choose Route / Adjust Plan on every workout; "Need to adjust? Tell Coach what changed — Flex Week" on the Plan tab. This directly answers "what if I can't do Tuesday?" — the question that kills static plans. It creates real differentiation if the flows behind it stay this discoverable.
6. **Feedback loop made visible.** Rating a run 7/10 immediately rewrites the coach panels and persists to history ("RPE 7/10" in the run list). The user can *see* the coach consume their input — rare and valuable.
7. **Privacy-conscious sharing.** "Private share: no map, GPS points, or exact route are included" — quietly excellent, aligned with the trust-sensitive persona.

---

## 7. Weaknesses

- **Product positioning:** the first screen sells "cue previews" and HealthKit compliance instead of the one-line promise the App Store already nails ("a clear daily answer: what to run today"). AI/coach language is oddly absent at the exact moment of first impression.
- **Onboarding:** mislabeled "Privacy" step with "Confirm Privacy" CTA; no back affordance; no selection validation; hidden default goal ("10K improvement") that isn't a visible option.
- **Navigation:** generally clear 5-tab structure, but the post-onboarding landing is inconsistent (replay lands on Plan; design intent is Today); "Training Data", the plan-repair surface, is buried in Profile.
- **Coaching clarity:** intensity taxonomy is incoherent across surfaces (Easy vs Zone 3-4 vs Build vs pace chips); the coach chat answered "Explain today's workout" with tomorrow's workout (demo canned response, but the entry-point/answer contract is untyped).
- **Trust:** raw NSError at sign-in; "Heuristic"/"Fallback"/"Source: Real" badges; contradictory week numbers, streak units, distances, and timeline weeks; "we know you'll finish."
- **Personalization credibility:** demo/profile artifacts ("10K focused", "Level 14 · Peak Performer") contradict the beginner story; the first identity card is generic where it should quote the user's own answers back ("3 days/week, Mon/Wed/Sat, first 5K — here's what that builds").
- **Running workflow:** strongest area; only gap is no visible planned-workout link on the Run tab (it always offers "Free Run" even when today's session is planned — starting the *planned* workout requires arriving via Today/Plan).
- **Post-run value:** analysis panels are template-shaped ("Rate the effort if you want this run tagged…") and restate inputs; the full report is gated behind a manual "Generate Report" tap that silently did nothing; pace definitions (live vs summary) aren't reconciled for the user.
- **Retention loop:** streaks + 21-day foundation + local reminders exist, but the loop's core claim — "the plan adapted because of what you did" — is asserted ("Plan is on track") more than demonstrated (no visible diff of what changed since yesterday).

---

## 8. What to double down on

1. **"Why this workout?" as the hero.** Put it (or a compressed version) inside the workout card itself, on the first-run activation sheet, and in the App Store screenshots. It is the answer to "how is this different from a PDF plan."
2. **Coach Learned / honest-restraint pattern.** Extend to every data-sparse situation; this converts skeptics.
3. **The context chips in Coach chat.** "Using: Readiness 82 · 8 recent runs · 3 reports" is visible provenance for AI output — surface the same chips on Week in Review and post-run analysis.
4. **Flex Week / coach actions.** Make one of the three App Store screenshots "life happened → plan rewritten" with a before/after diff.
5. **The run recording experience.** It's the trust anchor for data quality; show it pre-auth (short looping preview on the sign-in screen).
6. **Visible adaptation diffs.** When the plan changes, show what changed and why ("Moved Thursday tempo → Friday; you rated Tuesday 9/10"). This is the retention loop made tangible.

## 9. What to simplify

- **Remove from first screen:** the HealthKit compliance bullet (keep the disclosure where it already is — the Health step); replace "Run guidance and cue previews" with the daily-answer promise.
- **Delay:** Garmin mention and 21-Day Rookie Challenge callout (onboarding "Privacy" step) until after first activation; coaching-tone question until the first Coach chat.
- **Combine:** aha moment 1 (identity) into the "Ready" step; "Privacy" step's reminder toggle into the first Remind-Me interaction (which already requests notification permission at the right moment).
- **Reduce choices:** Run tab shows Free Run + Route + Audio + pacing intent before the user has ever run — collapse to Start Run with progressive disclosure.
- **Shorten copy:** "Confirm Privacy" → "Continue"; "HealthKit reads approved data and can save completed GPS runs" → "Works with Apple Health (optional)".
- **Hide until relevant:** "Generate Coach Report" (auto-generate on save instead; manual regeneration is a power-user affordance); per-row delete trash cans in history (move behind swipe-to-delete with confirm).
- **Progressive disclosure:** Workout Breakdown collapsed by default with "estimated" labeling; wearable trend charts only after a wearable is connected.
- **Secondary actions competing with primary:** on Today, "Review Report" (yesterday) visually competes with today's workout CTA — demote to a row, keep one lime CTA per viewport.

---

## 10. Bugs and usability defects

Reproducible defects, separated from product recommendations. All reproduced on iOS 26.5 simulator, Debug.

| # | Defect | Repro | Severity | Evidence |
|---|---|---|---|---|
| B1 | Raw `ASAuthorizationError 1000` string rendered on sign-in screen | Fresh install on sim without Apple Account → tap Sign in with Apple → dismiss system alert | High | `SignInView.swift:126` (`error.localizedDescription`); direct obs |
| B2 | "Six weeks" headline vs "in 8 weeks" milestone on the same aha screen (First 5K + Getting started persona) | Complete onboarding with First 5K goal → second aha moment | High | `GoalTimelineMomentView.swift:15` vs `:105`; direct obs |
| B3 | Workout Breakdown renders "21000 × 400 m" | Open Intervals workout detail whose distance string is "8 x 400m" → breakdown | High | `StructuredWorkoutFactory.swift:183` digit-strip parse ("8 x 400m"→8400 km); `:128` reps=km/0.4; direct obs (demo) |
| B4 | Breakdown target pace (4:45/km default) contradicts card chip (5'15"/km) for same workout | Same as B3 | Medium | `StructuredWorkoutFactory.swift:126`; direct obs |
| B5 | HealthKit connect failure is silent (button resets, no error) | Onboarding Health step → Connect when connect cannot succeed (unauth/denied) | Medium | `OnboardingView.connectHealthKit()` — no failure branch; direct obs ×2 taps |
| B6 | "Generate Report" produces no feedback and no report | Run report sheet (short saved run) → Generate Report | Medium | Direct obs; "No coach report yet" persists ≥9s, no spinner/error |
| B7 | Report tab shows blank screen ~10s with no loading indicator | Launch demo mode → Report tab | Medium | Direct obs `[shots: 30/31]`; no loading view in `ActivityTabView` |
| B8 | Week number contradiction: header pill "Week 3" vs Week-in-Review "Week 4 of your plan" | Demo mode Today, scroll | Medium | Direct obs (demo data; both values rendered from different sources) |
| B9 | "NEXT RUNS" section lists completed (Done) past runs; future run dated Tue 14 Jul tagged "Today" on Mon 13 Jul | Demo mode Today, scroll to Next Runs | Medium | Direct obs (demo services; date-tag logic suspect) |
| B10 | Streak unit mismatch: Today "11 day streak" vs Profile "11-week streak" | Demo mode, compare tabs | Medium | Direct obs |
| B11 | Plan "This Week" total distance (86.20 km) ≠ sum of listed workouts (~36 km) | Demo mode Plan tab | Medium | Direct obs |
| B12 | "Source: Real" hardcoded user-facing string | Report tab header pills | Low | `ActivityTabView.swift:56` |
| B13 | Duplicate "Review manually" controls (disabled button + orange link) on Coach Learned card | Run report for short run | Low | Direct obs `[shot: 33-after-generate]` |
| B14 | Terms of Service/Privacy links eject to external Safari (page render unverified) | Sign-in screen → Terms | Low | Direct obs; consider `SFSafariViewController` |
| B15 | Onboarding TabView allows swipe navigation (incl. forward skip) with no visible affordance; no back button | Onboarding, swipe horizontally | Low-Medium | Code (`.tabViewStyle(.page)`) + design intent mismatch |
| B16 | HRV "trending up" (positive) rendered in red bars while Readiness uses green | Demo Today, Wearable Trends | Low | Direct obs |

Simulator-only (not counted as defects): SIWA error 1000 itself; Terms page not rendering; HealthKit sheet not appearing in replay mode.

---

## 11. Instrumentation gaps

**Existing events** (inspected in `Services/Analytics/AnalyticsEvents.swift`; PostHog via xcconfig key): `app_launched`, `sign_in_completed`, `onboarding_started`, `onboarding_step_completed` (number+name), `onboarding_completed`, `plan_generated`, `run_started`, `run_completed`, `run_abandoned`, `post_run_card_viewed`, `coach_thread_opened`, `coach_message_sent`, `plan_viewed`, `plan_workout_tapped`, `plan_run_cta_tapped`, `first_run_cta_viewed/tapped`, `first_run_reminder_scheduled`, `route_selected/saved`, `benchmark_viewed`, `tab_viewed`, `garmin_connect_tapped`, `garmin_sync_completed`, `healthkit_disclosure_viewed`, `healthkit_connect_tapped`, `healthkit_sync_completed`, `aha_moment_fired/cta_clicked/dismissed`. This is a genuinely good base — most of the required funnel already exists.

**Missing (proposed):**

| Proposed event | Why |
|---|---|
| `sign_in_failed` (error domain/code) | The B1 cliff is currently invisible; you cannot measure the top-of-funnel drop |
| `onboarding_step_abandoned` (last step, dwell) | Step-completed events can't distinguish kill vs backgrounding at a step |
| `permission_requested/granted/denied` for location + notifications | Location denial ends the run flow; only HealthKit *tap* is tracked today, and no outcomes anywhere |
| `healthkit_connect_failed` (reason) | Pairs with B5; silent failure is currently also analytically silent |
| `plan_generation_started/succeeded/failed/timed_out` (duration) | The #1 abandonment risk has no telemetry; `plan_generated` only fires on success |
| `first_workout_viewed` | `first_run_cta_viewed` covers the sheet; add Today-card first impression for users who miss the sheet |
| `run_report_generate_tapped/succeeded/failed` | B6 currently invisible |
| `insight_expanded` (why-this-workout, week-in-review, coach-learned) | Measures whether explainability — the differentiator — is actually consumed |
| `share_progress_tapped/completed` | Referral loop baseline |
| D1/D7 return: derivable in PostHog from `app_launched` retention; add `cohort: onboarding_completed_at` person property to segment activated vs non-activated returns | Required for the experiments below |

---

## 12. Prioritized recommendations

### Fix before acquiring more users

1. **Design the plan-generation state** (Today + Plan): progress copy, expected wait, success handoff to First-Run sheet, inline retry on failure. Add `plan_generation_*` telemetry. (Risk #1)
2. **Humanize sign-in failure copy** and add `sign_in_failed` tracking. (B1)
3. **Fix the aha-timeline contradiction and remove "we know you'll finish."** (B2)
4. **Fix the breakdown parser** (B3/B4) or hide Workout Breakdown until it renders from structured data.
5. **Kill dev-vocabulary badges** on trust surfaces: "Heuristic"/"Fallback" mapping, delete "Source: Real". (B12 + risk #10)
6. **Make Goal/Experience selection required** (or visibly preselected) and fix the "10K improvement" hidden default. (Risk #9)

### Improve during the next iteration

7. Value preview before/around the auth wall (sample Today card + why-this-workout, or 15s run-flow loop).
8. Loading states: Report tab skeleton (B7); working/failure states for HealthKit connect (B5) and Generate Report (B6) — or auto-generate the report on save.
9. Consistency pass on numbers: one accessor per concept (week #, streak, weekly distance, intensity taxonomy); reconcile live vs summary pace with a label ("avg moving pace").
10. Onboarding polish: rename "Privacy" step, add back affordance, disable page-swipe skipping, move Garmin/challenge callouts post-activation.
11. Rest-day / no-workout Today state with an explicit "what to do today" answer (recovery guidance), so the core promise never renders empty.
12. Replace external Safari with in-app Safari view for Terms/Privacy.

### Observe before changing

13. Coaching-tone step (Motivating/Calm/Direct): measure whether tone choice correlates with retention before removing it.
14. First identity aha moment: A/B generic encouragement vs mirroring the user's own answers before rewriting.
15. Run-tab "Free Run" default vs planned-workout default: instrument `run_started(source:)` split first.
16. Per-row delete affordance in history: check accidental-deletion incidence before redesigning.
17. Manual "Generate Report" demand: if `run_report_generate_tapped` is near-universal, auto-generate; if rare, hide deeper.

---

## 13. Three product experiments

**Experiment 1 — Shorten time to first credible coaching value (required focus).**
- **Hypothesis:** Showing a personalized "coach preview" (draft Today card + why-this-fits explanation built from onboarding answers, client-side, before/while the real plan generates) increases day-0 activation (first workout viewed → started) by ≥15%.
- **Change:** After the "Ready" step, immediately render a deterministic preview of week 1 ("3 runs: Mon easy 20 min, Wed intervals-lite, Sat 30 min — because you chose First 5K, 3 days/week, getting started") while generation runs behind it; swap in the real plan when ready.
- **Primary metric:** % of new users who view first workout within 10 minutes of `onboarding_completed`; time from `onboarding_completed` → `first_run_cta_viewed`.
- **Guardrail:** plan-mismatch complaints / `flex_week` usage in week 1 (preview must not over-promise specifics); D7 retention.
- **Expected behavior:** users stop hitting empty Today/Plan; the 45s generation window stops being an exit.
- **Decision evidence:** ≥200 new users per arm; activation delta ≥10% relative with stable guardrails.

**Experiment 2 — Move the auth wall behind two onboarding questions.**
- **Hypothesis:** Asking Goal + Experience *before* Sign in with Apple ("so your coach is ready the moment you sign in") lifts install→sign-in conversion ≥10% for skeptical users without hurting completion.
- **Change:** Reorder: first screen → Goal → Experience → SIWA (with copy "Save your plan with Apple") → remaining steps.
- **Primary metric:** install→`sign_in_completed` rate (needs `sign_in_viewed` + `sign_in_failed` events).
- **Guardrail:** onboarding completion rate; abandoned-at-auth after answering (sunk-cost resentment).
- **Expected behavior:** more users invest two taps, then convert through auth at higher rates.
- **Decision evidence:** ≥300 installs per arm; conversion delta ≥5pp.

**Experiment 3 — "What changed" adaptation receipts for the return loop.**
- **Hypothesis:** A next-morning card ("Coach adjusted: moved Thursday easy → Friday because you rated yesterday 8/10") increases D1 return ≥8% vs the current static "Plan is on track."
- **Change:** After any completed/imported run, generate a one-line diff of plan impact (even "no change — and here's why that's right") shown on Today and in the return-loop local notification.
- **Primary metric:** D1 return rate of users with ≥1 completed run (PostHog retention on `app_launched`, segmented by cohort property).
- **Guardrail:** notification opt-out rate; `insight_expanded` on the card (are receipts read or dismissed).
- **Expected behavior:** the adaptation claim becomes observable, giving skeptics a concrete reason to reopen.
- **Decision evidence:** ≥2 weeks / ≥150 activated users per arm; D1 delta ≥5pp with flat opt-outs.

---

## 14. Final scorecard

| Area | Score | Rationale |
|---|---|---|
| First impression | 6/10 | Confident, distinctive brand; but auth-first, compliance copy as value prop, and "cue previews" jargon dilute an otherwise clear promise |
| Promise clarity | 6/10 | App Store copy nails it; the app's own first screen doesn't repeat it; inside the app the Today tab finally delivers it |
| Onboarding clarity | 7/10 | Short, respectful, well-subtitled; loses points for "Privacy" mislabel, no back path, silent-skippable goal, invisible swipe navigation |
| Time to value | 5/10 | ~2 min to "Ready" is good; the undesigned 0–45s+ plan-generation gap and auth wall push real value dangerously late |
| Personalization credibility | 5/10 | Goal-aware timeline and reactive post-run analysis are real; contradictions (six-vs-eight weeks, Easy-vs-Zone-3-4, 10K-vs-5K identity) undercut them |
| Navigation | 7/10 | Clean 5 tabs, sensible sheets; buried "Training Data", inconsistent post-onboarding landing, competing CTAs on Today |
| Trust | 4/10 | The most damaged dimension: raw NSError, dev-jargon badges, numeric contradictions, silent CTAs, overpromise ("we know you'll finish") — despite excellent honesty patterns elsewhere |
| Running usability | 8/10 | Best-in-app: just-in-time permission, auto-start, honest GPS states, big targets, correct pause/finish; only planned-run entry from Run tab is missing |
| Post-run value | 6/10 | Reactive analysis + honest Coach Learned are strong; template panels, pace mismatch, and the silent Generate Report keep it from landing |
| Retention motivation | 5/10 | Streaks, 21-day foundation, reminders, and Flex Week exist; adaptation is asserted rather than shown, and Week-in-Review contradicts itself |
| **Overall journey** | **5.5/10** | A differentiated coaching core with production-quality run mechanics, wrapped in a first-time journey whose two riskiest moments (auth, plan generation) and trust surface (consistent numbers, human copy) need work before scaling acquisition |
