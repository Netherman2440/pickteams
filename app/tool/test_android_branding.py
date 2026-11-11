"""Positive and negative controls for the native branding contract."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from check_android_branding import check_apk, check_badging, check_source

APP = Path(__file__).resolve().parents[1]
BADGING = """package: name='com.example.app' versionCode='1' versionName='1.0'
application-label:'Pickteams'
application-label-pl:'Pickteams'
launchable-activity: name='com.example.app.MainActivity' label='Pickteams' icon='res/icon.png'
"""


class AndroidBrandingTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name)
        self.src = self.app / "android/app/src"
        shutil.copytree(APP / "android/app/src", self.src)
        shutil.copy(APP / "android/app/build.gradle.kts", self.src.parent)

    def replace(self, path, before, after):
        source = path.read_text()
        self.assertIn(before, source)
        path.write_text(source.replace(before, after))

    def test_current_native_source(self):
        check_source(self.app)

    def test_rejects_original_application_label(self):
        self.replace(self.src / "main/AndroidManifest.xml", "@string/app_name", "app")
        with self.assertRaisesRegex(ValueError, "Application label"):
            check_source(self.app)

    def test_rejects_wrong_resource_value(self):
        self.replace(self.src / "main/res/values/strings.xml", "Pickteams", "app")
        with self.assertRaisesRegex(ValueError, "non-translatable Pickteams"):
            check_source(self.app)

    def test_rejects_translatable_brand(self):
        self.replace(self.src / "main/res/values/strings.xml", 'translatable="false"', '')
        with self.assertRaisesRegex(ValueError, "non-translatable Pickteams"):
            check_source(self.app)

    def test_rejects_launcher_label_override(self):
        self.replace(self.src / "main/AndroidManifest.xml", "<activity", '<activity android:label="app"')
        with self.assertRaisesRegex(ValueError, "Unexpected label"):
            check_source(self.app)

    def test_rejects_manifest_overlay(self):
        manifest = self.src / "release/AndroidManifest.xml"
        manifest.parent.mkdir()
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                            '<application android:label="app"/></manifest>')
        with self.assertRaisesRegex(ValueError, "Unexpected label"):
            check_source(self.app)

    def test_rejects_localized_or_build_type_override(self):
        for folder in ("main/res/values-pl", "release/res/values"):
            with self.subTest(folder=folder):
                resource = self.src / folder / "branding.xml"
                resource.parent.mkdir(parents=True)
                resource.write_text('<resources><string name="app_name">app</string></resources>')
                with self.assertRaisesRegex(ValueError, "Unexpected app_name override"):
                    check_source(self.app)
                resource.unlink()

    def test_rejects_changed_application_id(self):
        self.replace(self.src.parent / "build.gradle.kts", 'applicationId = "com.example.app"',
                     'applicationId = "com.example.other"')
        with self.assertRaisesRegex(ValueError, "applicationId"):
            check_source(self.app)

    def test_compiled_badging_positive(self):
        check_badging(BADGING)

    def test_compiled_badging_negative_controls(self):
        mutations = [
            BADGING.replace("com.example.app", "com.example.other"),
            BADGING.replace("application-label:'Pickteams'", "application-label:'app'"),
            BADGING.replace("application-label-pl:'Pickteams'", "application-label-pl:'app'"),
            BADGING.replace("label='Pickteams'", "label='app'"),
            BADGING.replace("label='Pickteams'", "label=''"),
            "\n".join(BADGING.splitlines()[1:]),
            "\n".join(BADGING.splitlines()[2:]),
            "\n".join(BADGING.splitlines()[:-1]),
            "",
        ]
        for output in mutations:
            with self.subTest(output=output), self.assertRaises(ValueError):
                check_badging(output)

    @patch("check_android_branding.subprocess.run")
    def test_apk_tool_invocation(self, run):
        run.return_value.stdout = BADGING
        check_apk(Path("final combined.apk"), "/sdk/build-tools/aapt2")
        run.assert_called_once_with(
            ["/sdk/build-tools/aapt2", "dump", "badging", "final combined.apk"],
            check=True, text=True, capture_output=True)

    @patch("check_android_branding.subprocess.run")
    def test_apk_tool_failure_is_not_a_pass(self, run):
        run.side_effect = subprocess.CalledProcessError(1, "aapt2")
        with self.assertRaises(subprocess.CalledProcessError):
            check_apk(Path("invalid.apk"), "aapt2")


if __name__ == "__main__":
    unittest.main()
