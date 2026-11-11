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
use temporary copies and synthetic badging output. They do not prove an APK.
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
`aapt2 dump badging` without building or changing the APK. It requires package
`com.example.app`, default and localized application labels `Pickteams`, and
launcher activity labels `Pickteams`. Missing labels and tool failures fail the
check. Archive the command output with the APK hash in the release evidence.

Compiled-label acceptance remains pending until this command runs on the final
combined APK. Device acceptance is separate: update the existing installation
with the same signing identity, confirm its data remain, and inspect the launcher
caption and Android Settings app-info name. Both must show `Pickteams`. Record
screenshots; static checks and badging output do not prove device display.
