# RunSmart 1.0.9 (23) — Sign in with Apple device test

**Date:** 2026-07-19  
**Status:** **BLOCKED — no clean SIWA attempt completed on the target binary today**  
**Binary under test:** Public App Store **1.0.9 (23)** (`com.runsmart.lite`)  
**PostHog:** Running coach (`171597`, UTC)  
**Supabase:** Run-Smart (`dxqglotcyirxzyqaxqln`, read-only inspection)

## Release context

| Item | Value |
|---|---|
| Public App Store version (iTunes lookup, 2026-07-19) | **1.0.9** |
| Target build for this test | **23** |
| ASC submission today | **1.1.0 (24)** submitted for review (Adaptive Coach flag ON) |
| Binary tested in this session | **1.0.9 (23) only** — **1.1.0 (24) was not installed or exercised** |

## Objective

Install public RunSmart **1.0.9 (23)** on the founder physical device and attempt **Sign in with Apple (SIWA)** once using a **non-destructive** account path (sign out / uninstall only — no delete account). Record:

1. UTC timestamp of the attempt  
2. Exact visible UI result  
3. Whether onboarding opens  

If SIWA fails: capture the user-facing error and inspect Supabase Apple provider config (read-only). **No code or ASC changes were made.**

## Session summary

| Step | UTC time | Result |
|---|---|---|
| Pre-test install confirmed | Before `2026-07-19T12:11:11Z` | Public **1.0.9 (23)** installed; app launched to **Today** already signed in (`Good afternoon, RunSma…`, Tempo workout visible) |
| First uninstall (local session reset) | `2026-07-19T12:11:11Z` | App removed; server account preserved |
| App Store reinstall opened | ~`2026-07-19T12:12Z` | Listing showed **Version 1.0.9**; cloud-download affordance visible |
| Post-reinstall launch | ~`2026-07-19T12:14Z` | Returned to **Today signed in** — **SignInView not reached** |
| Second uninstall (retry clean SIWA path) | `2026-07-19T12:16:49Z` | App removed again |
| Post-second-uninstall launch | ~`2026-07-19T12:17Z` | `devicectl` launch failed — **app not installed** |
| Device transport | ~`2026-07-19T12:20Z` onward | Founder iPhone reported **`unavailable`** in `devicectl`; CoreDevice could not match device |
| iPhone Mirroring | Intermittent | Brief Today view visible at ~15:14 local; later **locked** (Mac Touch ID/password required) |
| **Clean SIWA attempt on 1.0.9 (23)** | — | **Not completed** |

## SIWA attempt result (today)

| Field | Value |
|---|---|
| Attempt UTC timestamp | **None** — test blocked before SignInView |
| Visible UI result | N/A (never reached SIWA button on a confirmed clean 1.0.9 session today) |
| Onboarding opened? | **No** — pre-test state was already onboarded on Today |
| User-facing error captured | **No** — no SIWA tap recorded on 1.0.9 (23) today |

### Expected failure copy (code contract)

If SIWA fails on build 23, `SignInView` maps non-cancel Apple failures to:

> **Apple sign-in didn't finish. Nothing was created — tap to try again.**

Raw `ASAuthorizationError` strings (e.g. `error 1000`) are analytics-only via `sign_in_failed`, not shown in UI (`SignInView.swift`, WP-43).

If Supabase token exchange fails after Apple succeeds, `SupabaseSession` may surface:

> **Apple sign-in could not complete. Verify the Supabase Apple provider and native bundle ID audience.**

## Telemetry cross-check (PostHog, UTC)

### Build 23 (`$app_build = 23`) — relevant history

| Event | Count | Notes |
|---|---:|---|
| `sign_in_failed` on 2026-07-15 | **5** | All `com.apple.AuthenticationServices.AuthorizationError` / **1000**; `$app_version = 1.0.9` |
| `sign_in_completed` (method `apple`) | **1** | `2026-07-16T06:26:03Z` on build 23 |
| `sign_in_failed` on 2026-07-19 | **0** | No build-23 failures today |
| `sign_in_completed` on 2026-07-19 | **0** | No build-23 successes today |

