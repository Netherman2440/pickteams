# Historical match rankings: fixture screenshots

**Current reviewed source:** `a5d9e256c0a1ee82b72c0e88b940b058494c6ed0`. [Current 28 frames, independent review, actual commands/results and limits](a5d9e25/README.md). The files in this parent directory are retained older-source evidence only.

These are actual Flutter `MatchDetailsPage` frames at code candidate `2a74532dd25b8292ff83311dee305d54683da7c3`. They use the app's repositories and score use case over a synthetic in-memory HTTP transport. They are browser emulation, not live Supabase, physical-device, or production-durability evidence. The yellow banner labels the fixture and lists current scores separately from historical match inputs.

Four scenarios cover equal/unequal teams with substitutes enabled/disabled. Each has before-result, after-result, after-reload and after-correction frames. Adam's historical input stays 41.25 while the current score changes 90 → 95 → 85. Bartek stays above Adam at historical 63.75. Unequal raw team sums are 105.0 / 167.3; with substitutes enabled they are 105.0 / 111.5. Equal-team sums are 105.0 / 110.8 for either option. Reload invalidates the provider over the same fixture; it is not an independent database reconnect.

This evidence branch changes only this directory. The implementation branch and draft PR remain separate. These frames do not prove the unresolved tournament/partial-legacy paths, recover old-generation inputs/options, or approve missing-data error behavior. Issue #60 is NOT COMPLETE/VERIFIED and must not release dependent match stars (#61).

Reproduction uses the candidate's `app/tool/issue60_preview.dart` and `app/test/fixtures/snapshot_backend.dart`. Build from `app/` with `flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --pwa-strategy=none --target tool/issue60_preview.dart`, guarded by immediate nonblocking `/tmp/pickteams-flutter-validation.lock` admission and `MemAvailable >= 2621440 KiB`. Screenshot capture commands and raw logs are retained by the issue coordinator. No production calls, migration, merge or deployment were run to produce these frames.

| Scenario | Before | Result | Reload | Correction |
| --- | --- | --- | --- | --- |
| Unequal, substitutes off | [before](unequal-substitutes-off-before.png) | [result](unequal-substitutes-off-after-result.png) | [reload](unequal-substitutes-off-after-reload.png) | [correction](unequal-substitutes-off-after-correction.png) |
| Unequal, substitutes on | [before](unequal-substitutes-on-before.png) | [result](unequal-substitutes-on-after-result.png) | [reload](unequal-substitutes-on-after-reload.png) | [correction](unequal-substitutes-on-after-correction.png) |
| Equal, substitutes off | [before](equal-substitutes-off-before.png) | [result](equal-substitutes-off-after-result.png) | [reload](equal-substitutes-off-after-reload.png) | [correction](equal-substitutes-off-after-correction.png) |
| Equal, substitutes on | [before](equal-substitutes-on-before.png) | [result](equal-substitutes-on-after-result.png) | [reload](equal-substitutes-on-after-reload.png) | [correction](equal-substitutes-on-after-correction.png) |
