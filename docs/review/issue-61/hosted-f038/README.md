# Actual hosted configured candidate: compile passed, receiver proof pending

Main [44100639905](https://github.com/Netherman2440/pickteams/actions/runs/44100639905), attempt 1, completed SUCCESS for head `f0384d6e38673bf0f44423514e7749cb316c83d3`, PR66, same repository. The coordinator inspected actual job/step metadata and raw producer logs, not only observer status.

- Analyze passed: 166 Python tests, four database-free Supabase tests, branding/OAuth, locked dependencies, exact-config analysis, full Flutter tests, coverage and Chrome auth. Counts 166/4 are from actual producer logs; local full Python had been denied before execution and is not relabeled as a local pass.
- The configured PR job actually ran `candidate_main`, all source stages, pinned Flutter and the real `lib/main.dart` compiler. The build and NONPROMOTABLE upload passed. `compiler-excerpt.log` selects the actual relevant lines; the full job is linked there.
- Production build and production provenance/web upload were intentionally skipped. This is candidate validation, not release deployment.

## Externally authenticated archive

Actual artifact **14336672484**, name `unaccepted-web-candidate-f0384d6e38673bf0f44423514e7749cb316c83d3-b441ac4abfccd840b45b3f182f1c1c2a084795a8`, size 18473739 bytes. External GitHub API SHA256 and the single downloaded raw ZIP both equal:

```
6987795f4ef31e7fbfdbe2f85a5c7c1d316d8755887d3ab10fe120e6bb28391e
```

`ci-artifacts.json` and `download-receipt.json` preserve that external binding. Coverage artifact14336871289 is separate and is not candidate proof. The archive has 50 unique entries, 48217956 uncompressed bytes and only candidate.json, candidate.json.sha256 and web roots. Initial path/type/size checks passed. The ZIP and compiled web remain private operational artifacts and are not committed here or promoted.

Actual GitHub checkout API receipt binds merge `b441ac4abfccd840b45b3f182f1c1c2a084795a8`, ordered parents `[1377d580307959b8dc25594bff9e61370c539564, f0384d6e38673bf0f44423514e7749cb316c83d3]`, tree `895778801a6d96e79462f2b5f1960a52f7171fec`.

## Still open at this receipt

The original worker now verifies the complete inner manifest/detached hash, exact payload set and every file hash, source/configuration/context commitments and actual configured unauthenticated browser startup. A separate final artifact review is required. Archive authentication and a successful build do not alone close those gates or approve promotion.

The owner already gave conditional production approval. Required reviewed schema still has no known agent-accessible administrator route or prior application receipt; absence of a route is not proof that the column is absent. New joint production delivery needs schema readiness, a new version/code and NEW Android build/signature/audit/provenance/full public-download verification. Current 1.0.6 is unchanged. No broad approval question, credential hunt, bulk dbpush or unchecked rollout is authorized.
