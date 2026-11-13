# Collapsing lineup proof

Feature delta base: `603d08d26b234c408eed719f869d3da792d28dd5`. Keep the stacked parent commits. This feature does not establish acceptance of the parent shared rows or draft lifecycle.

## Seams

- `lib/core/widgets/lineup_header.dart`: one pinned sliver for both team identities; existing color badges shrink from 48 to 16 pixels. Name measurement reserves space for large text and wrapping. The stacked match variant also carries each team's `Ranking: …` total under its name while expanded; collapsed it reduces to the color badges alone, and the draft results variant keeps its inline badge-plus-name identity at every extent.
- `MatchDetailsPage.build`: read-only score/date occupy the full local toolbar width, independent of leading/actions. Editing keeps direct Save/Cancel and removes collapse; a separate scroll key opens editors at the start without changing controllers.
- `MatchDetailsPage._buildContent`: one scroll view, two compact shared-row columns, totals and probability after both rosters. Team editing retains its existing drop targets.
- `DraftResultsPage` data presentation: proposal navigation scrolls away, team identity stays pinned, shared compact rows precede the unchanged wrapping totals/probability. Lifecycle, acceptance, pointer lock and back handling are unchanged.
- `test/fixtures/lineup_app.dart` and `tool/lineup_preview.dart`: synthetic 8/11-player, long-name, scaled-text, role and saved/missing-score cases in real RootShell. No backend configuration.

## Exact-candidate lane

From the clean committed worktree, run:

```sh
SOURCE=$(git rev-parse HEAD)
E=/home/agents/dev/pickteams/.limen/proof/F015/$SOURCE
mkdir -p "$E"
nohup bash app/tool/check_lineups.sh "$SOURCE" "$E" > "$E/run.log" 2>&1 &
```

The script takes the shared nonblocking lock, installs from the lockfile, runs scoped tests with concurrency 1 and scoped analysis, then checks for at least 2621440 kB available before the JS build. It writes PID, stage, logs and exit status, serves only loopback, and stops its server on exit. Exit 75 is a resource blocker, not acceptance. No native build is included. If blocked before build, the coordinator can serialize a later invocation or use the shared source-pinned browser pipeline with `tool/lineup_preview.dart` and `tool/capture_lineups.py`.

Inspect all original PNGs listed in `frames/browser.json`. Compare expanded and collapsed frames at 360x640, eight and eleven per side; inspect 1.6x long names at top and bottom, 1440px, read-only/missing score, Owner menu, score editing/saving and team-edit cancellation. Browser success is not pixel acceptance. Eleven is a measured target, not permission to shrink fonts or change draft limits. Full combined tests and a new APK remain coordinator-owned.
