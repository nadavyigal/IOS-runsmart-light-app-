-- Shared fixtures for the C7.6 AC6 adherence parity (partial 80%, rest, extra,
-- time zone). One list, read by both sides:
--   * supabase/tests/workout_adherence_state.sql includes this file (\ir) and checks
--     workout_adherence_boundary and workout_adherence_state on every case.
--   * IOS RunSmart appTests/WorkoutAdherenceParityTests.swift reads the JSON
--     array inside the dollar-quoted block below and checks WorkoutAdherence.missedBoundary
--     and WorkoutAdherence.classify / counts on the same cases.
-- Change a case here and both tests run it. Keep the JSON plain (no comments).
--
-- Fields: type null means no workout (a run on its own). run_distance_km and
-- run_duration_seconds both null mean no run. now and time_zone give the boundary
-- (the missed cutoff is 20:00 local).

create temp table workout_adherence_fixtures as
select *
from jsonb_to_recordset($fixtures$
[
  {"name": "partial below 80% of distance", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": 3.99, "run_duration_seconds": 1500, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "partial"},
  {"name": "done at exactly 80% of distance", "type": "tempo", "planned_distance": 5, "planned_duration_minutes": 30, "scheduled_date": "2026-11-23", "run_distance_km": 4, "run_duration_seconds": 60, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "done"},
  {"name": "distance wins over duration", "type": "easy", "planned_distance": 10, "planned_duration_minutes": 50, "scheduled_date": "2026-11-23", "run_distance_km": 7.99, "run_duration_seconds": 6000, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "partial"},
  {"name": "done at exactly 80% of duration", "type": "easy", "planned_distance": 0, "planned_duration_minutes": 30, "scheduled_date": "2026-11-23", "run_distance_km": 0, "run_duration_seconds": 1440, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "done"},
  {"name": "partial below 80% of duration", "type": "easy", "planned_distance": 0, "planned_duration_minutes": 30, "scheduled_date": "2026-11-23", "run_distance_km": 0, "run_duration_seconds": 1439, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "partial"},
  {"name": "no target means any run is done", "type": "easy", "planned_distance": 0, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": 0.5, "run_duration_seconds": 60, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "done"},
  {"name": "rest is never counted", "type": "rest", "planned_distance": 0, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "rest"},
  {"name": "rest with spaces and capitals", "type": " Rest ", "planned_distance": 0, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": 5, "run_duration_seconds": 1800, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "rest"},
  {"name": "a run with no workout is extra", "type": null, "planned_distance": null, "planned_duration_minutes": null, "scheduled_date": null, "run_distance_km": 5, "run_duration_seconds": 1800, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "extra"},
  {"name": "no run at 20:00 is missed", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-23T18:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "missed"},
  {"name": "no run at 19:59 is still planned", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-23T17:59:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-23", "state": "planned"},
  {"name": "yesterday with no run is missed in the morning", "type": "long", "planned_distance": 12, "planned_duration_minutes": null, "scheduled_date": "2026-11-22", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-23T06:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-23", "state": "missed"},
  {"name": "a future day is planned", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-25", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-23T19:00:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "planned"},
  {"name": "same instant, New York is before its cutoff", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-24T00:30:00Z", "time_zone": "America/New_York", "boundary": "2026-11-23", "state": "planned"},
  {"name": "same instant, Jerusalem is past its cutoff", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-24T00:30:00Z", "time_zone": "Asia/Jerusalem", "boundary": "2026-11-24", "state": "missed"},
  {"name": "New York on the last summer-time evening", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-10-31", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-01T00:00:00Z", "time_zone": "America/New_York", "boundary": "2026-11-01", "state": "missed"},
  {"name": "New York on the first winter-time evening, 19:30", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-01", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-02T00:30:00Z", "time_zone": "America/New_York", "boundary": "2026-11-01", "state": "planned"},
  {"name": "Kolkata half-hour zone at 20:00", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-23T14:30:00Z", "time_zone": "Asia/Kolkata", "boundary": "2026-11-24", "state": "missed"},
  {"name": "Kolkata half-hour zone at 19:59", "type": "easy", "planned_distance": 5, "planned_duration_minutes": null, "scheduled_date": "2026-11-23", "run_distance_km": null, "run_duration_seconds": null, "now": "2026-11-23T14:29:00Z", "time_zone": "Asia/Kolkata", "boundary": "2026-11-23", "state": "planned"}
]
$fixtures$::jsonb) as f(
  name text,
  type text,
  planned_distance numeric,
  planned_duration_minutes integer,
  scheduled_date date,
  run_distance_km numeric,
  run_duration_seconds integer,
  now timestamptz,
  time_zone text,
  boundary date,
  state text
);
