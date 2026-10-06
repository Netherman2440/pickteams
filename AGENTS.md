# Repository Guidelines

## Project Structure & Module Organization
- `app/` hosts the Flutter web client; follow the feature-first layout in `app/lib/` (`features/auth`, `features/squads`, shared `core/`).
- UI assets live under `app/web/` and generated db mocks in `app/db/`; keep tests in `app/test/` mirrored to the feature they cover.
- Supabase SQL, migrations, and seed scripts go in `supabase/`; keep one migration per change request and document schema decisions in migration headers.
- Product direction and architecture references live in `docs/`; skim `prd.md` before starting large efforts so UX/role constraints stay aligned.

## Build, Test, and Development Commands
- `cd app && flutter pub get` installs packages.
- `cd app && flutter run -d chrome` runs the web dev server with hot reload.
- `cd app && flutter analyze` enforces lint rules from `analysis_options.yaml`.
- `cd app && flutter build web` produces the deployable bundle into `app/build/web/`.
- `supabase db push` (inside `supabase/`) applies schema migrations to a linked project; `supabase start` bootstraps the local stack.

## Coding Style & Naming Conventions
- Run `dart format .` prior to committing; the repo expects 2-space indentation and trailing commas for multiline literals to aid formatter diffing.
- Dart files must use `snake_case.dart`; classes and enums in `PascalCase`, providers/use-cases in `UpperCamel`, and Riverpod instances suffixed with `Provider`.
- Widgets stay lean: keep UI in `presentation/`, business logic in `application/`, and DTOs/entities in `domain/` per Clean Architecture; add brief file-level doc comments only for non-obvious flows.

## Testing Guidelines
- Prefer `flutter_test` with `mocktail` for unit logic and `integration_test` only when a feature spans routing; name files `<feature>_<behavior>_test.dart`.
- Every new use case or provider should have at least one happy-path and one failure test; mirror the folder path in `app/test/` to simplify discovery.
- Run `flutter test` locally before pushing; add `flutter test --coverage` when touching ranking/math code and keep coverage above the current baseline recorded in CI notes.
- For database changes, pair a `supabase/tests/` SQL script with each migration to assert RLS and constraints via `supabase db lint`.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (`feat:`, `fix:`, `docs:`) as seen in recent history; scope should match a single feature or migration batch.
- Commits must be linear and rebased on `develop`; avoid mixing Supabase and Flutter changes unless tightly coupled.
- Pull requests need: concise summary, linked issue, screenshots or terminal output for UI/CLI changes, test plan (commands run), and any Supabase migration IDs.
- Request at least one review; mark blockers clearly and convert to draft if awaiting backend credentials.

## Environment & Secrets
- Copy `app/.env.EXAMPLE` to `.env` and never commit secrets; reference keys via `flutter_dotenv` only in `infrastructure/` layers.
- When sharing repro steps, redact Supabase URLs or rotate keys via the dashboard and note the rotation in the PR description.

## Mobile UI Verification (responsywność)

Przy każdym tasku dotyczącym layoutu/UI na wąskich ekranach:

- Skill `.ai/cezar/skills/pickteams-ui-testing.md` to instrukcja operacyjna (serwer debug + Playwright MCP + pomiary geometrii). Workflow `pickteams-ui` dociąga go automatycznie.
- Serwer: `bash scripts/ui-serve.sh start|restart|stop|ready` (port 4370, tryb debug — wymagany dla drzewa dostępności i pasków overflow).
- Weryfikacja mierzalna: snapshoty a11y + recty elementów przed/po zmianie; screenshoty do `.ai/cezar/tmp/ui/`.

## Codex Command: create_doc
Use this command format in chat with Codex:

`/create_doc <feature_name> @<plan_path>`

Examples:
- `/create_doc matches @/home/netherman/code/squads_web/docs/feature_plans/matches.md`
- `/create_doc players @/home/netherman/code/squads_web/docs/feature_plans/player_details.md`

Behavior required from Codex when command is used:
- Treat `<feature_name>` as target feature.
- Read plan from `<plan_path>`. If `<plan_path>` is omitted, use `docs/feature_plans/<feature_name>.md`.
- Build or update target doc at `docs/features/<feature_name>.md`.
- Follow template and section order from `docs/features/feature_template_with_prompt.md`.
- Treat code + migrations as source of truth; treat plan as supportive context only.
- Keep output as implementation documentation (current state), not implementation plan.
