"""Pinned Vercel/CI build of the real web app; never print client configuration."""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
from urllib.parse import urlparse
from urllib.request import urlopen

FLUTTER_VERSION = "3.47.9"
FLUTTER_REVISION = "c197ca5199e9ee5661e865596c9c07294dfab51c"
RELEASES = "https://storage.googleapis.com/flutter_infra_release/releases/"
APP = Path(__file__).resolve().parents[1]


def run(command, *, cwd, env):
    subprocess.run([str(arg) for arg in command], cwd=cwd, env=env, check=True)


def client_config(env):
    config = {name: env.get(name, "").strip()
              for name in ("SUPABASE_URL", "SUPABASE_ANON_KEY")}
    missing = [name for name, value in config.items() if not value]
    if missing:
        raise ValueError("Missing build environment variables: " + ", ".join(missing))
    url = urlparse(config["SUPABASE_URL"])
    if url.scheme != "https" or not url.hostname or url.username or url.password:
        raise ValueError("SUPABASE_URL must be an HTTPS endpoint without credentials")
    key = config["SUPABASE_ANON_KEY"]
    if key.startswith("sb_publishable_") and len(key) > len("sb_publishable_"):
        return config
    try:
        parts = key.split(".")
        assert len(parts) == 3
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
        assert payload.get("role") == "anon"
    except (ValueError, AssertionError, TypeError, AttributeError):
        raise ValueError("SUPABASE_ANON_KEY must be a publishable key or anon JWT, never a server key") from None
    return config


def verify_flutter(root, env):
    result = subprocess.run([str(root / "bin/flutter"), "--version", "--machine"],
                            env=env, check=True, text=True, capture_output=True)
    info = json.loads(result.stdout)
    if (info.get("frameworkVersion"), info.get("frameworkRevision")) != (FLUTTER_VERSION, FLUTTER_REVISION):
        raise ValueError("Flutter SDK does not match the pinned version and framework revision")
    return root / "bin/flutter"


def install_flutter(env):
    """Use an explicit verified SDK, or a checksum-verified official archive."""
    if env.get("PICKTEAMS_FLUTTER_ROOT"):
        return verify_flutter(Path(env["PICKTEAMS_FLUTTER_ROOT"]), env)
    cache = Path.home() / ".cache/pickteams" / ("flutter-" + FLUTTER_REVISION)
    if not (cache / "bin/flutter").is_file():
        with urlopen(RELEASES + "releases_linux.json", timeout=60) as response:
            releases = json.load(response)["releases"]
        release = next((item for item in releases if item.get("hash") == FLUTTER_REVISION
                        and item.get("version") == FLUTTER_VERSION and item.get("channel") == "stable"), None)
        if not release or not re.fullmatch(r"[a-f0-9]{64}", release.get("sha256", "")):
            raise ValueError("Pinned SDK is absent from official release metadata")
        archive = release["archive"]
        if archive != f"stable/linux/flutter_linux_{FLUTTER_VERSION}-stable.tar.xz":
            raise ValueError("Unexpected SDK archive path")
        cache.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache.parent) as temporary:
            temporary = Path(temporary)
            package = temporary / "flutter.tar.xz"
            digest = hashlib.sha256()
            with urlopen(RELEASES + archive, timeout=120) as source, package.open("wb") as target:
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
                    target.write(chunk)
            if digest.hexdigest() != release["sha256"]:
                raise ValueError("Flutter archive checksum mismatch")
            with tarfile.open(package, "r:xz") as source:
                source.extractall(temporary, filter="data")
            verify_flutter(temporary / "flutter", env)
            (temporary / "flutter").rename(cache)
    return verify_flutter(cache, env)


def build(app, env, flutter):
    config = client_config(env)
    version_match = re.search(r"^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$", (app / "pubspec.yaml").read_text(), re.M)
    if not version_match:
        raise ValueError("pubspec.yaml must declare a release version and build number")
    version = version_match.group(1)
    commit = env.get("VERCEL_GIT_COMMIT_SHA", "").strip()
    if not commit:
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=app, text=True).strip()
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("A full Git commit SHA is required for release provenance")
    run([flutter, "pub", "get", "--enforce-lockfile"], cwd=app, env=env)
    with tempfile.TemporaryDirectory(prefix="pickteams-web-config-") as temporary:
        client = Path(temporary) / "client-config.json"
        client.touch(mode=0o600)
        client.write_text(json.dumps(config))
        run([flutter, "build", "web", "--release", "--no-pub", "--target=lib/main.dart",
             "--no-web-resources-cdn", "--no-wasm-dry-run", "--dart-define-from-file=" + str(client)],
            cwd=app, env=env)
    output = app / "build/web"
    if not (output / "index.html").is_file() or not (output / "main.dart.js").is_file():
        raise ValueError("Web build did not produce the real application entrypoint")
    manifest = {"schemaVersion": 1, "version": version, "commit": commit,
                "flutter": FLUTTER_VERSION, "flutterRevision": FLUTTER_REVISION,
                "files": {name: hashlib.sha256((output / name).read_bytes()).hexdigest()
                          for name in ("index.html", "main.dart.js")}}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built Pickteams {version} from {commit}")
    return manifest


def main():
    env = dict(os.environ, CI="true", FLUTTER_SUPPRESS_ANALYTICS="true")
    client_config(env)  # Fail before downloading the SDK when configuration is missing.
    flutter = install_flutter(env)
    env["PATH"] = str(flutter.parent) + os.pathsep + env.get("PATH", "")
    build(APP, env, flutter)


if __name__ == "__main__":
    main()
