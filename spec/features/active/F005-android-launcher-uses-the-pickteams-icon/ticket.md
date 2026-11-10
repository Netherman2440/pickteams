---
opened: 2026-11-10
---

# F005 · Android launcher uses the Pickteams icon

## Outcome

An installed Android build shows the existing Pickteams branding instead of the default Flutter launcher icon. Rebuilding the icon resources is reproducible and does not change the accepted in-app or web branding.

## Scope

- Generate Android launcher resources from the existing Pickteams icon assets.
- Support ordinary launcher icons and adaptive Android launcher masks without clipping the mark.
- Add a reproducible verification of the generated resources and their configuration.

## Out of scope

- New logo design, app-ID changes, release signing, and store publication.
- Authentication manifests, iOS branding, and web branding changes.

## Acceptance

- All Android density resources contain the Pickteams mark rather than the Flutter mark.
- Adaptive icons retain the complete mark under circular and rounded-square masks.
- The installed application continues to reference the generated launcher resources.
- Regenerating Android icons from the committed configuration leaves the tracked tree unchanged.
- Existing web assets remain unchanged.

## Notes

The repository already has `flutter_launcher_icons` and branded image assets, but the configuration enables only web generation. Preserve the existing Android application ID so an update can replace the installed test app. Do not edit AndroidManifest.xml; the Google sign-in worker owns it.
