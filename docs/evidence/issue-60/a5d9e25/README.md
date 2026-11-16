# SHA-bound historical ranking and retry evidence

Runtime source: `a5d9e256c0a1ee82b72c0e88b940b058494c6ed0` on the implementation branch for draft PR #62. This evidence-only branch adds no runtime changes. The independent verdict is copied verbatim in [independent-review.md](independent-review.md); actual reviewer commands/exits are in [independent-commands.txt](independent-commands.txt).

## Real results and limits

Worker final source validation: 460 Flutter tests passed, one existing skip; analyze clean; ten formatted Dart files unchanged; product and fixture release JS builds passed; all 17 native SQL regression scripts and a real two-session score-lock race passed on disposable local PostgreSQL. No coverage-baseline improvement is claimed. Reviewer independently passed 97 focused tests, one post-commit-timeout test, native numeric/ACL/atomic SQL and the score-lock race. No new blocking defect was proved in the last repair.

The owner requires the ranking from BEFORE ACTUAL GENERATION; before the first match the initial input is base_score. An independent regression generates A, enters and corrects an earlier previously unscored match before acceptance, and proves acceptance/stored-proposal/match reload retain A while current score changes. This is synthetic new-path evidence, not a production inventory or a general reconstruction proof for older ID-only payloads.

Whole issue #60 is NOT COMPLETE/VERIFIED. Existing production history is not assumed absent. Scoped authenticated production reads have not run, exact old-generation/options fidelity and missing-input policy remain unresolved, and dependent match stars (#61) stay blocked. No merge, manual deploy, schema rollout, backfill, production read or data repair was performed. Real Auth/PostgREST, Supabase CLI lint, physical devices and Android release were not checked. Normal automatic PR previews are routine infrastructure, not production release approval.

## 20 fresh regular-flow frames

[regular/](regular/) contains proposal plus before-result, after-result, after-reload and after-correction frames for four equal/unequal substitutes-on/off scenarios. These were freshly captured from the retained fixture release bundle built at the exact source above. [capture-final.log](capture-final.log) records the successful coordinator run under immediate nonblocking lock and the unchanged 2621440 KiB memory gate. Script: [capture_regular.py](capture_regular.py).

Both real pages show 105.0 / 167.3 for unequal teams with substitutes OFF, 105.0 / 111.5 with substitutes ON, and 105.0 / 110.8 for equal teams in either mode. Adam stays 41.25, Bartek stays 63.75 above him, and away ordering stays Dawid/Emil/Cezary. The banner changes current scores through result/correction; the input values and totals stay fixed. Synthetic raw away sum 167.25 is displayed as 167.3.

| Scenario | Proposal | Before result | Result | Reload | Correction |
| --- | --- | --- | --- | --- | --- |
| Unequal, substitutes OFF | [proposal](regular/unequal-substitutes-off-proposal.png) | [before](regular/unequal-substitutes-off-before.png) | [result](regular/unequal-substitutes-off-after-result.png) | [reload](regular/unequal-substitutes-off-after-reload.png) | [correction](regular/unequal-substitutes-off-after-correction.png) |
| Unequal, substitutes ON | [proposal](regular/unequal-substitutes-on-proposal.png) | [before](regular/unequal-substitutes-on-before.png) | [result](regular/unequal-substitutes-on-after-result.png) | [reload](regular/unequal-substitutes-on-after-reload.png) | [correction](regular/unequal-substitutes-on-after-correction.png) |
| Equal, substitutes OFF | [proposal](regular/equal-substitutes-off-proposal.png) | [before](regular/equal-substitutes-off-before.png) | [result](regular/equal-substitutes-off-after-result.png) | [reload](regular/equal-substitutes-off-after-reload.png) | [correction](regular/equal-substitutes-off-after-correction.png) |
| Equal, substitutes ON | [proposal](regular/equal-substitutes-on-proposal.png) | [before](regular/equal-substitutes-on-before.png) | [result](regular/equal-substitutes-on-after-result.png) | [reload](regular/equal-substitutes-on-after-reload.png) | [correction](regular/equal-substitutes-on-after-correction.png) |

## Eight recovery frames

[recovery/](recovery/) contains eight exact-source worker frames independently inspected: conflict before/rejected/reloaded/new-save and uncertain before/lost-reply/reloaded/exact-retry. [capture_recovery.py](capture_recovery.py) records the browser assertions. Known rejection plus explicit successful reload clears that rejected operation and allows a new UUID/base. Uncertain post-commit outcome retains identical UUID/base/input through reload/cancel until exact retry resolves it. Fixture operation UUIDs and base labels are synthetic, not production identifiers.

The initial save in this visual fixture is a labeled synthetic control. Independently executed widget tests separately drive real drag, Save, reload, cancel and retry controls. PostgreSQL proofs separately establish actual transaction rollback/RLS/race behavior. Neither visual fixture pretends to prove hosted network durability.

## Reproduction boundary

Build the candidate from `app/` with `flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none --target tool/issue60_preview.dart`, using an external output directory. Gate heavy work with immediate `flock -n -E75 /tmp/pickteams-flutter-validation.lock` then `MemAvailable >= 2621440 KiB`. Serve only that isolated build directory on loopback. Run the included regular capture script with `playwright-local python capture_regular.py http://127.0.0.1:<owned-port> <external-output>`; the recovery script uses the same interface. Stop the owned server afterward.

All images are real Flutter `DraftResultsPage`/`MatchDetailsPage`, repositories and use cases over labeled synthetic in-memory HTTP in browser emulation, not live Supabase or physical devices. Reload invalidates the fixture provider; it is not a browser restart or independent database reconnect. External font requests are blocked. Old frames at the parent directory belong to the old source SHA and are not current proof.
