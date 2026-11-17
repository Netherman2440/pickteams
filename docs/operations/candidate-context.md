# PR candidate checkout authority

## Provider contract

GitHub's [pull_request workflow contract](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request) defines `GITHUB_SHA` as the last merge commit on the PR merge branch, with `GITHUB_REF=refs/pull/<number>/merge`. Default checkout tests that merged result, not the head branch alone.

The [Get a pull request contract](https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request) describes a separately computed test merge: mergeability can be NULL while a background job runs, and `merge_commit_sha` depends on PR state. These documents do not specify a synchronous equality guarantee between that optional PR-state snapshot field and the runner's `GITHUB_SHA` for the event being executed.

This policy therefore validates `pull_request.merge_commit_sha` as a lowercase 40-digit SHA when present, but does not use it as checkout authority. NULL/absent metadata remains supported. Invalid types, malformed SHAs, duplicate event fields and invalid JSON still fail closed. There is no fallback to the head branch, environment override, remote metadata lookup or retry-dependent repair.

## Required authority, unchanged

Candidate admission still requires all of the following together:

- Reviewed GitHub Actions `pull_request` workflow context, exact repository/server, bounded numeric run/attempt, and matching PR/ref/workflow identity.
- Same-repository, non-fork head and base; main base; exact approved source origin and full Git history.
- Physical `HEAD == GITHUB_SHA`, with exactly ordered parents `[event.base.sha, event.head.sha]`.
- Checkout tree equal to a fresh local `git merge-tree --write-tree base head` result, plus the accepted-source ancestry check.
- At every existing build stage: clean index/status, unchanged full physical bytes and modes, no links/special files, no unexpected provider controls, and unchanged authoritative context.

The advisory field cannot rescue any failed requirement. It does not enter the immutable candidate identity or configuration commitments. Identity metadata and detached hashes are not authentication: the actual hosted workflow/run/source and external GitHub artifact digest still need independent verification. Candidate bundles remain NONPROMOTABLE. Frozen production/native guards and the accepted release pin are unchanged.

## Observed failure and limits

Main run `44092963250` at published head `7ed7651` selected the correct candidate step and failed before the builder's SDK/compiler stage with `Candidate event merge mismatch`. The log proves only that a present, well-formed auxiliary SHA differed from the runner checkout. **Its actual value is unknown. No stale-value cause is claimed.** The job had masked configured inputs, so this was not a missing-credentials failure.

The authentic checkout log/API facts are commit `93e9f2a7bd7cdd7d0f66c89573b3141ebfedfeda`, tree `b65d4cb78c749eb89641f2a293202997b970000f`, ordered parents `1377d580307959b8dc25594bff9e61370c539564` and `7ed7651e52b3d5ec868e353ed20447e3bdf7f7cd`. A later PR API merge SHA equal to that checkout is current state, not the original event payload. Only coverage was uploaded; no configured candidate bundle or browser proof exists for that run.

The failure-before/pass-after reproduction uses these actual Git objects with an explicitly synthetic unequal auxiliary field. Portable unit fixtures test valid variation and hostile checkout/head/base/parent-order/tree/repository/fork/ref/workflow/run/history/index/physical-byte cases under that variation. Real-history and mock-compiler regressions are not hosted authentication or compilation.

No raw event, client configuration or environment dump is needed for this correction. Public documentation and bounded public commit identities are sufficient. New source/security review must precede coordinator publication; actual configured hosted build, external archive-digest/full-envelope verification and privacy-bounded browser startup remain separate gates. Existing owner acceptance is not a substitute for those checks or for the later authorized schema route/new joint release.
