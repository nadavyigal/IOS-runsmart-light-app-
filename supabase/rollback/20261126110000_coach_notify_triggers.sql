-- Rollback for 20261126110000_coach_notify_triggers.sql (C7.5 push triggers).
-- Stops the insert pushes. Keeps every table and row; held pushes stay in
-- deferred_pushes. The Vault entries and the crons are separate (runbook section 7).

drop trigger if exists coach_notify_runs on public.runs;
drop trigger if exists coach_notify_flags on public.athlete_run_flags;
drop trigger if exists coach_notify_notes on public.coach_feedback;
drop trigger if exists coach_notify_replies on public.coach_feedback_replies;
drop function if exists public.coach_notify_webhook();
