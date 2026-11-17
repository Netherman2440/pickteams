# Real hosted context compatibility correction

PR66 current head: `f0384d6e38673bf0f44423514e7749cb316c83d3`, parent `7ed7651e52b3d5ec868e353ed20447e3bdf7f7cd`, accepted base `1377d580307959b8dc25594bff9e61370c539564`. Only the candidate context block, its tests and `docs/operations/candidate-context.md` changed. The complete correction was published to the SAME draft PR under the exact previous-head lease after an actual independent executed SECURITY pass.

## Why the boundary changed

Real Main44092963250 selected the candidate path and failed before compilation because a present, valid auxiliary PR merge SHA differed from the trusted runner checkout. Its original value and cause are UNKNOWN. Current PR metadata is not the original event. The before/after reproduction uses authentic known Git objects with a clearly synthetic unequal auxiliary field; it is not a reproduction of an authenticated event payload.

Official GitHub contracts define `GITHUB_SHA` as the PR merge-branch checkout and describe separately maintained PR test-merge/mergeability metadata. They do not promise atomic equality for the optional `pull_request.merge_commit_sha` snapshot. Relevant independently fetched excerpts and hashes are retained here.

The optional field remains strictly typed when present, but grants no authority over source selection. Trusted reviewed workflow/repository/server/ref, immutable GITHUB_SHA equal to physical HEAD, event head/base, exactly ordered parents, recomputed tree, complete history/origin and all staged/physical-source checks remain required. No head fallback, environment override, remote lookup, retry repair, production pin or native/private-payload change was added.

## Actual executed review and retained tests

`executed-security-review.md` is the original separate reviewer's verbatim PASS at exact f038. It actually ran a focused gated proof: **76 independent outcomes**, including **64 expected rejections and 12 valid controls**. One rejection is the deliberately expected predecessor failure. Forged checkout cases set the auxiliary field equal to the malicious checkout; parent/tree/source failures still reject. The raw log and per-case paths are included. This is a continued independent reviewer, not the implementation author or a new cold context.

Worker focused tooling tests passed **59** cases. Its reused nine privacy methods passed with unequal auxiliary metadata; all 11 privacy negatives and 84 JSON compositions rejected. AST receipts show every other candidate/production/privacy/compiler definition unchanged. Original ec UI and schema inputs remain equal; the nine screenshots retain exact-ec provenance, not new captures.

**Full local Python did not run.** Immediate lock admission succeeded, then memory2602596 KiB was below2621440 KiB. Exit76 occurred before execution. Exact pending command and source are preserved. No pass, test failure or local retry is implied. Intake permits source-safe draft publication after actual security clearance to use existing hosted CI for the full suite. That hosted suite MUST pass before merge/release.

## Open gates

Real new Main must compile configured `lib/main.dart` and upload its NONPROMOTABLE candidate envelope. External GitHub artifact digest, every archive/payload path and hash, source/config/context/history bindings, actual configured browser startup and later independent artifact acceptance remain required. Synthetic fixtures and detached checksums do not provide hosted authentication.

Owner conditional production approval stays valid. There is separately no known agent-accessible administrator schema route or prior stars migration receipt; this is not proof that the column is absent. No bulk dbpush, unrelated old RPC operator package, credential/grant hunt or unchecked DDL is allowed. New production delivery still needs reviewed schema readiness, a new matching web/Android version and newly built/signed/audited/full-download-verified native artifact. Completed1.0.6 remains unchanged.
