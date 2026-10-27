# Squads (Pickteams) Constitution

## Core Principles

### I. Feature-First Clean Architecture

- Code in `app/lib/features/<feature>/` MUST be split into `domain/`, `application/`,
  `infrastructure/` and `presentation/`; cross-feature code lives in `app/lib/core/`.
- `domain/` MUST NOT import Flutter, Riverpod, Supabase or any other infrastructure package.
- Supabase clients, `flutter_dotenv` and other external SDKs MUST be used only in
  `infrastructure/`; presentation reaches data exclusively through use cases and repositories.
- Repositories MUST map external exceptions to domain `Failure` types; presentation consumes
  state via Riverpod `AsyncValue` and surfaces errors through `ref.listen` side effects.
- Widgets stay lean: business rules belong in `application/` or `domain/`, never in `build`.

Rationale: the app is rebuilt from scratch to escape the legacy UI's coupling; layer rules are
what keeps features independently testable and replaceable.

### II. Database as the Security Boundary

- Every table exposed through PostgREST MUST have Row Level Security enabled with explicit
  policies; client-side checks are UX only and never count as authorization.
- Role rules (Owner, Admin, Member, guest) and hard limits (e.g. one squad per owner,
  100 players per squad, 16 players per draft) MUST be enforced in the database through
  policies, constraints, triggers or RPC functions.
- Schema changes MUST go through a new timestamped migration in `supabase/migrations/`, one
  per change request, with a header comment explaining the decision. Applied migrations MUST
  NOT be edited; fix forward with a new migration.
- Secrets MUST NOT be committed. Only the publishable (anon) key may reach the client.

Rationale: a Flutter web client is fully inspectable; the only trustworthy enforcement point is
PostgreSQL with RLS.

### III. Deterministic Drafts, Event-Sourced Rankings

- Draft generation MUST be deterministic: the same players, rankings and parameters MUST
  produce the same ordered list of proposals, sorted best to worst by balance score.
- Draft algorithms MUST be pure functions in `domain/` (no I/O, no clock, no unseeded
  randomness) so they can be reproduced and unit-tested.
- A player's ranking MUST be derivable from the history of deltas (`ranking_history`).
  Recording a match appends deltas only for players who played; correcting a result MUST
  adjust the corresponding delta, never silently overwrite a ranking.
- Any change to ranking, win-probability or balance math MUST document the formula in the
  feature doc or spec and keep historical data consistent (migration or recompute plan).

Rationale: fairness is the product. Users must be able to trust and reproduce why teams were
split and why rankings moved.

### IV. Paired Tests for Every Change

- Every new or changed use case, provider or domain service MUST ship with at least one
  happy-path and one failure-path test in `app/test/`, mirroring the source folder path and
  named `<feature>_<behavior>_test.dart`.
- Every migration MUST be paired with a SQL test in `supabase/tests/` asserting its RLS
  policies, constraints or function results.
- Changes to drafting or ranking math MUST include tests covering determinism and edge cases
  (odd player counts, ties, the 16-player limit) and MUST NOT lower coverage of that code.
- `flutter analyze` and `flutter test` MUST pass locally and in CI before merge.

Rationale: a single maintainer cannot manually re-verify balance math and access rules on
every change; tests are the regression net.

### V. MVP Scope and Simplicity

- Features MUST trace back to `docs/prd.md` or an approved spec in `specs/`; scope beyond
  that requires a spec first.
- Prefer the simplest solution that satisfies the spec (YAGNI). New dependencies, new layers
  or abstractions without a second concrete use MUST be justified in the plan's
  Complexity Tracking.
- MVP targets football and Flutter web; multi-sport or native-platform work is out of scope
  until the PRD says otherwise.

Rationale: the project is built and maintained by one person; unjustified complexity is the
main risk to shipping.

## Technology & Security Constraints

- Frontend: Flutter (Dart) for web, Riverpod for state, GoRouter for routing, fl_chart for
  charts. Formatting by `dart format` (2-space indent, trailing commas on multiline literals);
  files `snake_case.dart`, types `PascalCase`, Riverpod instances suffixed with `Provider`.
- Backend: Supabase only — Auth, PostgREST, RPC (SQL functions), triggers; Edge Functions
  (Deno/TypeScript) only when logic cannot live in SQL. No custom application server.
- Hosting: Supabase Cloud for backend, Vercel for the Flutter web build; CI on GitHub Actions.
- Environment: `app/.env` copied from `app/.env.EXAMPLE`; keys read via `flutter_dotenv` in
  infrastructure only. Redact Supabase URLs and keys in issues, PRs and notes.
- Legacy Squads code (Flutter + Python repo) is UX inspiration only; no code is copied.

## Development Workflow

- Non-trivial features follow Spec Kit: `/speckit-specify` → (`/speckit-clarify`) →
  `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`, with artifacts in
  `specs/NNN-feature/`. Small fixes MAY skip specs but still obey all principles.
- Every plan MUST pass a Constitution Check against Principles I–V before implementation;
  violations are recorded in Complexity Tracking with justification or the plan is revised.
- Work happens on short-lived branches (`feat/`, `fix/`, `chore/`, `docs/`) merged into
  `main` via pull request. Direct pushes to `main` are not allowed.
- Commits and PRs are in English and follow Conventional Commits (`feat(draft): …`); one
  feature or one migration batch per commit; avoid mixing Supabase and Flutter changes unless
  tightly coupled.
- PRs MUST include a summary, a test plan (commands run), screenshots for UI changes and the
  IDs of any Supabase migrations. CI (`analyze`, `test`, `web-build`) MUST be green.
- After a feature lands, update its current-state doc in `docs/features/<feature>.md`.

## Governance

- This constitution supersedes `AGENTS.md`, `docs/` and other guidance where they conflict;
  those documents MUST be updated to match when an amendment lands.
- Amendments are made via `/speckit-constitution` in a pull request that states the change,
  the rationale and any migration of existing code or specs. The maintainer (Netherman2440)
  approves amendments.
- Versioning follows semantic versioning: MAJOR for removing or redefining a principle,
  MINOR for adding a principle or section or materially expanding guidance, PATCH for
  clarifications and wording.
- Compliance is checked at three points: the Constitution Check in every `plan.md`,
  `/speckit-analyze` before implementation, and PR review. Known violations in existing code
  are tracked as follow-up tasks rather than tolerated silently.
- Runtime development guidance for agents lives in `AGENTS.md`.

**Version**: 1.0.0 | **Ratified**: 2026-10-27 | **Last Amended**: 2026-10-27
