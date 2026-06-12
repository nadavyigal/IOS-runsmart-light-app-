-- Hot-path indexes for code review Phase 3.7 (idempotent).

CREATE INDEX IF NOT EXISTS idx_garmin_activities_auth_activity
  ON public.garmin_activities (auth_user_id, activity_id);

CREATE INDEX IF NOT EXISTS idx_garmin_activities_auth_start_time
  ON public.garmin_activities (auth_user_id, start_time DESC);

CREATE INDEX IF NOT EXISTS idx_runs_auth_completed_at
  ON public.runs (auth_user_id, completed_at DESC);
