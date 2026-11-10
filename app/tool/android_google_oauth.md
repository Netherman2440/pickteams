# Android Google OAuth

## Callback contract

The exact native redirect is `pl.pickteams://auth/callback`. In the Supabase project dashboard, Authentication → URL Configuration → Redirect URLs must include **`pl.pickteams://auth/callback`**. Keep the existing web redirects, Site URL, and Google provider settings. This is a Supabase redirect allowlist entry, not a replacement for Google's authorized Supabase HTTPS callback. No dashboard settings were changed by this work.

The Android application ID remains `com.example.app`. The main manifest grants Internet access for release builds and accepts VIEW / DEFAULT / BROWSABLE for scheme `pl.pickteams`, host `auth`, exact path `/callback`. Flutter default deep-link routing is disabled because `app_links` inside Supabase Flutter owns these links. Launcher assets are not part of this change.

## Session ownership

The lockfile selects `supabase_flutter 2.18.3` and `gotrue 2.27.3`. `Supabase.initialize` uses PKCE by default and supplies persisted SharedPreferences PKCE storage. `GoTrueClientSignInProvider.signInWithOAuth` generates the challenge and forces an external browser for Google on Android. Its future reports browser launch, not authentication.

`SupabaseAuth._handleIncomingLinks` subscribes to `app_links.uriLinkStream`, including the initial Android link. `_handleDeeplink` calls `getSessionFromUrl`; GoTrue exchanges the code with the stored verifier, saves the session and emits `signedIn`. Callback AuthExceptions go to `onAuthStateChange` as stream errors. On web, the same SDK handles the initial URL and clears auth URL parameters. The app must not exchange the code a second time.

`AuthNotifier` observes SDK state, publishes it before awaiting compatibility token storage, and serializes those writes. Launch completion cannot replace a newer event. A browser close with no callback leaves the form enabled after launch. Callback errors allow retry; late errors do not discard an authenticated session. Login owns invite joining and navigation to `/me` or the invited squad. Registration forwards OAuth sessions to login instead of signing them out. Password registration keeps its email confirmation behavior.

The callback page observes SDK state on both platforms, including an already restored session. It never reads `Uri.base` or exchanges a code. Retry is always available, including when an error occurred before the page subscribed; after 15 seconds it stops showing a spinner. A later session still completes navigation.

Password reset is deliberately separate. Its existing web redirect remains `/#/auth/reset`; this change does not add native password-recovery links. The existing native password-reset request still uses a web-only origin and is not repaired by the OAuth callback.

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
