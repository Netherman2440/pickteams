---
opened: 2026-11-10
---

# F006 · Google sign-in returns to the Android app

## Outcome

Google sign-in from the Android login or registration screen opens the provider and returns a completed session to Pickteams. The app does not attempt to construct a web origin on Android. Existing web sign-in and password flows remain usable.

## Scope

- Trace provider launch, native callback handling, session updates, and navigation together.
- Configure a stable Android callback and preserve the existing web redirect behavior.
- Handle launch failure, provider cancellation/error, and callback/session ordering without a stuck spinner or session loss.
- Document the exact Supabase redirect allowlist requirement and a safe on-device verification procedure.

## Out of scope

- Production provider/dashboard writes, credentials, schema or RLS changes, and new providers.
- App-ID changes, native Google SDK migration, launcher resources, and match UI.

## Acceptance

- Login and registration choose valid native callback URIs without accessing a web-only origin on Android.
- The Android callback configuration matches the URI sent to Supabase.
- A simulated successful native return updates auth state and reaches the authenticated app without parsing Uri.base as an OAuth response.
- Provider launch failure and failed/cancelled returns leave a usable retry path and do not overwrite a newer successful session.
- Existing web callback and password-auth regression tests pass.
- The handoff names the exact external redirect setting and separates mocked/build checks from unperformed real Google sign-in.

## Notes

Both provider buttons currently use `${Uri.base.origin}/#/auth/callback`, and the callback page uses Uri.base. Supabase Flutter already handles native deep links; inspect the installed SDK before adding a second listener or code exchange. Reuse that path where possible. Preserve password recovery if a shared redirect helper changes it. Native Android builds and real provider login have not yet been verified here.
