# Wydanie web na Vercelu

The repository defines the Vercel build. `vercel.json` supports the repository root; `app/vercel.json` supports the `app/` root. Both run `app/tool/build_web_vercel.py` and publish only `app/build/vercel-web`. The router has two closed source policies. It does not infer the target from a branch name or from control diagnostics.

## Feature PR preview boundary

- Require provider system metadata: `VERCEL=1`, matching `VERCEL_ENV` and `VERCEL_TARGET_ENV` (`preview` or `production` only), GitHub provider, exact owner/repository, full commit SHA equal to physical HEAD, and a valid branch ref. Missing, custom, or conflicting target metadata fails before SDK installation.
- Preview requires a non-main feature branch, a verified PR identity, full local history, and ancestry from the existing accepted source. A positive `VERCEL_GIT_PULL_REQUEST_ID` remains provider authority. An absent or empty value requires the GitHub evidence below; a malformed nonempty value fails without fallback. The hosted provider authenticates its system variables; a local environment dictionary does not. The actual preview deployment must independently identify the same repository, PR, and commit.
- Every preview build stage checks the index, physical tracked bytes/modes, origin (when present), and exact checked app-root materialization. `.vercel/project.json` remains a source control, not an ignored output. The existing strict schema, no-link file access, SDK pin, locked dependencies, checked analyzer restore, real `lib/main.dart` compiler, and closed public-payload/privacy audit all remain active.
- Set `PICKTEAMS_PREVIEW_SUPABASE_URL` and `PICKTEAMS_PREVIEW_SUPABASE_ANON_KEY` only in Vercel's Preview scope. Use a separately approved non-production backend and public client key. No fallback to `SUPABASE_URL` or `SUPABASE_ANON_KEY` exists. Do not copy production configuration to Preview.
- Preview writes an unaccepted candidate envelope under `app/build/candidate-web/`. Only its audited runnable payload is copied and hash-checked into `app/build/vercel-web/`, with `/preview.json` as the unaccepted receipt. It sets `promotable=false` and `productionAccepted=false`. It never writes `/release.json`. A stale destination, stale candidate envelope, or pre-existing compiler output fails admission. Do not restore these build directories from cache.
- The production route requires `main` without a PR, and still calls the frozen release history validator. Generic/native checks, `ACCEPTED_SOURCE`, and the release allowlist are unchanged. Neither a feature preview nor its receipt can authorize production or native promotion. GitHub's separate merge-candidate workflow remains unchanged; it does not authenticate a Vercel PR-head preview.

### PR linkage when the provider ID is absent

