-- The unique index created for iOS upsert conflict handling also covers lookup
-- by (auth_user_id, challenge_id), so the non-unique duplicate is unnecessary.

DROP INDEX IF EXISTS public.idx_challenge_enrollments_auth_challenge;
