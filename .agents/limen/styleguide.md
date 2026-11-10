# Styleguide

> Project-owned coding practice for every coordinator, worker, and reviewer turn. Keep this file at or below 1000 lines. The injected copy is capped at 1000 lines. Edit this file to change how agents write and organize code here. It is not product scope and not speech.

## Shape

- Flutter web client lives in `app/`; feature-first layout in `app/lib/` (`features/auth`, `features/squads`, shared `core/`).
- Clean Architecture per feature: UI in `presentation/`, business logic in `application/`, DTOs/entities in `domain/`, external services in `infrastructure/`.
- Supabase SQL, migrations, and seeds live in `supabase/`; one migration per change request, schema decisions documented in the migration header.
- Tests in `app/test/`, mirrored to the feature they cover; name files `<feature>_<behavior>_test.dart`.

## Prefer

- Riverpod for state; providers suffixed `Provider`, classes and enums `PascalCase`, files `snake_case.dart`.
- `dart format .` before committing; 2-space indentation, trailing commas in multiline literals.
- `flutter_test` with `mocktail` for unit logic; `integration_test` only when a feature spans routing.
- One happy-path and one failure test for every new use case or provider.
- Conventional Commits (`feat:`, `fix:`, `docs:`); linear history rebased on `main`.
- Secrets via `flutter_dotenv`, referenced only in `infrastructure/`; `app/.env.EXAMPLE` is the only committed copy.
- Skim `docs/prd.md` before large efforts so UX and role constraints stay aligned.

## Avoid

- Fat widgets: keep UI lean in `presentation/`, logic in `application/`.
- Mixing Supabase and Flutter changes in one commit or PR unless tightly coupled.
- Mapping user↔player in MVP code (moved post-MVP; do not scaffold it early).
- Hardcoded keys or URLs outside `infrastructure/`; never commit secrets, redact Supabase URLs in shared repro steps.
- Weakening acceptance when a check fails — a failure is a blocker, not a scope negotiation.
