# Pickteams coordination

Use the standard multi-coordinator Limen workflow: a persistent intake session delegates each independent feature to a persistent Pi coordinator in Herdr. A coordinator is not a `limen spawn` job. Workers and reviewers are Limen jobs in isolated worktrees.

## Intake dispatcher

- Keep the project's existing GitHub binding on the intake session. Do not reconnect the project for each feature: the installed doorbell has one binding per repository.
- Keep intake short. Route requests, launch claim-bound initial jobs when requested by the feature coordinator, and return. Do not implement features, run validation suites, or wait synchronously for their completion here.
- Before dispatching, inspect existing jobs and `.limen/task-coordinators/`. Reuse the feature's live coordinator. Never create a second implementation because a claim says pending or a session is busy.
- Only the registered intake session runs `limen github work`, `review`, or `resolve`. Preserve its environment and all private-poller boundaries. Never impersonate that session or change authoritative claims/cursors.
- Recover pending claims deliberately: check both matching jobs and the intake transcript before acting. Each intake turn also checks other unresolved mirrored claims, so requests rejected during a busy turn are not forgotten.
- Hand initial jobs to the feature coordinator by exact ID. After it confirms `limen watch <id>`, intake may unwatch that job. Forward later issue/PR comments to the same coordinator. A no-job `github resolve` may acknowledge a successfully forwarded request; it is not feature completion.
- Keep an issue-to-PR mapping in the feature's runtime folder. Route PR feedback by that mapping, not by creating a new feature coordinator for every comment.

## Feature coordinators

- Start an ordinary interactive Pi session with `LIMEN_COORDINATOR=1`, the approved explicit model route, project hooks, and the canonical project root as cwd. Give it a stable task title. Its Herdr terminal must outlive the launching terminal. Do not use `limen spawn --role coordinator`.
- Keep runtime identity, brief, owned job IDs, PR link, dependency and handoff evidence under `.limen/task-coordinators/issue-<number>/`. These ignored files are operational state, not a second specification system. Durable feature intent stays in its issue and the project's normal specs.
- Own one feature and its full PR feedback cycle. Subscribe only to the named jobs assigned to it with `limen watch <id>`. Never use `watch --running` or control another coordinator's jobs.
- Implement and validate in Limen worktrees. Do not change product code, switch branches, merge, or run competing builds in the shared primary checkout. Serialize any shared board/spec updates through intake.
- Ask intake to start the initial claim-bound GitHub job. Subsequent implementation, repair and review jobs use the ordinary Limen commands and this coordinator's subscriptions. Explicitly pass engine, provider, model and thinking choices; do not substitute a model silently.
- Publish actual results and visible screenshots/recordings in the issue or PR. Name the validated commit and distinguish fixtures/emulation from a physical device. Do not leave the owner with local evidence paths only.
- For issues #59, #60 and #61, opening/updating a PR is authorized; merge, deploy and production-data changes are not. Do not extend the earlier PR #58 deployment permission to these requests.
- Independent features may run concurrently. Issue #61 must not start implementation before the historical-ranking fix in #60 is complete and verified. Base it on that verified candidate without merging the dependency or rewriting production data.

## Recovery and limits

A live process, an accepted prompt and a job marked done are different facts. Confirm the coordinator processed its handoff and subscribed to the job before reporting ownership. Keep session paths and Herdr terminal identities so recovery resumes the original conversation instead of duplicating work.

This is an agent-managed workflow, not a new native GitHub router. The installed Core adapter can reject delivery while intake is busy. A clean poll does not prove every request was processed. Inspect unresolved claims and report delivery gaps; never promise unattended recovery that has not been tested. Closing a viewer must not stop a coordinator; killing its actual Herdr terminal still can.

Reference workflow: https://mega.dev/autonomous-product-development. Package reference: `docs/setup.md` (coordinator sessions), `templates/agents.md` (roles and ownership), and `docs/remote.md` (GitHub doorbell).
