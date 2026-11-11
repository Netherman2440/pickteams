# Match-card evidence and integration

- Reviewed candidate: `a8bce0f57765b21d5cc522db52c7c80a01431d43`, based on `b8efb75`. The independent verdict is preserved verbatim in `review-1.md`.
- Exact-candidate format, analysis, 154 coverage tests, production/fixture JS builds and forty inspected real Flutter frames passed. Evidence: `.limen/proof/f007/a8bce0f57765b21d5cc522db52c7c80a01431d43/notes.md` and `visual-review.md`.
- The reviewer independently ran all twenty card tests, verified the candidate/clean tree, inspected eight representative original frames across both real pages and accepted all six criteria. Independent commands/results are in `.limen/proof/f007/review-1/`.
- The historical red probe does not pin the exact base revision or preserve its earlier test. This limits historical reproducibility; it is not a failed current behavior check. Current independent glyph-bound, association, wrapping, routing and card-width assertions plus the inspected frames establish the accepted behavior. Do not present the old red log as an independently reproduced exact-base negative run.
- The only allowed existing RootShell diagnostic is the exact 13-pixel branding overflow at 320px/1.6x, naming `root_shell.dart:281:19`; independent review confirmed that card bounds and all other exceptions still fail normally.
- Before integration, rebase onto main without removing the separately accepted icon/score changes, verify every feature file against the reviewed candidate and record equivalence under `.limen/proof/f007/integrated/`. Combined application checks follow integration.
- Native APK/device/emulator and Wasm were not run and remain outside the agreed browser proof contract. No production data or services were used.
