# Issue 57: original candidate screenshots

For the current ranking corrections, updated screenshots, recordings and validation,
see [ranking-corrections/README.md](ranking-corrections/README.md). The material
below documents the earlier candidate and is retained as historical evidence.

These are original screenshots of running Flutter widgets, not mockups. All
players, team names, rankings and match data come from synthetic test fixtures.
No credentials or production data appear. The eight PNGs were opened and audited
before publication. They total 410,902 bytes and are unchanged from the final
candidate capture. `SHA256SUMS` verifies this selected set; `checks.json` is the
original collector result for all ten cases and 49 frames (only eight are
published here). No earlier failed-contrast captures are included.

## Source and validation binding

- Original validated commit: `b6807aae30197231ed05c6aa1e014c1a67a7cf60`.
- Original base: `a59a207f4241896716ce274b7128c6f392b34ba6`.
- Remote `main` fetched for publication: `d5dd4f6b6d8e2367bccd2c12b4a7466343d14e48`.
- Both bases have exact tree `69764099173bef6433d163b379f522aec65153d5`.
- Only `01b9d192105b16c888031c53c6168b56615bf8b4` and the original validated
  commit were cherry-picked, without conflicts, onto that remote base.
- Reconciled implementation: `68adf0022f6ce03be03c797f9ee4fe49b4802796`.
  Its complete tree equals the original candidate tree:
  `2f5f811c054deb54f394ac97d815bc14d632a842`.
- Original and reconciled `app/` tree:
  `1a4cf420b2a5c47d40d7cd9f5d61a66ceddc7df0`.
  This includes source, tests, fixture, collector, lockfile and runtime inputs.
  The publication commit adds only this evidence directory. Thus the old
  validation applies to the published head's identical functional inputs;
  Flutter tests and browser checks were not rerun for this documentation-only
  publication.

Repeat the content comparison from the published head:

```sh
git diff --exit-code b6807aae30197231ed05c6aa1e014c1a67a7cf60 HEAD -- . ':!docs/review/issue-57'
git rev-parse HEAD:app 68adf0022f6ce03be03c797f9ee4fe49b4802796:app
cd docs/review/issue-57 && sha256sum -c SHA256SUMS
```

## Capture and limits

Chromium headless shell **156.0.8078.4**, **mobile/touch EMULATION**, not a physical
Android phone. Selected 360 px frames are 360 × 800 CSS px, scale factor 1; the
empty-target frame is 390 × 800. Full cases cover 360–430 CSS px. The collector
uses actual CDP touch start/move/end/cancel events. Non-loopback requests are
blocked. `app/tool/issue57_preview.dart` runs the real pages with
`app/test/fixtures/player_lists_app.dart`, in-memory `FixtureWrites` and fake
save/accept/reopen persistence. Reproduction commands are in
`app/tool/issue57_proof.md`.

A highlight frame alone does **not** prove gesture behavior. The corresponding
`checks.json` assertions check exact player-side maps before/after a transfer,
preserved identity sets, reverse movement, cancellation, fake save/reopen and
mouse movement. The long-name case checks scrolling without side changes.

Existing validation inspected for this publication:

- `flutter test --no-pub --concurrency=1`: 392 passed, one existing web-only test
  skipped in the native lane.
- `flutter analyze --no-pub`: no issues.
- Fixture `flutter build web --no-pub --target=tool/issue57_preview.dart
  --output=build/issue57-web --no-web-resources-cdn`: passed. Existing secure
  storage Wasm dry-run incompatibility warnings remain; this was a JavaScript build.
- Collector: ten Chromium cases passed, 49 frames, no page errors.
- Independent coordinator-corrected scoped command: 63 passed, exit 0.

Original evidence: implementation job
`2026-11-14-issue-57-task-issue-57-8743257e`, `evidence/issue-57/report.md`,
`clean-candidate-native.log`, `browser-candidate/checks.json`; review evidence
`evidence/independent-review/coordinator-corrected-tests.log`.
Physical Android Chrome and live database durability/RLS remain unverified.
No production writes or deployment were performed.

## Captions

| File | What it shows |
| --- | --- |
| `match-360-light-palette.png` | White/black choices and selected white border/check, light theme. |
| `match-360-dark-palette.png` | White/black choices and selected white check, dark theme. |
| `results-360-light-before.png` | Proposal: white home and black away, light theme. |
| `results-360-dark-before.png` | Proposal: white home and black away, dark theme. |
| `match-360-light-before.png` | BEFORE: synthetic Michał Kowalski at home; 7 home / 8 away. |
| `match-360-light-highlight.png` | DURING: held Michał over the highlighted away target. |
| `match-360-light-moved.png` | AFTER: Michał appears once at away; 6 home / 9 away, changed totals. |
| `match-390-dark-empty-highlight.png` | Empty away target highlights down to the last opposite row. |

The editable match fixture keeps synthetic team labels “Niebiescy/Czerwoni” even
when its color values are white/black. The proposal uses the side labels
“Gospodarze/Goście”. These are fixture labels, not live match records.
