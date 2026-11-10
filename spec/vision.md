# Vision

> Human-owned durable intent for every role. Keep this file at or below 1000 lines. The injected copy is capped at 1000 lines; keep each item high-signal and move supporting history to feature notes. The coordinator may propose changes but does not invent or rewrite this intent unprompted.

## Product principles

- Pickteams ends the chaos of amateur team selection: deterministic, sorted, balanced draft proposals instead of arguments.
- Rankings are earned on the pitch: every match updates them through event-sourced deltas; corrections adjust the delta, history stays auditable.
- Bounded MVP over feature count: football only, one squad per owner, up to 100 players, drafts capped at 16 players.
- Greenfield Flutter + Supabase; the old squads Flutter+Python repo is legacy UX inspiration (flows, layout, copy), not code to reuse.
- Fairness and simplicity for amateur organizers beat configurability.

## Current direction

- The main goal of this repository is to rebuild Pickteams for mobile; docs/prd.md stays the product definition.
- MVP scope: accounts with roles and invitations, squads, players, deterministic drafting, match results with score_meta, simple tournaments, basic stats and ranking trends.
- Clean Architecture, feature-first layout in Flutter (docs/mvp.md, docs/tech-stack.md); the existing web client is the codebase the mobile rebuild reworks.
- Draft quality is the product: 20 sorted proposals with balance scores is the bar; degrade honestly rather than silently.
