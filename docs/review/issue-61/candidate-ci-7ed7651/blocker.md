# Real candidate CI stopped at event/checkout context binding

Actual Main [44092963250](https://github.com/Netherman2440/pickteams/actions/runs/44092963250) completed FAILURE at source `7ed7651e52b3d5ec868e353ed20447e3bdf7f7cd`. The coordinator inspected actual jobs/steps, failed-step log and artifact API metadata. This is not inferred from observer exit.

Analyze job134072616307 passed tools, Supabase tooling, branding/OAuth, locked packages, exact-config analysis, full Flutter tests, coverage and Chrome auth. Web job134076271196 selected the new **Build NONPROMOTABLE configured PR candidate** step; production build/upload steps were skipped as intended.

The candidate step failed BEFORE compiler/SDK admission at `candidate_context` in build_web_release.py:478:

```
if pr.get('merge_commit_sha') is not None:
    assert sha(pr['merge_commit_sha']) == checkout, 'Candidate event merge mismatch'
AssertionError: Candidate event merge mismatch
```

The stack proves a present, well-formed auxiliary event SHA differs from GITHUB_SHA; its exact value is not printed. Do not invent that value or assert a stale-event cause as independently proved. Current API state is not the original event payload.

Authenticated read-only GitHub API confirms run head7ed/base1377. Checkout and coverage artifact identify merge `93e9f2a7bd7cdd7d0f66c89573b3141ebfedfeda`; its API parents are exactly [1377d580307959b8dc25594bff9e61370c539564, 7ed7651e52b3d5ec868e353ed20447e3bdf7f7cd], tree `b65d4cb78c749eb89641f2a293202997b970000f`. Current PR API reports that same merge SHA and mergeable=true. These observations do not substitute for missing original auxiliary event data or trust a local synthetic context as hosted authentication.

Only coverage artifact14333680386 exists. Candidate bundle/provenance upload was skipped. There is NO configured candidate artifact to authenticate or run, and no browser/startup proof. Hosted client configuration was present/masked; no missing-credentials or stars compilation failure is claimed. Vercel preview FAILURE is separately observed with raw cause unknown.

Original implementation session now owns focused follow-up `2026-11-17-issue-61-real-candidate-context-f8b39e36`. It must investigate supported provider semantics and, if needed, add bounded private-free source-identity diagnostics. No raw event/environment/config dump. A correction must retain trusted workflow/repo/non-fork/main/ref/origin/full history, immutable GITHUB_SHA=checkout, exact event head/base, ordered parents, recomputed merge tree and clean physical source checks. Do not simply delete the assertion, accept arbitrary metadata or blind-rerun. New source/SECURITY review precedes any exact-lease PR publication and new real CI.

This is a narrow candidate-context follow-up, not a production guard/pin/native/private-payload relaxation. Owner conditional production approval remains valid; new version/native/schema/artifact gates remain. Schema has a separate exact blocker: no agent-accessible admin route/prior stars migration receipt, not proof of absent column. No bulk dbpush, old RPC operator package, token/grant hunt, unchecked rollout or duplicate coordinator.
