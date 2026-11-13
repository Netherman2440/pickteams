# Final A match-view proof

`match_view_preview.dart` uses the real RootShell and match page, synthetic data,
local fonts and historical rankings 105.25/9.90. `window.matchViewMetrics()` only
reads rendered panels, individual glyph boxes, text sizes, team identities,
viewport geometry and Flutter errors. It does not change layout or scrolling.
Fixture score/team updates retain match settings and existing player snapshots.

`capture_match_view.py` covers 320/360/390/1440 x 640, scales 1/1.6, 8/11 players
and short/long names (32 combinations), plus guest, uneven read-only and two
short-content cases. It records expanded/collapsed/bottom/navigation states.
Four long-name 11-player phone cases enter 17:6, save, and assert the same 22
names, rankings, sides and team names/colors. Team editing changes a name with
normal keyboard input, then Cancel must restore that same identity.

`match_view_pixels.py` checks real raster ink inside every glyph box of each
fully visible panel. Geometry checks require all characters inside their panels,
14/12 base text sizes scaled once, equal row heights, inline panel-centered
rankings, strict score/date centering, and footer order. Team totals live in
the expanded header under each team name (badge, name, then a centered
`Ranking: …` per column); the collapsed header keeps only the pinned color
badges, and every roster frame re-asserts that collapsed state. The clear
region excludes the whole painted header, so panels below it count as visible
only when genuinely clear of it. Scrolling must expose every complete panel
below the pinned header. Ink checks detect blank paint, not all wrong glyphs:
open actual PNGs before accepting readability. No semantics or automatic
status replaces this inspection.

`test_match_view_capture.py` tests that the checks reject missing ink, truncated
names, reduced fonts, changed identities and misplaced rankings. It runs with
the existing Pillow interpreter; no dependency installation is required.

## Source-pinned execution

Commit first. Use a protected detached checkout, not a Limen worktree:

```sh
ROOT=/home/agents/dev/pickteams
SHA=$(git rev-parse HEAD)
WT=/home/agents/.local/share/pickteams-validation/match-details-final-a-$SHA
E=$ROOT/.limen/proof/match-details-final-a/$SHA
git worktree add --detach "$WT" "$SHA"
bash "$ROOT/.limen/tools/browser_proof.sh" "$WT" "$SHA" \
  tool/match_view_preview.dart "$WT/app/tool/capture_match_view.py" \
  "$E/browser" profile
```

For a queued run, a managed service owns this command and its stable working
directory. Record its PID, log, exit and runner snapshot in `E`. Run committed
full analysis, touched-file format and `flutter test --concurrency=1` under
`flock -n -E75 /tmp/pickteams-flutter-validation.lock` before browser execution.
Install offline from the lockfile, never through another checkout's package
symlink. Keep all earlier failed logs and frames.

The browser runner measures MemAvailable AFTER acquiring the shared lock. Web
build admission requires at least 2621440 KiB. It releases the lock between
attempts. Do not lower that limit or spend a model turn polling a blocked queue.
Report the service/stage/evidence and remaining checks when still gated.

The runner records source hashes and its executed snapshot. Its loopback server
stops on exit; its capture browser closes in `finally`. Read `run.exit`,
`build.exit`, `capture.exit` and `frames/results.json`. A failed capture remains
failed even when some PNGs look correct. No APK, release, public preview, schema
or API change belongs to this proof.
