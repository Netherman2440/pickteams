# Draft search Android resume candidate — issue #68

## Remaining blocker

Android IME reproduction and verification are NOT complete. No video exists. `android-capability.txt` records an empty `adb devices -l` result and absent emulator, system images, AVD, and the narrowly checked alternative SDK paths. Android OS/API and keyboard versions are unavailable because no Android runtime was available. Do not mark this candidate verified or the issue complete. The parent owns independent review and any permitted blocked draft publication.

## Source findings and design

Start at `app/lib/features/draft/presentation/pages/draft_selection_page.dart`, `_AvailablePlayersPanelState`. The base search field has no autofocus and no app lifecycle observer. `_refocusSearchField` only runs after a player add. These are source observations, not a reproduced Android root cause. The previous tap fix is merge `887589c8409dfc1cce8d2a86eb4292985b427181` (#48).

The candidate opens search on entry. On native Android it tracks visible keyboard insets while resumed and snapshots visibility plus search focus when leaving resumed. It ignores inset collapse while backgrounded. Only an open search keyboard permits focus restoration. On hidden/paused it releases the old input connection through unfocus; one guarded post-frame focus request creates a fresh connection on resume. It does not reset query, text selection, or player selection. Back-induced zero insets cancel visibility even when focus stays. Current-route and lifecycle guards prevent queued restoration or the existing player-add callback from focusing another route. Disposal removes the observer. No timer or retry loop exists. iOS/web/desktop do not use this new Android restoration path.

The old tap-selection test is replaced by a stronger tap plus three-cycle simulated resume test. Other checks cover initial connection, three dismissed-keyboard cycles followed by tap-to-reopen, covered/disposed route, query and roster persistence, arrows, hardware Enter, software Done, and scrolling. Fake insets and test text input are model checks only. Android lifecycle/IME event ordering remains an unproven assumption, including dismissal immediately before backgrounding. A stale input connection is a design hypothesis, not a measured cause.

## Checks and commands

Known Flutter SDK: `/home/agents/.local/share/pickteams-f001-sdk/flutter/bin`; observed Flutter 3.47.9, Dart 3.13.7, framework c197ca5199, engine 89c39edfdf. Dependencies were installed from the existing lockfile with `flutter pub get --offline --enforce-lockfile`. No symlink or software/SDK/image download was used. Pub get's automatic unrelated `analysis_options.yaml` upgrade was removed; the lockfile is unchanged.

- `baseline-entry.txt`: new initial-focus assertion failed on the unchanged base source (`Expected: true; Actual: false`). This is not Android bug reproduction.
- `focused-first.txt`: first candidate, 12 widget tests passed.
- `mutation-no-restore.txt`: temporarily omitted only the resume focus request. The repeated-resume test failed at its focus assertion. The request was restored before final checks. This demonstrates that the test detects missing restoration in the model.
- `format.txt`: scoped `dart format` checked two files, changed the test file.
- `focused-final.txt`: final focused file, 12 tests passed.
- `analyze.txt`: `flutter analyze --no-pub`, no issues.
- `full.txt`: attempted `flutter test --no-pub --coverage --concurrency=1` after code candidate commit `561a6ea2e3d5fdc041050d722b0baf04fbf635ce` (tree `def4ff758ac7f182ee0362ec80edc657add31d86`). The command hit the tool's 120-second limit after 218 completed tests, with no failure, while the 600px breakpoint case was in progress. Only the newly opened log was untracked at startup; code/tests matched the committed candidate. No validator process remained after timeout.
- `interrupted-option-error.txt`: first continuation command rejected unsupported `--exclude-name` with exit 64; no tests ran. Corrected to `--name '^(?!.*at (360|599)\\.0px).*'`.
- `interrupted-rest.txt`: the interrupted breakpoint file's 45 unfinished cases passed. The completed 360px and 599px cases were not repeated.
- `remaining-tests.txt` and `remaining.txt`: all 20 test files not started by the first run completed, 275 passed and one web-only reset-email test skipped (`skip: !kIsWeb` in `auth_regression_test.dart`). Across the three segments, 538 tests completed and one was skipped. There is no successful single-process full-suite result. Coverage from the killed first segment is absent; the available lcov report covers only the last continuation. Do not present it as aggregate full-suite coverage. No source/test changes occurred after the candidate commit.

`validate.sh` prints exact final commands and enforces a separate immediate `flock -n -E 75 /tmp/pickteams-flutter-validation.lock` plus `MemAvailable >= 2621440 KiB` before each Dart/Flutter command. Earlier probe commands used the same gate inline. No resource gate was denied. The first inline gate covered Flutter version, offline dependency resolution and the baseline test in one locked shell; subsequent validation uses one command per gate.

## Android probe provenance

ADB was not on PATH. The configured SDK is `/home/agents/.local/share/pickteams-android-release/production/sdk`; `adb version` reports Android Debug Bridge 1.0.41, version 37.0.1-15733141, Linux x86_64. A preliminary `adb -P 5037 server-status` unexpectedly started an ADB server (its output explicitly said daemon was not running). The subsequent `adb devices -l` reported no devices. This job then ran `adb kill-server` and confirmed no remaining `adb` process. No device contents or credentials were read. No emulator, install, Android build, signing, recording, or upload was attempted. ADB's standard log path was `/tmp/adb.1001.log`; it is not evidence of an Android session and was not inspected.

## Next verification

Use an authorized Android device or an existing configured emulator with a visible software keyboard. Run synthetic data through the real selection route. Record three app switches through Android Settings with an open keyboard; confirm query/selected players survive and keyboard remains usable after settling, not only on the first frame. Then dismiss with system Back/gesture and record three more switches; confirm it stays hidden until search is tapped. Include selection tap and other-route checks. Record actual Android/API/IME versions, build commit, commands, originals, hashes, and upload location visible from the eventual PR. Do not open private messaging content. Do not infer device results from these widget tests.

## PR-ready description (blocked draft only)

Title: `fix(draft): preserve Android search keyboard intent across app switches`

Refs #68. Open search on entry. Restore the search input connection after backgrounding only when its keyboard was visible. Preserve query, editing selection, and selected players. Keep explicit keyboard dismissal and other routes free from forced reopening. Extend the existing player-tap regression with repeated lifecycle cases.

Validation: focused widget suite passes (12); analyzer reports no issues; scoped formatting complete. The native test set completed across three segments: 218 before a 120-second tool timeout, then 45 passed and 275 passed/one web-only skip. No single-run full-suite result or aggregate coverage report exists. **Blocked:** no attached Android device or configured emulator/system image; actual Android reproduction, keyboard verification, Android version, and the two requested recordings are absent. Widget tests are not Android IME evidence. No PR, push, release build, deploy, signing, schema change, or production-data access was performed by this worker.
