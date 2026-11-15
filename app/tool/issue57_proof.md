# Issue 57: team colors and mobile-web transfers

For the PR #58 ranking follow-up, current source pin, 19-case matrix and recordings,
see [ranking-corrections/README.md](../../docs/review/issue-57/ranking-corrections/README.md).
Set `ISSUE57_VIDEO=1` when running the collector to record the 360 px, 1× match
and proposal cases. The original candidate report below retains its earlier scope.

## Candidate contract

New proposals show home white (`#FFFFFF`) and away black (`#000000`).
Redraw loads stored colors before exposing an accept-ready proposal. It does not
write or reset team metadata. The existing acceptance RPC already creates white
home / black away teams and preserves metadata on redraw
(`supabase/migrations/20261111120000_accept_match_draft.sql`, lines 80–87).
No SQL, ranking formulas, draft algorithms, permissions or live data changed.

Both roster components share pointer-kind recognizers: immediate mouse drag,
long-press touch/stylus drag. Quick touch swipes remain scroll gestures. The
whole roster is a target, with equal column heights and a 144 px minimum. A
visible grip, instructions, lifted feedback and a contrasted target identify
the gesture. The palette and its opener have 44 px touch areas.

The shared team badges and probability bar use `onSurfaceVariant` borders.
The light theme's `outline` is intentionally transparent, so it cannot define
a visible white badge. Probability labels explicitly identify home and away.

## Reproduce

Use Flutter 3.47.9 / Dart 3.13.7 from the existing SDK. Install dependencies with
`cd app && flutter pub get --enforce-lockfile`. No shared package-cache symlinks.
All heavy commands below must run inside this gate (from repository root):

```sh
flock -n -E75 /tmp/pickteams-flutter-validation.lock bash -c '
  set -eu
  available=$(awk "/MemAvailable:/ {print \$2}" /proc/meminfo)
  echo "MemAvailable=${available}KiB required=2621440KiB"
  test "$available" -ge 2621440
  cd app
  flutter test --no-pub --concurrency=1 \
    test/features/matches/presentation/team_transfer_gesture_test.dart test/draft
'
```

For the complete native test lane, replace the last command with
`flutter test --no-pub --concurrency=1`, then `flutter analyze --no-pub`.
The focused checks replace the earlier single swipe/target probes and strengthen
existing proposal tests with stored/default color and failed-read assertions.
They cover both pointer kinds, 360/430 px, 7/8 and empty teams, identity sets,
changing totals, cancellation, fake save/reopen, roles, both themes, palette
selection, contrast, and proposal-to-fake-acceptance-to-details continuity.

Build the credential-free browser fixture under the same gate:

```sh
cd app
flutter build web --no-pub --target=tool/issue57_preview.dart \
  --output=build/issue57-web --no-web-resources-cdn
```

Serve **only** `app/build/issue57-web` on `127.0.0.1:8857`, not the repository.
Run `python app/tool/check_issue57_browser.py <evidence-directory>` under the
same gate, with the installed Playwright interpreter. This machine needs:

```sh
export LD_LIBRARY_PATH="$HOME/.local/share/playwright-system-libs/root/usr/lib/x86_64-linux-gnu"
export TMPDIR="<owned-existing-evidence-directory>"
$HOME/.local/share/uv/tools/playwright/bin/python \
  app/tool/check_issue57_browser.py <evidence-directory>
```

The script uses the installed Chromium headless shell. It sends CDP touch
start/move/end/cancel events, with a real 600 ms hold. It also sends mouse
input in the touch-capable browser. It checks exact side maps, not only
screenshots. The ten cases include 360/430 px, both themes, both pages,
empty targets and long-name scrolling. `checks.json` records assertions,
Chromium version and screenshot hashes. All non-loopback requests are blocked.
Stop the loopback server after capture.

## Evidence and limits

The coordinator's job artifact directory holds the exact source pin, commands,
logs, opened-frame index and screenshots:
`/home/agents/dev/pickteams/.limen/jobs/2026-11-14-issue-57-task-issue-57-8743257e/evidence/issue-57/`.
Read `report.md` there for results and the acceptance-to-evidence map.

These are widget tests and touch-capable Chromium emulation, not physical Android
Chrome. Writes use in-memory fakes. The RPC's real database behavior was not
executed or deployed. Browser frames use synthetic players and fixture team
names; those names are not production data. Source publication requires separate
permission. No branch push, merge, deployment, APK build/replacement or service
change is part of this candidate.
