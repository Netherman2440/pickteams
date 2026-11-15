# Team-ranking corrections for PR #58

This evidence answers [the requested corrections](https://github.com/Netherman2440/pickteams/pull/58#issuecomment-6883443131). It supersedes the earlier screenshots one directory above. These are captures of the real Flutter proposal and match pages, not mockups.

## What changed

- Each team's ranking stays with its name and color above, and outside, its roster. Proposal and read-only match headers retain that identity while scrolling. The edit header sits outside the transfer target.
- Transfers still use the existing effective-ranking calculation. Both displayed totals follow the current rosters; match views retain snapshot rankings.
- Confirmed review finding: a tooltip's touch long-press competed with the drag recognizer. Manual tooltip triggering removes that competing touch gesture; mouse hover still displays the tooltip. Tests and browser checks start at the actual grip, not the middle of the player row.
- Confirmed review finding: unconstrained probability labels could overflow with enlarged text. Both labels now wrap in bounded columns without reducing text scale. Proposal navigation also wraps, and acceptance uses a bottom action so it does not crowd the narrow app bar.

## Source and checks

Validated source: `4b1d1da6d7d3fd3adb4b28ea8f4c181cb2c2433e`.
Its `app/` tree is `2f42e96f5b869bd53de854324b7f623e035ce7b6`.
The publication commit adds documentation and evidence only. Tests, analysis, build and browser checks were rerun on that exact source in a separate validation worktree.

An independent read-only review of that source found no blocking defects. It checked all 13 changed files and confirmed unchanged ranking arithmetic and meaningful gesture/layout tests. The reviewer did not independently rerun the runtime matrix. It noted that the widget-test totals helper is not side-specific; the browser collector separately verifies each side's total.

Flutter **3.47.9**, Dart **3.13.7**:

| Check | Result |
| --- | --- |
| `flutter test --no-pub --concurrency=1` | 421 passed; one existing web-only test skipped in the native lane |
| `flutter analyze --no-pub` | No issues |
| `dart format --output=none --set-exit-if-changed` on changed Dart files | No changes |
| `flutter build web --no-pub --target=tool/issue57_preview.dart --output=build/issue57-web --no-web-resources-cdn` | Passed; JavaScript build, existing secure-storage Wasm dry-run warnings |
| `ISSUE57_VIDEO=1 python app/tool/check_issue57_browser.py <output-directory>` | 19 cases passed; 97 screenshots; two WebM recordings; no page errors |

The matrix uses Chromium **156.0.8078.4**, height **800 CSS px**, device scale factor **1**. It covers proposal/details/edit at **320, 360 and 430 CSS px**, text scales **1× and 1.6×**, both themes, and desktop **1440 px**. Additional **320 px / 3×** cases check layout and reachable probability labels; they do not claim transfer coverage at 3×. Additional cases exercise empty targets and long-name scrolling.

`checks.json` records assertions against exact player-side maps, effective totals, real handle coordinates and SHA-256 hashes. Touch cases use actual CDP touch start/move/end/cancel events with a 600 ms hold. The collector also checks mouse transfer and fake save/reopen/cancel/acceptance. All non-loopback requests are blocked during capture. `SHA256SUMS` covers the published evidence.

## Screenshots

| View | Before | After |
| --- | --- | --- |
| Proposal, 360 × 800, 1× | [Before transfer](results-360-light-x1-before.png) | [After transfer](results-360-light-x1-moved.png) |
| Edit, 360 × 800, 1× | [Before transfer](match-360-light-x1-before.png) | [After transfer](match-360-light-x1-moved.png) |
| Match details, 360 × 800, 1× | [Initial](match-360-light-x1-view.png) | [After fake save](match-360-light-x1-saved.png) |
| Narrow match, 320 × 800, 1.6× | [Read-only](match-320-dark-x1.6-view.png) | [Editing](match-320-dark-x1.6-before.png) |
| Narrow proposal, 320 × 800 | [1.6×](results-320-dark-x1.6-before.png) | [3× probability footer](results-320-light-x3-probability-3x.png) |

## Recordings

The WebM files are original browser recordings of the complete checked flows. The GIFs are 5 fps previews decoded from those recordings, with initial blank/loading frames omitted. They are not animations assembled from invented states. The recordings include loading, real pointer gestures, transfers and fake save/acceptance. The cursor is not drawn by the touch-emulation recorder.

- [Match edit: original WebM](videos/page@ca1b36c6ee66c2d7a57bd1a1ee336df8.webm) · [animated preview](match-360-light-x1-recording.gif)
- [Proposal: original WebM](videos/page@f8ea285d7e58e7877fe6cabe1d1c131d.webm) · [animated preview](results-360-light-x1-recording.gif)

## Limits

These are mobile/touch **emulation**, not a physical Android phone. Players, names and match data are synthetic. Persistence uses in-memory fakes; real database durability/RLS and production writes were not exercised. The editable fixture calls the teams “Niebiescy/Czerwoni” even when their chosen colors are white/black; those are test labels, not production records.

No ranking algorithm, SQL or production data changed. No merge or deployment command was run. Existing Vercel preview failure is separate from these local checks; they do not establish a working deployed preview.
