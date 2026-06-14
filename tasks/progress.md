Status: 1.0.2 build 14 smoke-test blocker fixes are source-complete locally. Do not archive/resubmit yet; production deploys and live smoke are still required.
Current Phase: 1.0.2 build 14 - delete-account and Garmin-connect regression fix validation
Active Story: Deploy updated Supabase `delete_account` and RunSmart web Garmin gateway, then rerun live SIWA -> Garmin connect -> delete account -> register/sign in again smoke.
Last Completed Story: Patched `delete_account` to skip the production `garmin_activity_points` view; patched iOS Garmin OAuth to complete the callback exchange; patched web Garmin gateway to support native `runsmart://` redirects and signed native identity context (2026-06-14).
Next Recommended Story: Deploy the Edge Function and Vercel web gateway, then rerun live smoke on an Apple-auth-capable simulator/device before App Store archive/resubmission.
Estimated Completion: Pending backend/web deployment plus live smoke (approx 45-90 min after deploy access is available).
Blockers: Supabase CLI/token and Vercel deploy permissions are unavailable in this session; live delete-account and Garmin-connect smoke cannot pass until deployed code is live.
Last Validation: 2026-06-14 iOS simulator build passed with signing disabled; RunSmart web `npm run type-check` passed; `git diff --check` passed in both iOS and web repos; Deno validation was not run because `deno` is not installed.
Last Updated: 2026-06-14
