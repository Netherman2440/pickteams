# One manual stars-schema operation

The package passed final local PostgreSQL16 proof and separate executed SQL/security review. The coordinator accepted the exact delivery and verified the public Raw response byte-for-byte. The current pipeline does not apply this migration automatically. No production SQL has been executed by the agents.

1. Open the [reviewed complete Raw SQL](https://raw.githubusercontent.com/Netherman2440/pickteams/3047fd512bb3b729022e5b4140b87d4a597b6cb9/supabase/tools/squad_star_thresholds_operator.sql).
2. In Supabase Dashboard, select the correct production Pickteams project. Use the existing administrator session and **SQL Editor → New query**.
3. Paste the **whole file** and run it **once**, not a selected fragment. Do not add other migrations or edit the checks.
4. Return the actual nine-boolean result as text, plus confirmation that the whole execution had no errors and COMMIT completed. No credentials, URLs, user rows or dashboard screenshot are needed.

All nine flags must be true, except `migration_history_present` may be false. That false value means history remains absent; it does not create or reconcile an older baseline. The other flags are `canonical_source_sha256_matches`, `column_contract`, `validator_contract`, `constraint_contract`, `owner_update_rls_contract`, `policies_acl_unchanged`, `migration_record_exact_or_absent`, and `prior_history_unchanged`.

**Any error or lost response: stop. Do not rerun.** If a failed transaction is still open, run only `ROLLBACK;`. A successful COMMIT cannot be undone by ROLLBACK. An unknown outcome requires metadata review before another action. Do not add grants, remove objects, use IF NOT EXISTS or run bulk dbpush to bypass a refusal.

Exact delivery: `3047fd512bb3b729022e5b4140b87d4a597b6cb9`, separate from unchanged app source f038. File SHA256: `f26b6a1b597e83c9a989bc73f6ae6bf1302370ddbf1bfe25d90a5dfa09c7cfba`, 19,173 bytes; public HTTP200 and match to independently reviewed copy verified. [Full operator rules](https://github.com/Netherman2440/pickteams/blob/3047fd512bb3b729022e5b4140b87d4a597b6cb9/docs/operations/squad-star-thresholds.md).

The SQL adds the nullable field, validator and constraint, and only the new history record if compatible history exists. It does not backfill data or change policies/grants. The result and NOTIFY do not prove hosted API/cache/Auth readiness or complete the new joint WEB+ANDROID release. Those remain later checks; old1.0.6/native568f is unchanged.
