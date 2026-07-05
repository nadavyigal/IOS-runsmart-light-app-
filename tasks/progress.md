Status: WP-15 fix shipped to App Store Connect as **1.0.7 (21)** on 2026-07-05. Post-fix activation cohort readout is **pending** (needs ~3–7 days live on build 21). WP-34 Garmin credential-guard branch remains unrecoverable — founder decision required. WP-27 Garmin Gate-4 evidence cleanup complete on main; founder-run screenshots still pending.
Current Phase: PHASE 2 — Activation diagnostics + Garmin maintenance (EXD-015).
Active Story: WP-15 — monitor `plan_generated -> plan_run_cta_tapped -> run_started -> run_completed` on build 21 cohort (target >=20% plan-to-run).
Last Completed Story: 2026-07-05 — WP-15 release: archived and uploaded **1.0.7 (21)** with `firstRunnableWorkoutAfterPlanGeneration()` poll fix (commit `6ed8b97`).
Next Recommended Story: Re-run PostHog funnel on **2026-07-08+** for build-21-only users (`filterTestAccounts=true`). Founder: decide WP-34 re-implement vs park. Then WP-27 Gate-4 screenshots if Garmin path resumes.
Estimated Completion: Post-fix funnel gate opens ~2026-07-08 (3 days after ASC upload) once enough onboarding→plan completions mature.
Blockers: (1) Post-fix cohort not yet measurable same-day as upload. (2) WP-34 lost work. (3) Local main worktree has Finder duplicate `* 2.swift` files that block archive — release built from clean detached worktree at `6ed8b97`; clean duplicates before next local archive.
Last Validation: 2026-07-05 — Release archive **SUCCEEDED** (clean worktree, ~10 min). ASC upload **SUCCEEDED** (`ExportOptionsAppStoreUpload.plist`). Archive metadata: `RunSmart` / `com.runsmart.lite` / `1.0.7` / `21` / `ITSAppUsesNonExemptEncryption=false` / dSYM present. Known HKWorkout deprecation warning only.
PM Artifacts: Activation funnel events in `.agent-os/distribution/analytics-instrumentation-spec.md`; WP-34 incident in `tasks/ERRORS.md`.
Last Updated: 2026-07-05

---

## 2026-07-05 — WP-15 build 21 submitted to App Store Connect

| Field | Value |
|---|---|
| **Version** | 1.0.7 |
| **Build number** | 21 |
| **Fix commit** | `6ed8b97` (WP-15 first-run sheet poll) |
| **Submission date (UTC+3)** | 2026-07-05 ~20:18 |
| **Upload method** | `xcodebuild -exportArchive` + `ExportOptionsAppStoreUpload.plist` |
| **Archive path** | `/tmp/runsmart-wp15-release-1783271110/build/RunSmart-v1.0.7-build21-WP15-AppStore-20260705.xcarchive` |
| **ASC status** | Upload succeeded; package processing |

**Pre-submission checklist:** `tasks/lessons.md` + `docs/qa/testflight-checklist.md` + `docs/qa/app-store-readiness-checklist.md` reviewed. Secrets present (`RunSmartSecrets.xcconfig`). First archive from dirty main worktree failed on duplicate Finder `* 2.swift` compile crash; retried from clean detached worktree (no duplicates). DerivedData cleaned before retry.

**Build bump:** `CURRENT_PROJECT_VERSION` 20 → 21 (local/uncommitted on main worktree `project.pbxproj`).

---

## WP-15 activation readout — D7 baseline vs build 21 (in progress)

### PostHog query (project 171597 — Running coach)

Tool: PostHog MCP `query-funnel` after `switch-project` → **171597**.

```json
{
  "kind": "FunnelsQuery",
  "series": [
    { "kind": "EventsNode", "event": "plan_generated" },
    { "kind": "EventsNode", "event": "plan_run_cta_tapped" },
    { "kind": "EventsNode", "event": "run_started" },
    { "kind": "EventsNode", "event": "run_completed" }
  ],
  "dateRange": { "date_from": "2026-06-19", "date_to": "2026-07-05" },
  "funnelsFilter": {
    "funnelOrderType": "ordered",
    "funnelVizType": "steps",
    "funnelWindowInterval": 7,
    "funnelWindowIntervalUnit": "day"
  },
  "filterTestAccounts": true
}
```

Supporting diagnostic (confirms sheet skip):

```json
{
  "kind": "FunnelsQuery",
  "series": [
    { "kind": "EventsNode", "event": "plan_generated" },
    { "kind": "EventsNode", "event": "first_run_cta_viewed" },
    { "kind": "EventsNode", "event": "first_run_cta_tapped" },
    { "kind": "EventsNode", "event": "run_started" },
    { "kind": "EventsNode", "event": "run_completed" }
  ],
  "dateRange": { "date_from": "2026-06-19", "date_to": "2026-07-05" },
  "funnelsFilter": { "funnelOrderType": "ordered", "funnelWindowInterval": 7, "funnelWindowIntervalUnit": "day" },
  "filterTestAccounts": true
}
```

### Before (pre-fix baseline — D7 Readout #2 + PostHog 2026-06-19→2026-07-05)

| Metric | D7 Readout #2 (2026-07-05) | PostHog funnel (same window, test accounts excluded) |
|---|---|---|
| Mature cohort `run_completed` (7d) | **0 / 12** | 0 users at `run_completed` |
| Onboarding drop | **94.7%** | (separate funnel; not WP-15 chain) |
| `plan_generated` | some reached plan | **1** user |
| `plan_run_cta_tapped` | — | **0** (0%) |
| `run_started` | — | **0** (0%) |
| `run_completed` | **0** | **0** (0%) |
| **Plan → run conversion** | **0%** | **0%** (0/1) |
| `first_run_cta_viewed` | — | **0** (sheet never shown — matches race root cause) |

**Interpretation (pre-fix):** Users who generated a plan never saw the first-run activation sheet (`first_run_cta_viewed`=0) because `presentFirstRunActivationIfNeeded` ran before async `regenerateTrainingPlan` finished. No bridge CTA, no run start. The 94.7% onboarding drop is a **separate upstream wall** (sign-in + 5 onboarding steps + 2 aha screens).

### After (build 21 cohort — pending)

| Metric | Value |
|---|---|
| Submission date | 2026-07-05 |
| Earliest readout date | **2026-07-08** (3+ days live usage) |
| Same-day PostHog (2026-07-05 only) | No data (expected — upload just completed) |
| Plan → run conversion | **TBD** — re-run query with `date_from: 2026-07-05`, filter to build 21 installs when `$app_version` / build property visible |

**WP-15 completion gate:** >=20% `plan_generated` → `run_completed` (via `plan_run_cta_tapped` + `run_started`) on next usable build-21 cohort.

### If the wall persists after build 21 (next likely causes, with evidence)

1. **Onboarding attrition (94.7%)** — still upstream; fix does not shorten onboarding. Users never reach `plan_generated`.
2. **Today `upNext` routing** — if first workout is not today, user may land on Today without obvious run CTA even after sheet fix (partially addressed PR #62; verify on device).
3. **Location / HealthKit denial at run start** — not instrumented; secondary for users who reach CTA but fail GPS/Health gate.
4. **Funnel timing** — `onboarding_completed` fires before async plan save finishes; can skew step-to-step timing in dashboards (instrumentation nuance, not the sheet race).

**Verdict (2026-07-05):** Fix shipped; **too early to measure post-fix lift**. Pre-fix PostHog confirms 0% plan-to-run and 0 `first_run_cta_viewed`, consistent with the diagnosed race. Re-query **2026-07-08+**.
