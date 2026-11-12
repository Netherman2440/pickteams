# Bounded cleanup review

Candidate: a98b2c6f5ba9f75ce3216fdb7988460c04f6fbf0. Base: f860274565e21fa1fdbf202f8b6b6695844a88b0. No blocking acceptance defect or new note found. Both prior non-blocking notes are resolved.

## Source

Read the prior verdict, source/pixel review and integration mapping at /home/agents/dev/pickteams/.limen/proof/F015/review-1/. Git HEAD matches the candidate; initial and final status are empty. The exact base-to-candidate diff changes only three files. The 15 prior feature files match the base except the inspected assertion-string wrap; this does not reopen other changes integrated into the base.

PROVEN by source: /home/agents/dev/.pickteams-limen-worktrees/2026-11-12-f015-cleanup-and-fresh-pixels-re-fcd8fc1c/app/lib/core/widgets/lineup_header.dart:27–44 now disposes each temporary painter in finally, after reading height, also covering a layout exception. Width, scaler, direction and height calculation are unchanged.

PROVEN by source and pixels: /home/agents/dev/.pickteams-limen-worktrees/2026-11-12-f015-cleanup-and-fresh-pixels-re-fcd8fc1c/app/lib/features/matches/presentation/pages/match_details_page.dart:735 now excludes bottom rankings in both edit modes. The unchanged edit-mode section headers already supply each ranking. View-mode totals and probability remain. The edit-mode getters at lines 60–62 confirm this changes score editing only; team editing already excluded these totals.

PROVEN by source and inspected execution: /home/agents/dev/.pickteams-limen-worktrees/2026-11-12-f015-cleanup-and-fresh-pixels-re-fcd8fc1c/app/test/features/matches/presentation/lineup_collapse_test.dart:42–57 adds ranking-count checks at 360 and 1440 without deleting existing assertions. The red evidence at /home/agents/dev/pickteams/.limen/proof/F015/review-notes-repair/red.log shows both real four-versus-two failures. The fresh combined VM record shows both now passing. No math, roles, navigation, lifecycle, request, snapshot, drag or score-label source changes occur in this diff.

## Execution evidence inspected, not rerun

The complete pipeline is under /home/agents/dev/pickteams/.limen/proof/mobile-feedback/a98b2c6f5ba9f75ce3216fdb7988460c04f6fbf0/. Read all four runner-as-executed copies. They pin HEAD and require clean checkpoints. The combined runner installs offline from the enforced lockfile, restores only the known SDK analysis-options insertion before checks, and compares input hashes. Production builds the default lib/main.dart release target; browser proof builds the separate profile fixture. No private config or protected checkout was opened.

Inspected results: 275 VM tests passed, one existing web-only reset-email test skipped in VM; all 10 Chrome auth tests passed. Analysis found no issues. Formatting checked 270 files with zero changes. OAuth and branding static contracts passed; 12 branding Python tests and 4 lineup-capture Python tests passed. Production and fixture builds succeeded. Capture reports 14 cases and zero failures. All 15 recorded exit files are zero, including the overall pipeline and capture runs.

Independent audit verified every recorded input hash against candidate Git blobs: all 433 tracked app files for combined/production, and 285 fixture inputs at each browser checkpoint. All recorded source checkpoints equal the candidate, all status/diff checkpoints are empty. Details and exact absolute evidence paths: /home/agents/dev/pickteams/.limen/proof/F015/review-2/audit.json and /home/agents/dev/pickteams/.limen/proof/F015/review-2/additional-audit.json.

The older harness failure remains recorded at /home/agents/dev/pickteams/.limen/proof/mobile-feedback/f860274565e21fa1fdbf202f8b6b6695844a88b0/combined/lineup-capture-tests.log: Python lacked PIL; its run.exit remains 1. This is not an app defect. No old failure record was modified, including the earlier formatter evidence; that formatter failure was not independently re-audited here.

## Pixels

Independent PNG/hash audit checked the exact 14-case matrix and all 54 JSON-listed originals: 360×640 or 1440×1000, matching viewport metrics and SHA-256. Exactly 52 are RGB-pixel-identical to the previously reviewed 760 frames. Only the two score-editor images differ. Their changed bounds are [51,569,309,582] on phone and [459,526,1037,539] on desktop: the removed bottom rankings.

Opened old and fresh phone/desktop score-editor originals. Fresh frames visibly show one 387.0 home ranking and one 355.0 away ranking, with no duplicate below the rosters. Date, 14:5 inputs, Save and Cancel remain unchanged. The unchanged truncated home input label is not reopened.

Generated 19 contact sheets with /home/agents/dev/pickteams/.limen/tools/proof_contacts.py. Independently compared all 54 contact tiles to originals: no resizing or pixel changes. Opened all five phone sheets at /home/agents/dev/pickteams/.limen/proof/F015/review-2/contacts/. They show complete eight- and eleven-player collapsed rosters, stable colored sides, full saved 17:6, changed team name followed by Cancel restoration, and long-text collapsed/bottom pairs. Large-text bottom frames retain full totals and 52%/48% probability below the roster; normal scrolling clips intermediate rows at the pinned header, as in the settled review.

Also opened fresh desktop saved-score and cancelled-team originals and both pages' desktop 1.6× collapsed/bottom originals. Saved 17:6 and restored Niebiescy/Czerwoni remain visible. Long names wrap legibly; final rows, full totals and probability are exposed at bottom. Those frames are pixel-identical to the prior evidence. Desktop contact sheets were generated but not all opened; unchanged desktop coverage is bounded by exact pixel equality and the prior full review, not by scenario flags. No paint claim relies on DOM semantics.

## Checks performed and limits

Actually ran: Git HEAD/status/diff and targeted blob comparisons; file discovery and targeted log searches; /home/agents/.local/share/pickteams-image-tools/bin/python /home/agents/dev/pickteams/.limen/proof/F015/review-2/audit.py (passed); the contact generator (54 originals, 19 sheets); a separate inline Pillow/Git audit (433-file manifest complete, 54 exact contact tiles, exact case matrix, clean HEAD). Read source/callers/tests, runner copies, supplied logs and requested images. No install, Flutter/JS/native build, application test or browser run was started by this reviewer.

UNVERIFIED: physical/native/manual acceptance, live backend authorization/persistence, hosted SQL, and deployed-client behavior. Static OAuth/branding checks and synthetic fixture capture do not establish those. This verdict covers only a98, not the future main rebase. The coordinator must verify all app bytes remain identical after the proposed documentation/operator-only rebase before carrying this evidence forward. No source, spec, board, branch, protected checkout, credentials, publication or deployment was changed. Evidence writes were limited to this review directory and the designated job note.
