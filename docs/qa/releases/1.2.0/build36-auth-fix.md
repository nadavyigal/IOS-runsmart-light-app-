# 1.2.0 (36) — repair the invalid packaged API key

Founder could not sign in with Apple in build 35. Supabase edge logs show /auth/v1/token requests rejected at the API gateway with UNAUTHORIZED_INVALID_API_KEY. A request using the key extracted from the actual build-35 archive returned HTTP 401 Invalid API key. The active enabled publishable key from the intended project returned HTTP 200 from /auth/v1/settings, with Apple and email providers enabled.

Corrected the committed client default and the ignored local override to that existing enabled public client key. No backend keys were created, rotated or revoked, and no authentication protections or RLS policies were changed. Build 36 is required because 35 is already uploaded. Build 35 is not ready for production; its earlier configuration-presence verification missed the live rejection.

Added scripts/verify-release-backend.py: checks the key extracted from an actual built app against live Auth settings, requires both shipping providers, never uses user credentials, and fails closed on network or HTTP errors. Fastlane beta/release now run it before upload. This checks the API gateway/provider configuration; it does not prove a real Apple account can complete the full device authorization flow.

Validation and build-36 TestFlight distribution results will be recorded after completion. Physical locked-phone/GPS/Health tests remain owner-required. Do not reset the founder's password or create a second account as an API-key workaround.
