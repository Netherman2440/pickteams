# Android Google OAuth

## Callback contract

The exact native redirect is `pl.pickteams://auth/callback`. In the Supabase project dashboard, Authentication → URL Configuration → Redirect URLs must include **`pl.pickteams://auth/callback`**. Keep the existing web redirects, Site URL, and Google provider settings. This is a Supabase redirect allowlist entry, not a replacement for Google's authorized Supabase HTTPS callback. No dashboard settings were changed by this work.

The Android application ID remains `com.example.app`. The main manifest grants Internet access for release builds and accepts VIEW / DEFAULT / BROWSABLE for scheme `pl.pickteams`, host `auth`, exact path `/callback`. Flutter default deep-link routing is disabled because `app_links` inside Supabase Flutter owns these links. Launcher assets are not part of this change.

## Session ownership

The lockfile selects `supabase_flutter 2.18.3` and `gotrue 2.27.3`. `Supabase.initialize` uses PKCE by default and supplies persisted SharedPreferences PKCE storage. `GoTrueClientSignInProvider.signInWithOAuth` generates the challenge and forces an external browser for Google on Android. Its future reports browser launch, not authentication.

`SupabaseAuth._handleIncomingLinks` subscribes to `app_links.uriLinkStream`, including the initial Android link. `_handleDeeplink` calls `getSessionFromUrl`; GoTrue exchanges the code with the stored verifier, saves the session and emits `signedIn`. Callback AuthExceptions go to `onAuthStateChange` as stream errors. On web, the same SDK handles the initial URL and clears auth URL parameters. The app must not exchange the code a second time.

`AuthNotifier` observes SDK state, publishes it before awaiting compatibility token storage, and serializes those writes. Launch completion cannot replace a newer event. A browser close with no callback leaves the form enabled after launch. Callback errors allow retry; late errors do not discard an authenticated session. Login owns invite joining and navigation to `/me` or the invited squad. Registration forwards OAuth sessions to login instead of signing them out. Password registration keeps its email confirmation behavior.

On a native cold return, Flutter starts at `/` because link routing is disabled. `NativeAuthEntry` observes the SDK session and forwards only that landing route to login. It requests a frame for late events. It does not intercept other routes or web navigation.

The callback page observes SDK state on both platforms, including an already restored session. It never reads `Uri.base` or exchanges a code. Retry is always available, including when an error occurred before the page subscribed; after 15 seconds it stops showing a spinner. A later session still completes navigation.

Password reset is deliberately separate. Its existing web redirect remains `/#/auth/reset`; this change does not add native password-recovery links. The existing native password-reset request still uses a web-only origin and is not repaired by the OAuth callback.

## Local proof

Use the SDK setup in `app/tool/player_lists_proof.md`. Run all heavy commands with the shared non-blocking lock; exit 75 means the check did not run. Run only one lane at a time. Native SDK-event tests use the real installed Supabase Flutter/GoTrue code, a mocked `app_links` event channel, a mocked browser launcher, in-memory PKCE storage, and an in-memory HTTP transport. No provider or Supabase server is contacted. Test futures cross from SDK initialization into Flutter's fake-async zone. The harness advances widget frames and the real async queue together, bounded to 100 turns. Waiting in only one queue can stall a mocked plugin future; this is a test-harness constraint, not a production workaround.

```sh
python3 app/tool/check_android_oauth.py
cd app
flock -n -E 75 /tmp/pickteams-flutter-validation.lock flutter pub get --enforce-lockfile
flock -n -E 75 /tmp/pickteams-flutter-validation.lock flutter test --no-pub --concurrency=1 test/features/auth test/widgets/auth --reporter expanded
flock -n -E 75 /tmp/pickteams-flutter-validation.lock flutter test --no-pub --concurrency=1 --platform chrome test/widgets/auth/auth_regression_test.dart --reporter expanded
```

Browser tests need a local Chromium executable in `CHROME_EXECUTABLE`. On this host, use `/home/agents/.cache/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-linux64/chrome-headless-shell` and set `LD_LIBRARY_PATH` to `$HOME/.local/share/playwright-system-libs/root/usr/lib/x86_64-linux-gnu`, plus `FONTCONFIG_FILE=$HOME/.local/share/playwright-system-libs/fonts.conf`. These are the same user-local libraries used by `playwright-local`; no system install is needed. Flutter accepts but ignores `--concurrency=1` for web tests; the command runs one test file under the shared lock. They test the real forms and callback widget with controlled auth state and password use cases. Native SDK tests separately test one PKCE exchange, provider denial, failed exchange, retry, invite navigation, cold/warm callback ordering, and a stale code after a successful session. They also pass the existing web callback URL shape through the SDK's shared parser; this does not simulate browser startup or a real redirect. Neither suite proves a live provider redirect. The static Python check verifies intent/URI consistency, release network permission, unchanged app ID, and no app-owned duplicate listener/exchange.

After committing all source, tests, tools and documentation, record the candidate SHA and clean Git status, then format-check changed Dart files, run `flutter analyze --no-pub`, `flutter test --no-pub --concurrency=1 --coverage --reporter expanded`, the browser regressions, and `flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run`. Acquire the same lock separately for each heavy command. Record status again. Restore only the known Flutter `analysis_options.yaml` exclusion migration if it occurs. Keep raw logs and `lcov.info` under `/home/agents/dev/pickteams/.limen/proof/f006/<candidate-sha>/`.

## Real-device acceptance (not run here)

An operator must verify the allowlist above before this procedure. Do not place real tokens, callback codes, account data, or full provider URLs in evidence.

1. Build and install with the normal project configuration on Android. Confirm the application ID has not changed. This environment has no native JDK/Android SDK, so no APK was built here.
2. From login, tap Google. Confirm an external browser opens. Finish sign-in with a test account. Confirm Pickteams resumes, reaches the authenticated app, and retains the session after restart.
3. Repeat from registration. Confirm no email-confirmation page and no sign-out. Repeat with an invite pending and confirm the existing invite destination.
4. Repeat with the app process killed while the browser is open. Confirm persisted PKCE and the initial link finish authentication. Do not test code exchange with a fabricated code as proof of success.
5. Cancel at Google, close the browser without a callback, and simulate loss of network. Confirm forms remain usable and a new attempt can succeed. Confirm a late failed return does not sign out an already authenticated session.
6. On web, verify login, Google callback, password registration confirmation, reset email, and password update with a test account. Mocked tests do not establish dashboard, browser, or live-provider acceptance.

To check Android intent resolution without credentials after installing a build:

```sh
adb shell am start -W -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d 'pl.pickteams://auth/callback' com.example.app
```

This only proves dispatch to the app, not successful OAuth. No server, production write, or credential is needed for the local tests.
