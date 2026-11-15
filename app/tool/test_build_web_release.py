"""Offline regression tests for the production web build contract."""
import base64
from contextlib import redirect_stdout
from io import BytesIO, StringIO
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_web_release as release


def jwt(role):
    payload = base64.urlsafe_b64encode(json.dumps({"role": role}).encode()).decode().rstrip("=")
    return "test." + payload + ".signature"


def config():
    return {"SUPABASE_URL": "https://client.invalid", "SUPABASE_ANON_KEY": jwt("anon"),
            "VERCEL_GIT_COMMIT_SHA": "a" * 40, "PATH": "/usr/bin:/bin"}


class WebReleaseTest(unittest.TestCase):
    def test_public_client_keys_are_accepted(self):
        for key in (jwt("anon"), "sb_publishable_fixture"):
            with self.subTest(key_type=key.split(".")[0]):
                env = dict(config(), SUPABASE_ANON_KEY=key)
                self.assertEqual(release.client_config(env)["SUPABASE_ANON_KEY"], key)

    def test_missing_configuration_fails_before_sdk_install(self):
        with patch.dict(release.os.environ, {}, clear=True), patch.object(release, "install_flutter") as install:
            with self.assertRaisesRegex(ValueError, "SUPABASE_URL, SUPABASE_ANON_KEY"):
                release.main()
            install.assert_not_called()

    def test_private_keys_and_malformed_jwts_are_rejected_without_echo(self):
        for key in (jwt("service_role"), "sb_secret_fixture", "not-a-jwt", "test.!!!.sig", "test.bnVsbA.sig"):
            with self.subTest(key_type=key.split(".")[0]):
                with self.assertRaises(ValueError) as error:
                    release.client_config(dict(config(), SUPABASE_ANON_KEY=key))
                self.assertNotIn(key, str(error.exception))

    def test_invalid_client_urls_are_rejected_without_echo(self):
        for url in ("http://client.invalid", "https://user:password@client.invalid", "file:///tmp/config"):
            with self.subTest(scheme=url.split(":")[0]):
                with self.assertRaises(ValueError) as error:
                    release.client_config(dict(config(), SUPABASE_URL=url))
                self.assertNotIn(url, str(error.exception))

    def test_sdk_checks_both_version_and_full_revision(self):
        for version, revision, accepted in [(release.FLUTTER_VERSION, release.FLUTTER_REVISION, True),
                                             (release.FLUTTER_VERSION, "b" * 40, False),
                                             ("3.48.0", release.FLUTTER_REVISION, False)]:
            response = unittest.mock.Mock(stdout=json.dumps({"frameworkVersion": version, "frameworkRevision": revision}))
            with self.subTest(version=version, revision=revision), patch.object(release.subprocess, "run", return_value=response):
                if accepted:
                    self.assertEqual(release.verify_flutter(Path("/sdk"), {}), Path("/sdk/bin/flutter"))
                else:
                    with self.assertRaisesRegex(ValueError, "pinned"):
                        release.verify_flutter(Path("/sdk"), {})

    def test_corrupt_sdk_archive_is_rejected(self):
        metadata = {"releases": [{"hash": release.FLUTTER_REVISION, "version": release.FLUTTER_VERSION,
                                 "channel": "stable", "sha256": "0" * 64,
                                 "archive": f"stable/linux/flutter_linux_{release.FLUTTER_VERSION}-stable.tar.xz"}]}
        with tempfile.TemporaryDirectory() as home, patch.object(release.Path, "home", return_value=Path(home)), \
                patch.object(release, "urlopen", side_effect=[BytesIO(json.dumps(metadata).encode()), BytesIO(b"bad archive")]):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                release.install_flutter({})
            self.assertFalse((Path(home) / ".cache/pickteams" / ("flutter-" + release.FLUTTER_REVISION)).exists())

    def test_build_uses_real_entrypoint_locked_dependencies_and_private_temp_config(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            (app / "pubspec.yaml").write_text("version: 1.0.5+2026111501\n")
            calls = []
            config_paths = []

            def execute(command, *, cwd, env):
                calls.append(command)
                self.assertEqual(cwd, app)
                if "build" in command:
                    option = next(arg for arg in command if str(arg).startswith("--dart-define-from-file="))
                    path = Path(str(option).split("=", 1)[1])
                    config_paths.append(path)
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(json.loads(path.read_text()), release.client_config(env))
                    self.assertNotIn(str(app / "build/web"), str(path))
                    output = app / "build/web"
                    output.mkdir(parents=True)
                    (output / "index.html").write_text("app")
                    (output / "main.dart.js").write_text("app")

            output = StringIO()
            with patch.object(release, "run", side_effect=execute), redirect_stdout(output):
                manifest = release.build(app, config(), Path("/sdk/bin/flutter"))
            self.assertIn("--enforce-lockfile", calls[0])
            self.assertIn("--no-pub", calls[1])
            self.assertIn("--target=lib/main.dart", calls[1])
            self.assertNotIn("issue57_preview", str(calls))
            self.assertEqual(manifest["commit"], "a" * 40)
            self.assertEqual(manifest["version"], "1.0.5+2026111501")
            self.assertEqual(json.loads((app / "build/web/release.json").read_text()), manifest)
            self.assertTrue(all(not path.exists() for path in config_paths))
            self.assertNotIn(config()["SUPABASE_ANON_KEY"], output.getvalue())
            self.assertNotIn("client.invalid", json.dumps(manifest))

    def test_failed_build_cleans_up_temp_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            (app / "pubspec.yaml").write_text("version: 1.0.5+2026111501\n")
            paths = []

            def execute(command, **kwargs):
                if "build" in command:
                    paths.append(Path(next(arg for arg in command if str(arg).startswith("--dart-define-from-file=")).split("=", 1)[1]))
                    raise RuntimeError("compiler failed")

            with patch.object(release, "run", side_effect=execute), self.assertRaisesRegex(RuntimeError, "compiler failed"):
                release.build(app, config(), Path("/sdk/bin/flutter"))
            self.assertTrue(paths)
            self.assertTrue(all(not path.exists() for path in paths))
            self.assertFalse((app / "build/web/release.json").exists())

    def test_invalid_source_pin_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(release, "run") as execute:
            app = Path(temporary)
            (app / "pubspec.yaml").write_text("version: 1.0.5+2026111501\n")
            with self.assertRaisesRegex(ValueError, "full Git commit"):
                release.build(app, dict(config(), VERCEL_GIT_COMMIT_SHA="main"), Path("/sdk/bin/flutter"))
            execute.assert_not_called()

    def test_vercel_configs_support_repository_and_app_project_roots(self):
        for root in (release.APP.parent, release.APP):
            data = json.loads((root / "vercel.json").read_text())
            self.assertTrue((root / data["buildCommand"].split()[1]).is_file())
            self.assertEqual((root / data["outputDirectory"]).resolve(), release.APP / "build/web")
            self.assertEqual(data["installCommand"], "")
            self.assertIsNone(data["framework"])
            self.assertIn({"source": "/release.json", "headers": [{"key": "Cache-Control", "value": "no-store"}]}, data["headers"])


if __name__ == "__main__":
    unittest.main()
