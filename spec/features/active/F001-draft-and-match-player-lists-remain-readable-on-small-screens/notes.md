# Verification and handoff map

## Design decisions

- The owner approved the current mobile player rows, not a broad redesign: Open Sans 14 px names, muted 11 px rankings below, subtle separators, approximately 42 px rows with natural growth for wrapped names.
- Team names are centered within their own columns. Desktop retains one-line name/ranking rows.
- Search precedes selected and available players. A single scroll area and optional selection collapse avoid separate cramped panels.
- Home screen and navigation behavior remain unchanged. Do not remove existing actions to make a screenshot fit; compact or relocate them accessibly.
- Real Flutter system insets and existing shell space count against the phone viewport. Do not hide bars only for evidence, enlarge the viewport, change text scale, or replace real screens with imitation widgets.

## Proof contract

- Use the actual feature pages with deterministic fake repositories/providers. Include 22 available squad players, 16 selected, and eight players per team; include longer Polish names and decimal/snapshot rankings.
- Keep fixture setup outside production entry points. No live Supabase, credentials, Sentry submission, real match writes, or production data.
- Record exact fixture launch/build commands, viewport, text scale, candidate SHA, and artifact paths so a fresh session can reproduce the render.
- Capture unchanged 360 × 640 and 1440 × 1000 viewport images from real Flutter. Check horizontal overflow at 320 and 2560 pixels as well.
- Retain widget assertions that both rosters' final player rows lie inside their visible content area at default scale. Larger text and longer names must wrap or remain reachable, never clip silently.
- Exercise search, add/remove selection, collapse if introduced, proposal navigation, acceptance, and score entry. Preserve player navigation, permissions, snapshot-ranking display, redraft/rematch access, and team-edit drag behavior.
- Run targeted widget tests during development; final checks: `dart format` on changed Dart files, `flutter analyze`, `flutter test --coverage`, and a web build. Preserve raw logs and distinguish pre-existing failures from regressions.
- Browser screenshots prove Flutter web layout only. Include Android-target widget coverage for native spacing/insets and explicitly name any native-device or APK checks not run.

## Local seams

- Feature pages: draft selection/results and match details under `app/lib/features/`.
- Current row widgets: `DraftDraggablePlayerTile`, `MatchPlayerTile`; preserve behavior when replacing their card-heavy presentation.
- Existing draft search tests assert `Card` ancestry and normal color. Update only obsolete structural assertions if the card is removed; retain the behavior checks.
- Baseline includes no match UI regression tests. Cover actual page behavior, not only an isolated row widget.

## Outside paths

- Accepted HTML reference: `.limen/visuals/match-draft/mobile-app.html` and `index.html` in the canonical checkout; these ignored files are not copied into worktrees.
- Retained real-Flutter proof: `.limen/proof/f001/` in the canonical checkout. Keep images and logs out of Git; commit the reproducible fixture/test source.
- The existing Tailscale preview service serves `.limen/visuals/mobile-concepts/public/`. Do not stop it or replace approved HTML mockups. A credential-free fixture web bundle may be published only under its new `flutter-f001/` subdirectory.
- An isolated preview server started for checks belongs to this task. Stop it when checks finish; leave an explicitly shared owner preview running and record how to stop it.
- Flutter is not currently on PATH. Install an SDK archive outside the repository if needed; no system-wide package or engine changes. Read `app/AGENTS.md` before edits.
