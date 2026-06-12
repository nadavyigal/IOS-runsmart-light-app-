-- Owner-scoped RLS for Garmin activity data and runs (code review P0).
-- Safe to re-run: uses DROP POLICY IF EXISTS before CREATE.

ALTER TABLE IF EXISTS public.garmin_activity_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.garmin_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS garmin_activity_points_select_own ON public.garmin_activity_points;
CREATE POLICY garmin_activity_points_select_own
  ON public.garmin_activity_points
  FOR SELECT
  TO authenticated
  USING (auth_user_id = auth.uid());

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
