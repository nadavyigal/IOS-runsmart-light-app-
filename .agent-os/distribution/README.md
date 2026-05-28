# RunSmart Project-Level Distribution Scaffold

Copy these files into the RunSmart repo at `.agent-os/distribution/`. They are the project-level distribution OS for RunSmart.

## How To Install

From inside the RunSmart repo:

```
mkdir -p .agent-os/distribution
cp -R "/Users/nadavyigal/Documents/Projects /Agentic OS/distribution-os/projects/runsmart/scaffold/"* .agent-os/distribution/
# Mirror positioning for marketingskills compatibility
mkdir -p .agents
cp .agent-os/distribution/product-positioning.md .agents/product-marketing.md
```

After install, edit each file to reflect the current state of RunSmart. The global Distribution OS reads these files when running workflows.

## Files In This Scaffold

- `README.md` (this file)
- `product-positioning.md` — used by every marketing skill as the foundation
- `audience.md`
- `channels.md`
- `messaging.md`
- `competitors.md`
- `seo-program.md`
- `app-store-program.md`
- `lifecycle-program.md`
- `gtm-plan.md` — populated by `distribution-os/workflows/13-gtm-plan.md`
- `experiment-backlog.md`
- `weekly-plan.md`
- `metrics.md`
- `assets-needed.md`
- `lessons.md`

## Update Cadence

- `product-positioning.md`, `audience.md`, `messaging.md`, `competitors.md`: quarterly or on major product change
- `channels.md`: monthly during strategy review
- `seo-program.md`, `app-store-program.md`, `lifecycle-program.md`: when the relevant program ships work
- `weekly-plan.md`, `experiment-backlog.md`, `assets-needed.md`: weekly
- `metrics.md`: weekly
- `lessons.md`: append as discovered
