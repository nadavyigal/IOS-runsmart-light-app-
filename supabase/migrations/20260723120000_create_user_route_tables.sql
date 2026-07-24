-- Route library cloud persistence (WP: route feature review, 2026-07-23).
--
-- The iOS app has shipped RouteRepository.swift reads/writes against these two
-- tables since the route feature landed, but the tables were never created in
-- the production project — every fetch failed, the app silently fell back to
-- device-local storage, and users lost saved routes and benchmarks on
-- reinstall. This migration creates the tables the client already expects.
--
-- Applied to production project dxqglotcyirxzyqaxqln on 2026-07-23 with
-- founder approval.

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
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- `source` maps 1:1 onto the Swift `RouteSource` enum; an unexpected value
  -- would make `RouteSource(rawValue:)` return nil and the row would silently
  -- vanish from the user's library on decode.
  CONSTRAINT user_saved_routes_source_check
    CHECK (source IN ('recorded', 'garmin', 'generated', 'manual')),
  CONSTRAINT user_saved_routes_nonneg_check
    CHECK (distance_meters >= 0 AND elevation_gain_meters >= 0),
  -- Target for the ownership-enforcing composite FK on user_benchmark_routes.
  CONSTRAINT user_saved_routes_id_user_id_key UNIQUE (id, user_id)
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
  saved_route_id UUID NOT NULL,
  enabled_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Composite FK, not a plain FK on saved_route_id: RLS only proves the row's
  -- own user_id is the caller, so a bare FK would let an authenticated user
  -- benchmark someone else's route id. The client relies on the inverse
  -- ("a benchmark always points at one of my saved routes") when it resolves
  -- savedRouteID against savedRoutes() to open route detail.
  CONSTRAINT user_benchmark_routes_route_owned_fkey
    FOREIGN KEY (saved_route_id, user_id)
    REFERENCES public.user_saved_routes (id, user_id) ON DELETE CASCADE,
  -- One benchmark per route: the local store and RouteSync.mergeBenchmarks
  -- both dedupe by savedRouteID, so duplicates here would be silently dropped.
  CONSTRAINT user_benchmark_routes_user_route_key UNIQUE (user_id, saved_route_id)
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
