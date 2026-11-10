# Android launcher resource proof

The launcher uses the existing `assets/icons/app_icon.png` at five ordinary densities. Adaptive launchers use the existing transparent `app_icon_2.png` over `#2E2C29`. The 16% foreground inset keeps every nontransparent pixel inside Android's centered 66dp safe circle on the 108dp layer. No new logo or themed monochrome icon is introduced.

## Regenerate and check

Use the Flutter/Dart SDK and locked dependencies described in `player_lists_proof.md`. From `app/`:

```sh
flutter pub get --enforce-lockfile
# Inspect the known SDK migration before restoring it. Do not commit it.
git diff -- analysis_options.yaml
git restore analysis_options.yaml

dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml
dart run tool/android_icons_proof.dart /absolute/path/to/proof
```

The explicit `-f` is required. The default configuration in `pubspec.yaml` remains web-only. The Android configuration disables other platforms and retains the existing `@mipmap/ic_launcher` name. The generator rewrites the manifest with identical bytes when this name is already present; it must produce no manifest diff. Do not change AndroidManifest.xml or Info.plist to regenerate icons.

The proof decodes every generated PNG and checks its dimensions and exact resampled pixels against the existing brand sources. It resolves the manifest icon reference, adaptive foreground/inset and background color references. It checks all foreground pixels, including partially transparent edges, against the safe circle. The tool writes `resources.json`, ten individual mask previews, and `launcher-masks.png`. Open the sheet: all five density rows must show both people and the complete shield. The circle and squircle columns must have different outer shapes without clipping the mark.

The sheet uses real generated resources and the XML inset. It models a centered 72dp resting viewport and a fourth-power squircle; it is **not a device screenshot** or a model of every OEM launcher. The stronger 66dp safe-circle assertion protects the mark across standard adaptive masks and motion.

## Candidate evidence

Commit configuration, resources and proof tooling before final checks. Record `git rev-parse HEAD` and `git status --porcelain --untracked-files=no` before and after the following commands. Save outputs and previews under `/home/agents/dev/pickteams/.limen/proof/f005/<candidate-sha>/`.

```sh
dart format --output=none --set-exit-if-changed tool/android_icons_proof.dart
dart analyze tool/android_icons_proof.dart
dart run tool/android_icons_proof.dart /absolute/path/to/proof
# Must leave the complete tracked tree unchanged, including web and iOS.
dart run flutter_launcher_icons -f flutter_launcher_icons_android.yaml
git diff --exit-code HEAD
```

Also check the checker: substitute the old Flutter mdpi icon, substitute an incorrect-size PNG, and remove the inset from both the configuration and adaptive XML in turn. Each check must fail for the intended reason. Restore each file byte-for-byte before proceeding. Keep the failure logs with the candidate evidence.

Run `flutter analyze --no-pub` and `flutter test --coverage --reporter expanded` once on the committed candidate for the available Flutter lane. Inspect and restore any SDK-only `analysis_options.yaml` migration after these commands. Compare the source assets, web/iOS trees, manifests and Android Gradle application ID against the parent commit, not only against a second generator run.

## Native limits and installation

Static resource checks do not prove an APK build, installation, launcher cache refresh, or OEM rendering. The worker environment has no JDK or Android SDK. Do not install a native toolchain for this resource-only change or report a native build as passed.

A native-capable environment must rebuild the Android APK and install/update it with the same application ID (`com.example.app`). Hot reload and a web deployment do not replace launcher resources. If an installed launcher retains its cached icon after an update, restart the launcher or reinstall the test app (reinstallation can remove local app data). Check the installed icon on circle and rounded-square launchers before claiming device proof.
