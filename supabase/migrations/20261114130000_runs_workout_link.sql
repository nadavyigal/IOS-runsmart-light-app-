-- Runs link to the workout they completed (Story 0.2).
-- Idempotent: safe to re-run. Every step is skipped when already applied or
-- when a table is missing, so it also runs on schemas without `workouts`.
--
-- WEB REPO: this must also be copied into the web migration tree
-- (Running-coach-/v0/supabase/migrations/).
--
-- Live-schema check (production dxqglotcyirxzyqaxqln, 2026-11-14):
-- runs.workout_id did not exist. runs.id is bigint, workouts.id is uuid.
-- Existing owner RLS on runs (runs_update_own) already lets the signed-in
-- user set the column on their own rows, so no policy change is needed.

do $$
begin
    if to_regclass('public.runs') is null then
        raise notice 'public.runs is missing; skipping workout link';
        return;
    end if;

    alter table public.runs
        add column if not exists workout_id uuid;

    -- FK only when workouts exists and the constraint is not there yet.
    -- ON DELETE SET NULL: deleting a workout unlinks the run, never deletes it.
    if to_regclass('public.workouts') is not null
       and not exists (
           select 1
           from pg_constraint
           where conrelid = 'public.runs'::regclass
             and conname = 'runs_workout_id_fkey'
       ) then
        alter table public.runs
            add constraint runs_workout_id_fkey
            foreign key (workout_id) references public.workouts (id)
            on delete set null;
    end if;

    -- A workout links to at most one run. Unlinked runs (null) are unlimited.
    create unique index if not exists runs_workout_id_unique
        on public.runs (workout_id)
        where workout_id is not null;
end
$$;
