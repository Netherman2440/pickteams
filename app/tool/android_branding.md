# Android display-name contract

The Android application uses `@string/app_name`, defined as non-translatable
`Pickteams` in `android/app/src/main/res/values/strings.xml`. The launcher activity
inherits this label. This changes neither the application ID nor signing, icons,
OAuth callbacks, native versions, Dart code or other platform runners.

Run from the repository root (Python standard library only):

```sh
python3 app/tool/check_android_branding.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s app/tool -p 'test_android_branding.py' -v
python3 app/tool/check_android_oauth.py
```

The source check rejects the old label, changed resource values, label overrides
in manifests and resource variants, and a changed application ID. The unit tests
use temporary copies, captured aapt2 metadata excerpts and mutated negative
controls. They do not prove an APK.
The OAuth contract remains separate and unchanged.

## Final combined APK proof

Do not build a separate APK for this change. After the coordinator builds the
combined release, run this command from the repository root on that exact APK:

```sh
python3 app/tool/check_android_branding.py \
  --apk app/build/app/outputs/flutter-apk/app-release.apk \
  --aapt "$HOME/.local/share/pickteams-android-release/sdk/build-tools/36.0.0/aapt2"
```

For another SDK location, pass its `aapt2` executable with `--aapt`. For a copied
release artifact, pass its exact path with `--apk`. The checker runs
`aapt2 dump badging` and `aapt2 dump xmltree APK --file AndroidManifest.xml`
without building or changing the APK. It requires package `pl.pickteams.app` and
all default and localized application labels to resolve to `Pickteams`.

An empty badging launcher label alone still fails. With compiled manifest
evidence, the checker matches the named launcher to a MAIN/LAUNCHER component
and checks its label. An absent activity label inherits the application label;
an absent alias label inherits its named target activity's label, then the
application label. Aliases must target a preceding activity; alias chains and
cycles are not supported and fail closed. Explicit blank/wrong labels, unknown
label references, missing/duplicate components, inconsistent identities and tool
failures fail. Explicit labels must be literal `Pickteams` or the same reference
as the already resolved application label. Other references fail closed even if
they might resolve to `Pickteams`; this checker is not a general resource resolver.
Intent-filter label overrides receive the same checks. `check_badging(output)`
without tree evidence retains its strict behavior.

Android's contract is in
[`ComponentInfo.loadUnsafeLabel`](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/content/pm/ComponentInfo.java):
component literal/resource, then application literal/resource, then component name.
[`PackageParser.parseActivityAlias`](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/core/java/android/content/pm/PackageParser.java)
copies the target's label before parsing alias overrides. See also the
[activity-alias contract](https://developer.android.com/guide/topics/manifest/activity-alias-element).
Thus aapt2's empty launchable-activity field is not itself a blank Android label.
Archive both command outputs with the APK hash and checker commit in the release
evidence. Keep the checker source pin separate from the APK build source pin.

Compiled-label acceptance remains pending until this command runs on the final
combined APK. Device acceptance is separate: update the existing installation
with the same signing identity, confirm its data remain, and inspect the launcher
caption and Android Settings app-info name. Both must show `Pickteams`. Record
screenshots; static checks and badging output do not prove device display.
