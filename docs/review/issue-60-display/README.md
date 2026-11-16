# Historical match display: narrow issue #60 evidence

Runtime candidate: `f128155a0179f9469a67f75dc0d65488bd0032b7`, branch `limen/issue-60-display-only`, PR #65. Base: current-main `01f03757c48c44a5fd9b49d7ce393ebf91a61e96`, including accepted PR #63. This evidence-only branch adds documentation/images, not runtime behavior.

Owner-approved scope: display existing match/player `ranking_history.ranking` WITHOUT adding `change`; keep ordering/totals stable across results, corrections and later current-score changes. Existing unequal-side multiplier and fallback behavior remain. No generator persistence, RPC, migration, roster transaction, new missing-history policy or production data repair. Broad PR #62 is superseded/not-for-merge and its evidence is not used as proof of this candidate. Exact-generator-time audit is not an acceptance gate.

## Eight real rendered frames

These are actual `MatchDetailsPage`, repositories and notifier over a labeled SYNTHETIC HTTP transport in Chromium at 1440×1000. They are not production data, physical-device or live Supabase evidence. The fixture exercises the existing player/ranking writer, not the full match scoring formula. `Next state` is a visible fixture control; real mouse clicks drive it. Capture waits for exact rendered stage/current-score banner AND rendered result paragraphs after async refresh, not just mutable fixture stage.

Historical p0 stays 40 while current p0 changes 40→95→15→150. The scoreboard changes unset→3:1→1:4→1:4. Home sorting stays p1=60, p0=40, plus p4=30 for unequal sides; away stays p3=70 then p2=50. Equal totals remain 100.0/120.0. For 3 vs 2, the existing factor gives `(40+60+30)*2/3 = 86.7`/120.0.

| Case | Before result | After result | Correction | Later current score |
| --- | --- | --- | --- | --- |
| Equal 2 vs 2 | [equal-0](equal-0.png) | [equal-1](equal-1.png) | [equal-2](equal-2.png) | [equal-3](equal-3.png) |
| Unequal 3 vs 2, x2/3 | [unequal-0](unequal-0.png) | [unequal-1](unequal-1.png) | [unequal-2](unequal-2.png) | [unequal-3](unequal-3.png) |

The worker opened all eight frames; the coordinator independently opened all eight. `browser.json` retains raw rendered labels, player panels/order/totals and zero browser-error assertions. `provenance.json` pins source SHA, capture-source SHA256, build hashes and all PNG hashes. All values/IDs/names are synthetic. Reload is also driven after each four-state case and checked. The capture's local server/browser stopped after completion.

## Actual final-SHA local checks

All final local lanes below ran on `f128155a0179f9469a67f75dc0d65488bd0032b7`, not a broad/predecessor candidate:

- `python -m unittest discover -s tool -p 'test_*.py'`: 99 passed, exit 0.
- `flutter pub get --enforce-lockfile`: exit 0, workflow-pinned Flutter 3.47.9.
- Scoped `dart format --output=none --set-exit-if-changed`: six files, zero changes, exit 0.
- `flutter analyze --no-pub`: no issues, exit 0.
- `flutter test --no-pub --concurrency=1`: 494 passed, one existing skip, exit 0. Includes all six accepted PR63 scores/teams/colors refresh success/failure cases and historical/fallback regressions.
- `flutter test --no-pub --platform chrome test/widgets/auth/auth_regression_test.dart`: 10 passed, exit 0.
- Fixture release build with `--target=tool/historical_match_preview.dart`: exit 0.
- Committed `capture_historical_match.py`: eight asserted/rendered frames and both Reload checks, exit 0.

Python dependencies use an external uv venv; Chromium runtime libraries were extracted outside the repository. No system install or project/CI/signing/dependency-version changes. Flutter's automatic analyzer config edits were restored before checks. Heavy lanes required immediate nonblocking lock admission and `MemAvailable >= 2621440 KiB`; no waiting/polling/gate reduction.

## Independent review and remote gate

[Initial independent code review](initial-code-review.md) is preserved verbatim at `1a7029e`: PASS, 38 independently passing focused tests, no production blocker. Its then-open screenshot/configured gates describe that earlier point in time. Runtime/Dart sources at final SHA are identical to that reviewed source; only the capture Python tool changed. The [final independent supplement](final-review.md) is now PASS at exact `f128155a0179f9469a67f75dc0d65488bd0032b7`: all eight frames opened, rendered states and source/build/PNG hashes verified, all capture assertions retained. [Artifact-check output](artifact-checks.txt) records actual verification. That report correctly leaves configured remote CI open at its inspection time; the CI gate is tracked separately in PR #65, not inferred from the visual PASS.

Configured production build inputs are intentionally unavailable locally; no credentials were sought. The exact final-SHA remote gate is now SUCCESS: [Main run 43926221967](https://github.com/Netherman2440/pickteams/actions/runs/43926221967), head `f128155a0179f9469a67f75dc0d65488bd0032b7`. Both analyze and web-build completed successfully, including Python/Flutter/Chrome lanes, the configured production-entrypoint build and provenance upload. [Saved actual run/job/step metadata](ci-result.json) was read and explicitly checked by the coordinator; success is not inferred from an observer wrapper. The prior green run on `1a7029e` and synthetic fixture build are not used to close this gate.

The OWNER-RESCOPED DISPLAY-ONLY task is COMPLETE/VERIFIED for PR review. This does NOT claim exact generator-time fidelity, owner acceptance, merge or production release. Broad PR #62 remains superseded; match stars (#61) may consume only this verified narrow candidate under intake scheduling. No schema operation or production-data change was performed. Future release, only after explicit owner acceptance, must include WEB and matching ANDROID; no release is claimed here.

## Reproduce

From candidate `app/`, install the lockfile dependencies with pinned Flutter 3.47.9 and run:

```sh
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run \
  --target=tool/historical_match_preview.dart --output=/absolute/external/fixture
python tool/capture_historical_match.py /absolute/external/fixture /absolute/external/screenshots
```

Guard heavy work with immediate `flock -n -E75 /tmp/pickteams-flutter-validation.lock`, then verify `MemAvailable >= 2621440 KiB` before execution. Use requirements from `tool/match_view_requirements.txt` and the browser's normal runtime libraries. The capture serves only the built fixture directory on loopback and shuts down its browser/server. It never serves the repository or calls production. Read `app/tool/historical_match_proof.md` for source-level details and limitations.
