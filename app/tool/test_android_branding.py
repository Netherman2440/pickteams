"""Positive and negative controls for the native branding contract."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import call, patch

from check_android_branding import check_apk, check_badging, check_source

APP = Path(__file__).resolve().parents[1]
BADGING = """package: name='pl.pickteams.app' versionCode='1' versionName='1.0'
application-label:'Pickteams'
application-label-pl:'Pickteams'
launchable-activity: name='pl.pickteams.app.MainActivity' label='Pickteams' icon='res/icon.png'
"""

# Relevant records captured from build-tools 36.0.0 on the fc616d7 APK.
# Unrelated attributes/components and localized application-label variants omitted.
# TREE is legacy aapt; AAPT2_TREE is the actual aapt2 format.
REAL_BADGING = """package: name='pl.pickteams.app' versionCode='2026111201' versionName='1.0.2'
application-label:'Pickteams'
application-label-pl:'Pickteams'
launchable-activity: name='pl.pickteams.app.MainActivity'  label='' icon=''
"""
TREE = '''N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=2)
    A: package="pl.pickteams.app" (Raw: "pl.pickteams.app")
    E: application (line=33)
      A: android:label(0x01010001)=@0x7f0d001c
      E: activity (line=39)
        A: android:name(0x01010003)="pl.pickteams.app.MainActivity" (Raw: "pl.pickteams.app.MainActivity")
        E: intent-filter (line=74)
          E: action (line=75)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
          E: category (line=77)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
'''
AAPT2_TREE = '''N: android=http://schemas.android.com/apk/res/android (line=2)
  E: manifest (line=2)
    A: package="pl.pickteams.app" (Raw: "pl.pickteams.app")
      E: application (line=33)
        A: http://schemas.android.com/apk/res/android:label(0x01010001)=@0x7f0d001c
          E: activity (line=39)
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="pl.pickteams.app.MainActivity" (Raw: "pl.pickteams.app.MainActivity")
              E: intent-filter (line=74)
                  E: action (line=75)
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
                  E: category (line=77)
                    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
'''


def aapt2_format(tree):
    """Apply the same mutations to both supported SDK tree formats."""
    lines = []
    for line in tree.splitlines():
        text = line.lstrip()
        indent = len(line) - len(text)
        if text.startswith('N: '):
            lines.append(text + ' (line=2)')
        else:
            indent = 2 * indent - (2 if text.startswith('E: ') else 4)
            lines.append(' ' * max(0, indent) + text.replace(
                'A: android:', 'A: http://schemas.android.com/apk/res/android:'))
    return '\n'.join(lines) + '\n'


ACTIVITY = '      E: activity (line=39)\n'
FILTER = '        E: intent-filter (line=74)\n'


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
        self.replace(self.src.parent / "build.gradle.kts", 'applicationId = "pl.pickteams.app"',
                     'applicationId = "pl.pickteams.other"')
        with self.assertRaisesRegex(ValueError, "applicationId"):
            check_source(self.app)

    def test_compiled_badging_positive(self):
        check_badging(BADGING)

    def test_compiled_badging_negative_controls(self):
        mutations = [
            BADGING.replace("pl.pickteams.app", "pl.pickteams.other"),
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
        run.side_effect = [subprocess.CompletedProcess([], 0, REAL_BADGING),
                           subprocess.CompletedProcess([], 0, AAPT2_TREE)]
        check_apk(Path("final combined.apk"), "/sdk/build-tools/aapt2")
        self.assertEqual(run.call_args_list, [
            call(["/sdk/build-tools/aapt2", "dump", "badging", "final combined.apk"],
                 check=True, text=True, capture_output=True),
            call(["/sdk/build-tools/aapt2", "dump", "xmltree", "final combined.apk",
                  "--file", "AndroidManifest.xml"],
                 check=True, text=True, capture_output=True),
        ])

    def test_compiled_inheritance_requires_tree(self):
        with self.assertRaises(ValueError):
            check_badging(REAL_BADGING)
        self.assertEqual(aapt2_format(TREE), AAPT2_TREE)
        check_badging(REAL_BADGING, AAPT2_TREE)
        check_badging(REAL_BADGING, TREE)
        for value in ('"Pickteams"', '@0x7f0d001c'):
            check_badging(REAL_BADGING, TREE.replace(FILTER,
                          '        A: android:label(0x01010001)=' + value + '\n' + FILTER))

    def test_compiled_tree_negative_controls(self):
        mutations = [
            '', TREE.replace('pl.pickteams.app', 'pl.pickteams.other'),
            TREE.replace('android.intent.category.LAUNCHER', 'android.intent.category.DEFAULT'),
            TREE.replace(ACTIVITY, '      E: service (line=39)\n'),
            TREE.replace('      A: android:label(0x01010001)=@0x7f0d001c\n', ''),
            TREE.replace('      A: android:label(0x01010001)=@0x7f0d001c',
                         '      A: android:label(0x01010001)=""'),
            TREE + TREE,
            TREE.replace(FILTER, '          E: intent-filter (line=74)\n'),
            TREE + 'bad record\n',
            TREE.replace('(Raw: "pl.pickteams.app")', '(Raw: "pl.pickteams.other")'),
            TREE.replace(FILTER, '        A: android:name(0x01010003)="Duplicate"\n' + FILTER),
            TREE + TREE[TREE.index(ACTIVITY):],
        ]
        for value in ('""', '"app"', '@0x7f0dffff', '(type 0x00)0x0', '?0x7f0d001c'):
            mutations.append(TREE.replace(FILTER,
                             '        A: android:label(0x01010001)=' + value + '\n' + FILTER))
            mutations.append(TREE.replace(FILTER, FILTER +
                             '          A: android:label(0x01010001)=' + value + '\n'))
        for tree in mutations:
            for evidence in (tree, aapt2_format(tree)):
                with self.subTest(tree=evidence), self.assertRaises(ValueError):
                    check_badging(REAL_BADGING, evidence)
        for badging in (REAL_BADGING.replace("label=''", "label='app'"),
                        REAL_BADGING.replace("application-label-pl:'Pickteams'", "application-label-pl:'app'"),
                        REAL_BADGING + REAL_BADGING.splitlines()[-1] + '\n'):
            with self.subTest(badging=badging), self.assertRaises(ValueError):
                check_badging(badging, TREE)

    def test_alias_inherits_from_named_target(self):
        target = ('      E: activity (line=34)\n'
                  '        A: android:name(0x01010003)=".Target"\n')
        alias = TREE.replace(ACTIVITY, target + '      E: activity-alias (line=39)\n'
                             '        A: android:targetActivity(0x01010202)=".Target"\n')
        check_badging(REAL_BADGING, alias)
        check_badging(REAL_BADGING, aapt2_format(alias))
        for value in ('"Pickteams"', '@0x7f0d001c'):
            check_badging(REAL_BADGING, alias.replace(target, target +
                          '        A: android:label(0x01010001)=' + value + '\n'))
        mutations = [alias.replace(target, ''), alias.replace('=".Target"', '=".MainActivity"'),
                     alias.replace(target, target.replace('E: activity ', 'E: activity-alias '))]
        for value in ('""', '"Wrong"', '@0x7f0dffff'):
            mutations.append(alias.replace(target, target +
                             '        A: android:label(0x01010001)=' + value + '\n'))
            mutations.append(alias.replace(FILTER,
                             '        A: android:label(0x01010001)=' + value + '\n' + FILTER))
        for tree in mutations:
            for evidence in (tree, aapt2_format(tree)):
                with self.subTest(tree=evidence), self.assertRaises(ValueError):
                    check_badging(REAL_BADGING, evidence)

    @patch("check_android_branding.subprocess.run")
    def test_xmltree_tool_failure_is_not_a_pass(self, run):
        run.side_effect = [subprocess.CompletedProcess([], 0, REAL_BADGING),
                           subprocess.CalledProcessError(1, "aapt2")]
        with self.assertRaises(subprocess.CalledProcessError):
            check_apk(Path("invalid.apk"), "aapt2")

    @patch("check_android_branding.subprocess.run")
    def test_apk_tool_failure_is_not_a_pass(self, run):
        run.side_effect = subprocess.CalledProcessError(1, "aapt2")
        with self.assertRaises(subprocess.CalledProcessError):
            check_apk(Path("invalid.apk"), "aapt2")


if __name__ == "__main__":
    unittest.main()