Vercel documents that [`VERCEL_GIT_PULL_REQUEST_ID`](https://vercel.com/docs/environment-variables/system-environment-variables#VERCEL_GIT_PULL_REQUEST_ID) is empty when a deployment is created on a branch before its PR exists. Its [GitHub integration](https://vercel.com/docs/git/vercel-for-github#a-deployment-for-each-push) deploys pushes as well as PR updates. Thus a first-push deployment can lack PR linkage. A missing-ID assertion alone does not prove whether a hosted value was absent, empty, or malformed.

For absent or empty IDs only, the builder uses GitHub's documented [List pull requests](https://docs.github.com/en/rest/pulls/pulls#list-pull-requests) public read API. The request is a GET to the fixed `Netherman2440/pickteams` repository, with `state=open`, `head=Netherman2440:<exact provider branch>`, `base=main`, and `per_page=2`. No credential, configurable endpoint, redirect, pagination, retry, or provider-ID substitution is used.

Admission requires exactly one result. Its API identity and positive number must belong to the fixed repository; both head and base repositories must be that same repository and not forks. The head branch and full SHA must equal the provider branch and physical checkout. The base must be `main`, with a full SHA available in local history and descended from the existing accepted source. Closed/merged, ambiguous, mismatched, malformed, oversized, paginated, unavailable, or rate-limited evidence fails closed before SDK installation. A branch without an actual open PR remains blocked. Opening the PR does not authorize a stale deployment whose SHA differs from the PR head.

The bounded HTTPS response is validated once at admission. The receipt records `pullRequestAuthority=github-open-pr`, the actual PR number, and `baseCommit`. A valid provider ID instead records `pullRequestAuthority=vercel`. Each subsequent build stage still checks the original provider context and exact worktree; it does not repeatedly query GitHub or reuse evidence across builds. This snapshot proves the admission identity, not continued PR state or production approval.

If public GitHub evidence is unavailable, do not add a token, use production configuration, disable protection, or invent a PR number. Fix the provider linkage or retry the exact current PR head after evidence becomes available.

### Safe production integration

The frozen production contract intentionally does **not** allow edits to either Vercel config, this new router, or these docs. Thus this branch can pass preview policy while production correctly fails with `Unapproved source differences`. Do not add these paths to `RELEASE_FILES`, repin this branch, reuse the old release descriptor, or treat a green preview as production approval.

Before a merge that can trigger Vercel production, the release owner must authorize a separate new joint-release descriptor for the exact reviewed runtime **and** build/config tree. That separate release must bind its approved source and version, pass strict production/native checks, and follow the release approval process. Keep this change as a draft PR until that integration is approved. The production router supports an authorized tree; it does not grant that authorization. No production deploy, alias update, or stable APK change is part of this work.

### Preview proof after branch push

1. Update the existing feature PR branch and request a real Vercel rerun of its exact new head. Confirm both provider target variables and the authenticated deployment commit. Verify the receipt's `pullRequest` and `pullRequestAuthority`: either provider linkage or a unique public GitHub PR snapshot must bind the same repository, branch, exact SHA, and trusted `main` base. If the provider ID is absent or empty, the public API must be reachable from Vercel. Do not infer hosted success from local mocked responses or a local public API read. Missing other target fields and malformed IDs still fail closed.
2. Check the real Vercel build log for admission at all stages and the pinned SDK. A root-control diagnostic alone is not evidence of a config failure. The observed #80 failure at `179df8dc5802c4cf55a14bd3dc9c4ac50273911d` is reproduced by the frozen history check, not by a guessed project-root setting.
3. Fetch `/preview.json` from that preview deployment. Check the commit, unaccepted kind and flags. Fetch `index.html` and `main.dart.js`; compare their hashes with the receipt's `files` entries (prefixed `web/`). Confirm `/release.json` does not serve an approved manifest. Open the real app in a fresh browser and check startup without production writes. Local mock-compiler tests do not prove hosted compilation or browser startup.
4. Keep production blocked on unapproved input. Do not test this by deploying or assigning a production alias. The offline negative tests cover that boundary.

Offline checks: `PYTHONPATH=app/tool python3 -m unittest test_build_web_vercel test_build_web_release test_release_contract -v`. The real-history test uses the existing #80 object without changing it or fetching; it explicitly skips if that object is absent. Its recorded local run must show no skip. Portable synthetic tests still cover both routes in shallow CI checkouts. No Flutter build is needed to test target selection or frozen source rejection.

## Wymagania

- Flutter 3.47.9, dokładny framework `c197ca5199e9ee5661e865596c9c07294dfab51c`, taki sam jak w GitHub Actions.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` in Vercel Production only; the separate `PICKTEAMS_PREVIEW_*` inputs above in Preview only. Use only a publishable key or an `anon` JWT; server keys are rejected.
- Numer wersji i builda w `app/pubspec.yaml`.

Nie zapisuj wartości konfiguracji do repozytorium, raportów ani logów. Skrypt przekazuje konfigurację kompilatorowi przez tymczasowy plik z uprawnieniami `0600`, poza katalogiem publikacji, i usuwa go również po nieudanej kompilacji.

Bez istniejącego SDK skrypt pobiera oficjalne archiwum, weryfikuje SHA-256 z metadanych wydania oraz dokładną wersję i rewizję frameworka. W CI i lokalnie można wskazać istniejący SDK przez `PICKTEAMS_FLUTTER_ROOT`; niezgodny SDK kończy build błędem. Instalacja zależności używa `--enforce-lockfile`. Kompilowany jest rzeczywisty `lib/main.dart`, nigdy fixture.

## Sprawdzenia przed scaleniem

Workflow `Main` uruchamia testy narzędzi Python, analizę Flutter, pełny zestaw testów native, osobny przebieg Chrome dla regresji auth — w tym test pomijany w przebiegu native — oraz skonfigurowany build web. Te same sprawdzenia uruchamiają się ponownie po pushu do `main`. Produkcyjne dane klienta są dostępne tylko w kroku kompilacji, nie w zadaniu testowym.

Preview Vercela musi przejść osobno. Zielone GitHub Actions nie dowodzą poprawnego buildu ani konfiguracji w Vercelu. Scalaj dopiero po sprawdzeniu obu wyników. Integracja Git Vercela publikuje produkcję po scaleniu do skonfigurowanej gałęzi produkcyjnej `main`.

## Weryfikacja produkcji

Only an approved production build contains public `/release.json`: wersję, pełny commit, przypięty Flutter oraz SHA-256 `index.html` i `main.dart.js`. Manifest nie zawiera konfiguracji Supabase. Ma nagłówek `Cache-Control: no-store`.

Po wdrożeniu:

1. Sprawdź status produkcyjnego deploymentu i przypisany commit, nie tylko status preview.
2. Pobierz `/release.json` z domeny produkcyjnej. Porównaj commit ze scalonym `main` i wersję z `pubspec.yaml`.
3. Pobierz pliki wymienione w `files` i porównaj ich SHA-256 z manifestem.
4. Otwórz aplikację w świeżym kontekście przeglądarki na szerokim i wąskim ekranie. Sprawdź, że nie ma pustego widoku ani błędu startu. Nie wykonuj operacji zmieniających dane produkcyjne w ramach smoke testu.

Błąd preview lub niedostępne logi nie są podstawą do uznania konkretnej przyczyny awarii. Jeśli build nadal nie przechodzi po nadpisaniu konfiguracji z repozytorium, potrzebne są rzeczywiste logi Vercela lub dostęp operatora.
