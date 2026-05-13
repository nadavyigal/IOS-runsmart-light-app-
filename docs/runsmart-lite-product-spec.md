# RunSmart Lite Product Spec

## Vision

RunSmart Lite is a native iOS running coach that makes the next right workout obvious. The app should feel premium, calm, and decisive: the user opens it, sees the coach recommendation, and can start running or ask a question without digging through dense analytics.

## Information Architecture

- Today: current coach recommendation, readiness, workout CTA, progress, and short coach conversation.
- Plan: week-first training plan with month context and coach briefing.
- Run: pre-run and live run experience with coach cues and core metrics.
- Profile: runner identity, progress, achievements, preferences, and connected services.
- Coach: launched as a modal flow from context-specific CTAs.

## First Viewport Rules

- Today must show greeting, coach card, readiness/workout recommendation, and Start Workout.
- Plan must show title, AI coach briefing, current week strip, and upcoming coach notes.
- Run must show live/pre-run coach, core metrics, route/map panel, and primary controls.
- Profile must show identity, stats, coach persona, and settings highlights.

## Progressive Disclosure

- Keep primary screens action-oriented and compact.
- Use cards as entry points to secondary flows rather than inline long forms.
- Keep advanced device, recovery, and notification settings behind Profile.
- Avoid a permanent fifth Coach tab in V1.

## Scope

### V1

- Four-tab SwiftUI shell.
- Mock-backed content for Today, Plan, Run, and Profile.
- Coach sheet scaffold.
- Service protocols for future integration.
- Release and QA readiness docs.

### V1.1

- Live API clients for auth, plan, workouts, coach chat, and run logging.
- Location and HealthKit permission flows.
- Persistence for preferences and completed run summaries.

### Later

- Community/social features.
- Leaderboards.
- Long-form analytics and full training history.