### Build 24 (`$app_version = 1.1.0`) — **not the test binary**

| Event | Count | Notes |
|---|---:|---|
| `sign_in_failed` on 2026-07-19 | **2** | `11:03:52Z` and `11:04:06Z`; `ASAuthorizationError` **1000** — likely from separate 1.1.0 activity, **excluded from this 1.0.9 (23) verdict** |

**Interpretation:** Historical build-23 SIWA failures exist (July 15 cluster). SIWA can succeed on build 23 (July 16). Today's session did not add new build-23 SIWA telemetry because no attempt reached the button on a verified clean 1.0.9 install.

## Supabase Apple provider (read-only)

| Check | Result |
|---|---|
| Project status | `ACTIVE_HEALTHY` |
| Apple identities in `auth.identities` | **8** rows (`provider = 'apple'`) |
| Most recent Apple identity `created_at` | `2026-07-16T06:26:02Z` (aligns with build-23 `sign_in_completed`) |
| `auth.custom_oauth_providers` | Empty |
| Dashboard provider secrets (Services ID, key, team ID) | **Not readable via SQL/MCP** — stored in Supabase Auth dashboard, not `auth.*` tables |

**Read-only conclusion:** Apple auth is operational in production (identities exist; a build-23 success was recorded July 16). The July 15 build-23 `ASAuthorizationError 1000` cluster points to an **Apple authorization-layer failure before Supabase token exchange**, not a missing provider row. Full provider secret / audience alignment (bundle ID `com.runsmart.lite`, Services ID, redirect URL) still requires a founder-gated dashboard check if failures reproduce on device.

Native entitlements on the reviewed app include `com.apple.developer.applesignin = Default` (`RunSmart.entitlements`).

## Blockers

1. **CoreDevice unavailable** — founder iPhone remained `unavailable` to `devicectl` after second uninstall; could not verify reinstall, launch, or capture device logs.  
2. **iPhone Mirroring locked** — requires Mac login (Touch ID/password); automation could not reach Profile → Sign Out.  
3. **Session persistence** — first reinstall returned to Today signed-in without exposing SignInView, so a non-destructive sign-out path was still required.  
4. **No alternate sideload path** — no 1.0.9 (23) IPA on disk; test must use public App Store binary.

## Screenshots (local, not committed)

Captured under `/tmp/` during the session (device names redacted in this report):

- `appstore-runsmart.png` — App Store listing **Version 1.0.9**
- `runsmart-fresh-launch.png`, `runsmart-profile*.png` — Today signed-in state
- `mirror-current.png` — iPhone Mirroring locked gate

## Founder unblock checklist (to finish this test)

1. Connect founder iPhone via USB, unlock, and trust the Mac if prompted.  
2. Unlock **iPhone Mirroring** on the Mac (Touch ID or password).  
3. From App Store, install **RunSmart 1.0.9** (public track — not TestFlight 1.1.0).  
4. Confirm install: version **1.0.9**, build **23**, bundle `com.runsmart.lite`.  
5. If app opens to Today signed-in: **Profile → Sign Out** (do **not** delete account).  
6. Tap **Sign in with Apple** once; record UTC time, exact on-screen result, and whether onboarding opens.  
7. If failure UI appears, note whether copy matches the WP-43 mapped string above.

## Verdict

**INCOMPLETE.** Public **1.0.9 (23)** was the intended and only target binary. **1.1.0 (24)** is in App Store Connect review (submitted 2026-07-19) but was **not** tested here. A clean SIWA attempt on 1.0.9 (23) did not occur today due to device/mirroring blockers after session-reset uninstalls. Historical telemetry shows build-23 SIWA can fail (`ASAuthorizationError 1000`, July 15) and can succeed (July 16); no new build-23 SIWA events were emitted during this blocked session.

**No code, ASC, or Supabase configuration changes were made.**
