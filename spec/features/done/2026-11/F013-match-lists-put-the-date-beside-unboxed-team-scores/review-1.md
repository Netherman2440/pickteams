# Actual browser review: FAIL

Candidate: 3016267e4379983c67564d60cb7a0c87e0e16394. Base: f2ed2a1. All paths below are relative to this proof directory unless stated otherwise.

## Proven blocking finding

The real browser splits two-digit scores over two lines. `14` renders as `1` above `4`, and `16` as `1` above `6`. Both squad and player histories show the defect at 360px / 1x, 360px / 1.6x, and 1440px / 1x. In the first normal-scale card, the home marker/name sit between the two painted score digits rather than beside the complete number. This breaks ticket acceptance “Każdy wynik jest wyrównany z właściwą nazwą i znacznikiem koloru” and the requested plain two-row scores at every width.

Production seam: `app/lib/features/matches/presentation/widgets/match_tile.dart:55-58,130-141`. The score uses an intrinsic-width table column and a wrapping Text with no single-line constraint. Make the complete number fit on one line without clipping or shrinking the requested text scale. Add a regression that proves single-line score paint, not just a selection-box union centered on the team row. The existing 28 tests pass despite this defect. Exact browser metric cause is not established; the rendered defect is proven.

Primary evidence: `frames/squad-360-scale1-top.png`, `frames/player-360-scale1-top.png`, `frames/squad-1440-scale1-top.png`, `frames/player-1440-scale1-top.png`. At 1.6x, the same split is visible in both `*-360-scale1.6-top.png` frames.

## Capture failure and limits

The exact committed command built successfully in 51.1s. The committed capture script then generated all 14 images but exited 1 at `app/tool/capture_match_lists.py:51`: every page requested Google Fonts CSS from the unchanged `app/web/index.html:22-25`. The script blocked these requests. This is a proof setup issue, not a newly introduced external dependency. Preserve the rejection; make the offline fixture entry shell local-only before the next accepted capture, without changing production theme/font behavior. No rerun was attempted.

`frames/browser.json` records zero page errors, matching document widths, and no reported Flutter overflow/exception console messages. Those facts did not detect the visible score wrapping. The command is a release build as specified by `app/tool/match_lists_proof.md`, so lack of debug overflow diagnostics is not proof of paint correctness.

All 14 PNGs were opened individually: both `squad` and `player`, `360-scale1` and `360-scale1.6`, each at `top`, `middle`, `bottom`; plus both `1440-scale1-top` images. They show DD.MM left of the teams, correct red/home and blue/away association, no score boxes, zero scores, partial/missing-result dashes, and the unselected-team message. Long names stay inside their columns in the visible regions. However, the 360px / 1.6x bottom image only shows the lower portion of the long-name card; these three scroll positions do not prove its full content. Supplemental 1440px / 1.6x frames did not execute after the committed capture failed. Empty/error list pages and full-date/route behavior were verified only by widget tests, not browser interactions.

## Resources and continuation

`validation.log` preserves 31 resource/lock deferrals and successful build admission on attempt 32 with the lock held and MemAvailable=2679004 KiB, above 2621440. `validate.sh` records the exact worktree and build command. `fixture-web/` contains that exact built candidate. No further compiler run is needed to inspect this failed candidate.

`capture.sh` records port 18857, the dedicated compiled directory, the committed capture command, and the prepared supplemental `capture_wide_scaled.py`. It expects the caller to hold `/tmp/pickteams-flutter-validation.lock`; do not invoke it without that lock. A rerun would overwrite `frames/`, so use a new proof directory for any subsequent attempt. Current failed frames and logs must remain intact.

The current operation finished before the coordinator's scheduling steer. No new retry/build/capture was started afterward. The server stopped at 22:19:13 UTC; its PID and validation PID no longer exist, and port 18857 has no listener. Chromium closes in the capture script's finally block. No F014 work, foreign process termination, resource-gate relaxation, full-suite repeat, production source repair, ticket/board edit, native build or deployment was performed. Do not close the ticket.
