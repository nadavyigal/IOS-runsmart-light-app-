-- Owner-scoped RLS for Garmin activity data and runs (code review P0).
-- Safe to re-run: uses DROP POLICY IF EXISTS before CREATE.

-- garmin_activity_points is a view over garmin_activities telemetry_json in
-- production. Run it as the querying user so garmin_activities RLS is enforced.
ALTER VIEW IF EXISTS public.garmin_activity_points SET (security_invoker = true);

ALTER TABLE IF EXISTS public.garmin_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS garmin_activities_select_own ON public.garmin_activities;
CREATE POLICY garmin_activities_select_own
  ON public.garmin_activities
  FOR SELECT
  TO authenticated
  USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS runs_select_own ON public.runs;
CREATE POLICY runs_select_own
  ON public.runs
  FOR SELECT
  TO authenticated
  USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS runs_insert_own ON public.runs;
CREATE POLICY runs_insert_own
  ON public.runs
  FOR INSERT
  TO authenticated
  WITH CHECK (auth_user_id = auth.uid());

DROP POLICY IF EXISTS runs_update_own ON public.runs;
CREATE POLICY runs_update_own
  ON public.runs
  FOR UPDATE
  TO authenticated
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

DROP POLICY IF EXISTS runs_delete_own ON public.runs;
CREATE POLICY runs_delete_own
  ON public.runs
  FOR DELETE
  TO authenticated
  USING (auth_user_id = auth.uid());
