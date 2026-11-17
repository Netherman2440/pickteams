# Draft PR66: configured-build validation uses a frozen release contract

Actual Main run [44043449198](https://github.com/Netherman2440/pickteams/actions/runs/44043449198) completed FAILURE for head `ec6630d6d732d3c9191ef74c5e5460bd3cc2f847`. The run checked out PR merge `be53e217cf6c4a247a5663a0e436d8dcdf292fdd`. The coordinator read actual result/jobs/steps, failed-step log and artifact list; this is not inferred from observer exit.

The `analyze` job [133903308047](https://github.com/Netherman2440/pickteams/actions/runs/44043449198/job/133903308047) passed: Python tools, Supabase tools, branding/OAuth, locked packages, restored documented analyzer migration, exact committed-config analysis, full Flutter tests, coverage upload and Chrome auth.

The `web-build` job [133905553536](https://github.com/Netherman2440/pickteams/actions/runs/44043449198/job/133905553536) failed in **Build configured production entrypoint with pinned SDK**, at `Release source check: before-sdk`, before compilation. Actual stack:

```
build_web_release.py: verify_source_stage -> verify_web_source
release_contract.py:82: verify_source_history
assert set(changed) <= set(RELEASE_FILES) | {'app/pubspec.yaml', 'app/.gitignore'}
AssertionError: Unapproved source differences
```

Current accepted main's release contract pins accepted source `4fe251fc2dadf5cd0e9abc70a25b2220096ded02` and permits only reviewed release-tool/version changes. New stars runtime files are correctly outside that frozen PRODUCTION RELEASE contract, but normal PR candidate validation currently calls the same release builder. This is a validation-policy seam, not a demonstrated stars compiler error. Hosted client configuration was present with masked values; no missing-credentials claim or credential recovery is needed. No configured web build was produced. Release provenance and configured build upload steps were skipped. Only the coverage artifact is listed.

Normal Vercel PR preview is SUCCESS, but it neither overrides failed required Main nor proves an approved production release. Local tests and synthetic frames remain valid at exact source; whole-feature configured-build acceptance remains OPEN and PR66 stays DRAFT.

Intake `t5r` was sent the exact failure and should route a bounded candidate-versus-release validation fix. The correct boundary is an unaccepted candidate's configured `lib/main.dart` compilation with candidate-specific provenance, separate from promotion/release of a frozen owner-accepted source. The production guard must continue rejecting stars until actual acceptance. Do not add lib paths to RELEASE_FILES, repin accepted runtime as if stars were accepted, skip configured proof, change provider settings/privileges or broadly rewrite release workflows in this feature. No such change was made here.

Same PR66, source branch/head and nine-frame evidence remain. Existing worker/reviewer jobs and read-only observer are terminal. No retry or new helper should run without a concrete routed fix/useful event. Release64 ownership is separate. No merge, manual deploy, production schema/data rollout, new grant, token hunt or false full-success claim.
