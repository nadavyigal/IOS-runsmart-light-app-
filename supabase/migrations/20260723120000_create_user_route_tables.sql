-- Route library cloud persistence (WP: route feature review, 2026-07-23).
--
-- The iOS app has shipped RouteRepository.swift reads/writes against these two
-- tables since the route feature landed, but the tables were never created in
-- the production project — every fetch failed, the app silently fell back to
-- device-local storage, and users lost saved routes and benchmarks on
-- reinstall. This migration creates the tables the client already expects.
--
-- NOT applied automatically. Apply via Supabase MCP/dashboard after founder
-- approval.

CREATE TABLE IF NOT EXISTS public.user_saved_routes (
  id                    UUID PRIMARY KEY NOT NULL,
  user_id               UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  distance_meters       FLOAT8 NOT NULL,
  elevation_gain_meters INT4 NOT NULL DEFAULT 0,
  points_json           JSONB,         -- compact [[lat,lon,unix_ts,accuracy]], null if GPS storage disabled
  source                TEXT NOT NULL, -- 'recorded' | 'garmin' | 'generated' | 'manual'
  tags                  TEXT[] NOT NULL DEFAULT '{}',
  notes                 TEXT NOT NULL DEFAULT '',
  is_favorite           BOOL NOT NULL DEFAULT false,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_saved_routes ENABLE ROW LEVEL SECURITY;

-- Owner-scoped, per-command policies with WITH CHECK on writes so a user can
-- neither read nor write another user's rows (see lessons.md: permissive
-- policies combine, so keep exactly one owner policy per command).
CREATE POLICY "saved_routes_select_own" ON public.user_saved_routes
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY "saved_routes_insert_own" ON public.user_saved_routes
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "saved_routes_update_own" ON public.user_saved_routes
  FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "saved_routes_delete_own" ON public.user_saved_routes
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE INDEX IF NOT EXISTS idx_user_saved_routes_user_id
  ON public.user_saved_routes (user_id);

CREATE TABLE IF NOT EXISTS public.user_benchmark_routes (
  id             UUID PRIMARY KEY NOT NULL,
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  saved_route_id UUID NOT NULL REFERENCES public.user_saved_routes(id) ON DELETE CASCADE,
  enabled_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_benchmark_routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "benchmark_routes_select_own" ON public.user_benchmark_routes
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY "benchmark_routes_insert_own" ON public.user_benchmark_routes
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "benchmark_routes_update_own" ON public.user_benchmark_routes
  FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "benchmark_routes_delete_own" ON public.user_benchmark_routes
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE INDEX IF NOT EXISTS idx_user_benchmark_routes_user_id
  ON public.user_benchmark_routes (user_id);
CREATE INDEX IF NOT EXISTS idx_user_benchmark_routes_saved_route_id
  ON public.user_benchmark_routes (saved_route_id);
