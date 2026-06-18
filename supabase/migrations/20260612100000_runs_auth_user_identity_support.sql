-- Support iOS UUID-first identity writes introduced by the code-review fix.
-- Idempotent: safe to run after older production schemas.

ALTER TABLE IF EXISTS public.runs
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id);

UPDATE public.runs r
SET auth_user_id = p.auth_user_id
FROM public.profiles p
WHERE r.auth_user_id IS NULL
  AND r.profile_id = p.id
  AND p.auth_user_id IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'runs_auth_user_id_fkey'
      AND conrelid = 'public.runs'::regclass
  ) THEN
    ALTER TABLE public.runs
      ADD CONSTRAINT runs_auth_user_id_fkey
      FOREIGN KEY (auth_user_id) REFERENCES auth.users(id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS challenge_enrollments_auth_challenge_unique
  ON public.challenge_enrollments (auth_user_id, challenge_id);
