# Match-level stars: calibrated baseline and squad overrides

## Source and limits

The owner supplied aggregates in [issue #61, comment 6941297324](https://github.com/Netherman2440/pickteams/issues/61#issuecomment-6941297324). The author was verified as Netherman2440. The reported source is dot's read-only public RLS GET on 2026-11-16 at 19:14 UTC for Politechnika Lubelska through 2026-11-13 inclusive. The date basis is `created_at` in Europe/Warsaw; `played_at` is NULL.

The owner reports 54 completed matches, 791 match/player pairs and 791 matching `ranking_history.ranking` values, with zero missing, duplicate or non-finite values. The input excludes `change`, current player scores and tournament fallback. Each player has equal weight within a match; each match has equal weight in the distribution. Reported mean: **58.1409**, population SD: **2.85331**, observed range: **49.8–62.926**.

These are owner-supplied provenance and counts, not an independent production read by this implementation. The aggregate statistics are sufficient for the requested parametric calculation. They do not prove exact generator/acceptance-time identity; that audit remains deferred. No personal rows, credentials, production access or historical backfill are needed for this calculation. The previous access blocker is historical and is resolved by this authorized aggregate input.

## Reproducible method

Run `python3 app/tool/calibrate_match_levels.py`. With normal CDF `F` for the supplied mean and population SD, map a score `x` to `1 + 4*(F(x)-F(min))/(F(max)-F(min))`. Invert at full-star levels 1, 2, 3, 4 and 5, then round each full threshold to one decimal place (decimal half-up).

The independently calculated endpoint CDFs are approximately 0.0017320663 and 0.9532321558. Raw full thresholds are approximately 49.8, 56.12199, 57.97976, 59.76473 and 62.926. These extra digits document the calculation, not the accuracy of the supplied data.

| Full stars | Baseline threshold |
|---|---|
| 1 | 49.8 |
| 2 | 56.1 |
| 3 | 58.0 |
| 4 | 59.8 |
| 5 | 62.9 |

The four automatic halves use adjacent **rounded** full thresholds: **52.95, 57.05, 58.9, 61.35**. They are not separate configuration values. Equality promotes to the new full/half level. Scores below the scale clamp to 1; scores above it clamp to 5. The one-star threshold is the lower anchor, not a zero-star cutoff.

`test_calibrate_match_levels.py` checks the committed Dart baseline against the calculation. Sensitivity at the interior corners of the reported precision bins preserves the one-decimal full thresholds. This establishes numerical rounding stability only, not confidence intervals or independent validation of the underlying records.

## Application and persistence

A NULL `squads.star_thresholds` means **use the immutable calibrated baseline**, for both existing and new squads. It is not a copied database default. An owner can save five finite, strictly increasing full thresholds as that squad's independent override. Reads, saves and permissions remain subject to existing RLS. No migration update, production UPDATE or backfill is required to enable the baseline, and an existing custom array is never overwritten automatically.

Settings show the effective five fields and identify baseline versus override. Match views still require more than 25 completed matches (both scores non-NULL, including 0–0) and complete finite match-specific history for every participant. The baseline never fills missing historical scores. The same provider calculates both views. Ranking math, team rotation factors, win probabilities and existing lineup fallback behavior remain unchanged.
