---
opened: 2026-11-11
landed: 2026-11-11
---

# F009 · Android release builds use a compatible toolchain

## Outcome

The reviewed Pickteams mobile changes can produce an installable release APK with the Flutter toolchain already used for application validation. Native builds no longer stop at an incompatible Gradle/plugin version, and rebuilding does not silently modify tracked native configuration.

## Scope

- Align the Android build-tool versions as one compatible, pinned set.
- Preserve the current Kotlin Android plugin and DSL integration explicitly.
- Verify a real production APK without changing app behavior, identity, configuration values, or signing-key bytes.

## Out of scope

- AGP 9 migration, new app features, dependency upgrades, and release-key replacement.
- Physical installation, real Google sign-in, MDM changes, and store publication.

## Acceptance

- The supported release command completes without skipping dependency-version validation.
- A native build leaves the committed Android source unchanged.
- The APK retains com.example.app and the existing local signing certificate.
- Packaged permissions, launcher resources, callback intent and production AOT libraries pass offline checks.
- The Gradle distribution is pinned with its official checksum.

## Notes

The preserved failed build is `.limen/releases/8c0aa30/build.log`: Flutter 3.47.9 rejects Gradle 8.12 before compilation. Its installed version checker also requires AGP >=8.11.1, Kotlin >=2.2.20, and Java 17. Use Gradle 8.14.3, AGP 8.11.1 and Kotlin 2.2.20 rather than introducing an AGP 9 migration. Backend configuration remains outside Git; actual installation/signature compatibility with the unavailable previous APK remains a separate manual check.
