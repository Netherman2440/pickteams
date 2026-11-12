# Match view full-name proof

The candidate implements the final approved A layout, not the earlier two-line
clamp. `match_view_preview.dart` uses the real RootShell and match page with
synthetic data, local fonts, historical rankings 105.25/9.90, and unchanged
long-name fixtures. `window.matchViewMetrics()` only reads the rendered tree.
It returns per-character Flutter glyph boxes, panel bounds, footer bounds,
identity bounds and Flutter errors; it does not alter layout or scrolling.

`capture_match_view.py` uses real 320/360/390/1440 x 640 viewports, scales 1/1.6,
8/11 players, a two-player short case, and an uneven read-only case. It uses
normal wheel and pointer input, captures expanded/collapsed/bottom/edit states,
and checks every name character inside its panel. Source glyph boxes are not
visual acceptance: open the PNGs and check for missing glyphs and actual paint.
A nonzero capture exit remains a failed check even if some frames look correct.

Run only from a committed clean source. The shared runner records source hashes,
its own executed snapshot, all exits and failure logs. It acquires
`/tmp/pickteams-flutter-validation.lock` nonblocking and admits the web build only
when MemAvailable is at least 2621440 KiB AFTER the lock. It releases the lock
between admission attempts. Do not wait in an idle model turn for that gate.
Use a protected checkout outside `.pickteams-limen-worktrees` for queued runs:

```sh
ROOT=/home/agents/dev/pickteams
SHA=$(git rev-parse HEAD)
E="$ROOT/.limen/proof/match-details-final-a/$SHA"
git worktree add --detach "$E/source" "$SHA"
# Start this only when a queued run has an explicit owner.
bash "$ROOT/.limen/tools/browser_proof.sh" "$E/source" "$SHA" \
  tool/match_view_preview.dart "$E/source/app/tool/capture_match_view.py" \
  "$E/browser" profile
```

The runner starts a loopback-only server and stops it on exit. Its capture
browser closes in a `finally` block. No APK, public preview or release file is
changed. Inspect `browser/run.exit`, `build.exit`, `capture.exit`, and
`browser/frames/results.json`; the JSON explicitly marks frames as still needing
pixel inspection even when automated checks pass.

The strict 320px/1.6 RootShell check is intentionally not skipped. The unchanged
RootShell toolbar has a known overflow at that width/scale (also documented in
`match_score_breakpoint_test.dart`). A match-only change must not hide it or
silently lower text scale. Resolve that global scope restriction before claiming
full task acceptance.
