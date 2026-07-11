# WP-40 S3 + S4 Verification — 2026-07-10

## S3 — Confirm HealthKit data actually surfaces value once imported

**Method:** code-level verification pass (per packet: "No new UI unless a gap is found — this story is a verification pass"), cross-checked against real device evidence from S2 (a real HealthKit snapshot now exists on the founder's device after today's sync).

**Finding: no gap.** `SupabaseRunSmartServices.swift` confirms all three read paths are wired to real HealthKit-derived data, not dead code:

- `todayHealthSummary()` (~L1579) reads `store.loadHealthKitDailySnapshot()` for steps, active calories, sleep seconds.
- `recoverySnapshot()` (~L1589) falls back to HealthKit-derived readiness/sleep/HRV/resting-HR when no Garmin data exists, explicitly labeled `"Recovery data synced from Apple Health."`
- `wellnessSnapshot()` (~L1645) has the same Apple Health fallback, labeled `soreness: "Apple Health"` / `"... sleep from Health."`

`HealthKitSyncService.importHealthData()` (~L206) confirmed to call `localStore.saveHealthKitDailySnapshot(wellness)` as part of the same import that just ran in S2 — so the snapshot these three functions read was actually populated by today's real sync (4 workouts imported).

**Not completed:** a live on-device screenshot of Today/Recovery actually rendering this data — the USB tunnel to the device dropped mid-session (`devicectl` transport error) and the session moved on before reconnecting. The data path is confirmed correct at the code level and the snapshot exists on-device from S2's sync; a visual glance next time the app is open would close this out but isn't blocking given the code-level confirmation.

## S4 — Verify the funnel populates in PostHog

**Method:** queried PostHog project 171597 ("Running coach"), `filterTestAccounts=true`, per packet instruction to report actual counts.

**Funnel query** (`healthkit_disclosure_viewed` → `healthkit_connect_tapped` → `healthkit_sync_completed`, ordered, 14-day window, last 90 days):

| Step | Persons | Conversion |
|---|---:|---:|
| `healthkit_disclosure_viewed` | 9 | 100% |
| `healthkit_connect_tapped` | 7 | 77.78% |
| `healthkit_sync_completed` | 5 | 55.56% |

**This is not evidence of real-user adoption of the new S1 flow — read carefully before citing it.** Three things caveat this number:

1. **S1 hasn't shipped yet.** PR #84 (this work) is still an unmerged draft. Nobody outside this session has been able to reach the new onboarding-embedded Connect button. All 9/7/5 above are from the **pre-existing Profile-tab path**, which is exactly what WP-39 already found "fires, but near zero from real users."
2. **The daily event trend shows QA-burst patterns, not organic usage:** `healthkit_sync_completed` (raw event count, not persons) shows 0 for the first two months of the window, then spikes of **27 on 06-17** and **23 on 06-23** — clearly repeated dev/QA taps on manual Sync during earlier development, not 20+ real users syncing in a day. Today (07-10) shows 1 event, which is very likely this session's own device QA (the founder's live phone, just used above for S2).
3. **The 5 converted "persons" are anonymous distinct IDs with no email/name attached** — consistent with dev/simulator/device test identities, not identified real users, per the standing exclusion practice for this portfolio's PostHog reads.

**Honest conclusion:** the funnel mechanics work correctly (events exist, fire, and compute a real funnel) — but there is currently **no real-user data to report**, because the feature this funnel is meant to measure (S1's onboarding-embedded Connect) hasn't been merged or shipped. This matches the packet's own instruction: S4 is meant to run "after S1-S3 ship and get real usage" — that step is still ahead of this session, not behind it. Re-run this exact funnel query after PR #84 merges and a real cohort has had time to onboard.
