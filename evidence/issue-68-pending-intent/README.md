# Preserve pending search-keyboard intent — issue #68 follow-up

## Boundary and remaining gates

This repairs a deterministic source/model flaw in candidate `80a4d7317a9ee35bf8d7a13b366b4e31bd671f4f`. It does not establish the cause of the reported Android problem. Actual Android reproduction, visible software-keyboard acceptance, Android/API/IME versions, and both recordings remain unavailable. No Android reprobe, tool installation, or new runtime was attempted in this continuation. Keep publication blocked DRAFT and source-only until those gates close.

The unchanged independent review is `/home/agents/dev/pickteams/.limen/task-coordinators/issue-68/review-1/`. `report.md` says PASS, Source-DRAFT-only, not VERIFIED. Its `full.txt` ends `+538 ~1: All tests passed!`, `Command_exit=0`; `full.exit` is 0. `coverage-summary.txt` records all 42 files and aggregate 4,988/12,830 lines across 218 source records. That closes the earlier timeout/coverage gate only for exact `80a4d73`, not this successor. The parent will send the successor to the same reviewer for a complete native run. No full suite or coverage run was repeated here. Original worker evidence and independent failed probes were not edited.

## Proven invariant and seam

Seam: `_AvailablePlayersPanelState` in `app/lib/features/draft/presentation/pages/draft_selection_page.dart`.

Old code cleared `_restoreKeyboardOnResume` before its post-frame callback ran. A second departure could then replace the known restore intent with a transient unfocused snapshot and invalidate the first callback. The final resume had nothing left to restore. `red-old.txt` reproduces this with the old implementation and a new committed model regression.

The replacement `_SearchKeyboardIntent` states are:

| State | Meaning / transition |
| --- | --- |
| `hidden` | No permission to restore. Positive focused foreground insets establish `visible`. |
| `visible` | Visibility acknowledged. Leaving resumed with search focus establishes `restorePending`; settled zero insets or foreground focus loss cancel. |
| `restorePending` | Known open intent, possibly with a superseded callback and no focus. Departures do not replace it with a transient focus snapshot. |
| `awaitingVisibility` | The guarded callback issued a focus request. Intent is still pending until positive focused foreground insets acknowledge visibility. |

Both pending states survive another departure and ignore unacknowledged zero insets. The current generation alone may issue focus on resume. Hidden/paused releases even a pending focus request via `FocusNode.unfocus`; no timer, unconditional show call, or retry loop exists. A settled foreground focus loss after issuing the restore cancels it. A non-current route cancels intent through `ModalRoute` dependency changes and lifecycle guards; covering-route pop must not resurrect it. Replacement/disposal invalidate callbacks. Native non-Android targets do not enter the restoration path.

The SDK source confirms these narrow framework mechanisms: `packages/flutter/lib/src/widgets/focus_manager.dart:924-948` allows `unfocus` to cancel a node marked for focus even before `hasFocus` is true; `packages/flutter/lib/src/widgets/routes.dart:1309-1318` documents the `ModalRoute.of` dependency on `isCurrent`. These are focus/route guarantees, not Android IME ordering guarantees.

The acknowledgement boundary is visible insets, not callback execution or focus acquisition. `mutation-premature-ack.txt` deliberately marked a focus request as `visible`; the regression then failed at the next restoration after zero insets. The mutation was removed before final validation.

## Regression replacement and checks

The old single other-route/disposal test was replaced by six queued/issued cases across cover, replacement, and disposal. They include another background/resume under the new route and after covering-route pop. The new rapid-departure case runs three superseded resume cycles, preserves `Anna`, partial selection `[1,3]`, and the selected roster, then exercises the pre-visibility boundary and settled manual dismissal. A separate settled foreground connection-close case cancels issued intent and checks tap-to-reopen. Existing Back, selection-tap #48, Done, Enter, arrows, and scroll cases remain. iOS/Linux exclusion has committed model checks. These are Flutter signal models, not Android traces.

All heavy commands used separate inline immediate `flock -n -E75 /tmp/pickteams-flutter-validation.lock` admission, then `MemAvailable >= 2621440 KiB`. No helper, polling, waiting, denial retry, or gate denial occurred. Each log names its exact command and exit. SDK executable prefix: `/home/agents/.local/share/pickteams-f001-sdk/flutter/bin/`.

- `dependencies.txt`: `flutter pub get --offline --enforce-lockfile`, exit 0. Recovered worktree had no package config. No lockfile change or dependency symlink; the unrelated automatic analyzer-options upgrade was removed.
- `red-old.txt`: focused rapid-departure regression on unchanged old app source, exit 1 at final-resume focus assertion.
- `green-new.txt`: the same model case on the repaired app source, exit 0, one passed.
- `focused.txt`: expanded focused file before final format/roster assertions, exit 0, 21 passed.
- `mutation-premature-ack.txt`: deliberate premature visibility acknowledgement, exit 1 at focus after the later zero-inset/departure boundary.
- `format.txt`: scoped Dart format, exit 0, two files changed.
- `focused-final.txt`: final focused file after removing mutation and formatting, exit 0, 21 passed.
- `analyze.txt`: `flutter analyze --no-pub`, exit 0, no issues.
- `recovery.txt` and `preservation.txt`: accepted branch/base/source admission and unchanged prior evidence/overlays/dependency files. Logs retain assertion content and exits; trailing whitespace is removed for Git checks.

## Native ordering questions deliberately left open

1. **Zero insets before vs after inactivity.** A zero while still resumed can mean explicit dismissal or early platform background hiding. Once inactive, collapse is ignored. The independent old-candidate probes fail the collapse-before-inactive expectation but pass collapse-after-inactive. No measured Android sequence chooses between those meanings. This repair does not redefine that boundary.
2. **Quick connection-close Back then app switch.** The independent probe closes the connection and departs without a settled focus notification/zero-inset frame; its old-candidate expectation fails. A settled foreground close cancels intent in this repair, but close/focus/lifecycle ordering without that settlement remains unmeasured. We did not turn the quick native hypothesis into a required fake order.
3. **Inactive-only recovery while focus remains.** The independent old probe hides the keyboard during inactive-only and expects resume to show it. `FocusNode.requestFocus` can be a no-op for an already-focused node. This repair keeps the no-unfocus-on-inactive boundary and makes no unconditional IME calls. Whether an authorized Android transition needs that behavior is still unknown.

Additionally, before visibility acknowledgement a zero-inset signal without focus loss cannot distinguish user dismissal from stale background insets. The repair preserves known pending intent in that interval; actual Back/IME/lifecycle traces are still required. The settled explicit-Back model tests are not proof for that interval.

## Handoff and publication

Accepted base remains `dc4f2a490e8ebeb70c8ad764de56719cba112c1f`. Same branch: `limen/github-issue-68-7043656121`. `final-git.txt` in the external follow-up artifact copy records final head/tree. No primary edits, push, PR, merge, deploy, signing, production-data/credential access, Android commands, or server operations occurred. Overlays and production1.0.7/public APK artifacts/server remain untouched. No process was started to remain running.

PR summary addition: preserve search-keyboard intent across superseded resume callbacks and wait for visibility acknowledgement; cancel on settled foreground focus loss and route change. Add rapid-switch, partial-selection, cancellation and platform-exclusion regressions. Source model tests pass; new independent full-suite validation and all actual Android/video gates remain open.
