PASS 8eaca148fa794f3f38e8df50a933a065cd945c6c

Source-only verdict for F010 against `f2ed2a1` and `spec/features/active/F010-android-identifies-the-app-as-pickteams/ticket.md`. No blocking findings.

- **UNVERIFIED:** Real APK application/launcher labels and packaged `com.example.app` remain pending. No `aapt2` command ran. Device launcher/app-info names, update signing compatibility and retained data remain manual acceptance. Integrate with `--keep-open`; do not close the ticket or ship on this review.
- **PROVEN — source and preservation:** `app/android/app/src/main/AndroidManifest.xml` changes only the application label to `@string/app_name`. The new `res/values/strings.xml` defines non-translatable `Pickteams`; the launcher activity inherits it. Independent byte comparison and exact five-file scope checks passed. Tracked package/signing configuration, launcher assets, OAuth callback, toolchain, Dart, other runners, AGENTS and vision remain unchanged.
- **PROVEN — checker controls:** `app/tool/check_android_branding.py` rejects the original base manifest (exit 1, expected). All 12 Python tests passed. Synthetic badging tests cover wrong/missing package, default/localized application labels, launcher labels, invocation arguments and tool failure. The implementation calls `aapt2 dump badging` without a shell and propagates failure. This verifies checker logic, not an actual APK. `app/tool/android_branding.md` correctly separates source, packaged and device proof.

Checks actually run:
- `git rev-parse HEAD`, `git status --porcelain`, `git diff --name-status f2ed2a1 HEAD`: expected candidate, clean tree and five-file scope before and after.
- `git diff --check f2ed2a1 HEAD`: exit 0.
- `python3 app/tool/check_android_branding.py`: exit 0; APK/device explicitly pending.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s app/tool -p test_android_branding.py -v`: 12 passed.
- `python3 app/tool/check_android_oauth.py`: exit 0; static contract only.
- Independent `run_checks.py` scope/manifest assertions and temporary original-label negative control: passed. The wrapper exited 0. No Flutter, Gradle, builds, dependency installs or device commands ran.

Exact output and executable check record: `/home/agents/dev/pickteams/.limen/proof/F010/review-1/checks.log` and `run_checks.py`. This review is saved verbatim beside them as `review.md`.
