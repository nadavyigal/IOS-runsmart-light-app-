# Unified Training Context + AI Coach Context Integration

Status: Approved for implementation
Date: 2026-05-16

## Summary

Create a native iOS `TrainingContextSnapshot` so RunSmart Coach has one consistent, privacy-conscious view of the runner's current state.

The context should include profile, Today recommendation, plan, recovery, wellness, recent runs, route/report summaries, and honest missing-data limitations. This story integrates that context into native Coach chat calls without adding a live backend AI endpoint, Supabase schema, permissions, TestFlight, or screen redesign work.

## Goals

- Add typed Coach entry points for Today, Plan, Run, Report, and Profile.
- Build Coach context from existing service APIs instead of duplicating UI state.
- Summarize recent data with safe limits: 5 recent runs, 3 upcoming workouts, 3 routes, and 3 reports.
- Exclude raw GPS route coordinates from Coach context.
- Pass `TrainingContextSnapshot` into Coach send calls.
- Keep deterministic local fallback responses until a backend Coach endpoint is approved.

## Non-Goals

- No backend endpoint implementation.
- No Supabase table or RLS changes.
- No live AI call.
- No location, HealthKit, Garmin, signing, or TestFlight changes.
- No Coach screen redesign beyond a compact context panel.

## Acceptance Criteria

- Coach context is generated from existing RunSmart services.
- Today, Plan, Profile, and other existing Coach entry buttons still open the Coach sheet.
- Coach screen displays current context chips and honest limitations.
- Sending a Coach message uses `send(message:context:)`.
- Placeholder/fallback Coach response references context-specific facts when available.
- Tests cover context completeness, limits, coordinate omission, missing-data limitations, and fallback response variation.

## QA Plan

- Run focused XCTest for the new context and Coach fallback tests.
- Run a generic simulator build for `IOS RunSmart app`.
- Keep physical-device outdoor/background/battery QA tracked separately.
