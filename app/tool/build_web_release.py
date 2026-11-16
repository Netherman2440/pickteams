"""Pinned Vercel/CI build of the real web app; never print client configuration."""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tarfile
import tempfile
from urllib.parse import urlparse
from urllib.request import urlopen

from release_contract import restore_analysis, verify_source

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


def committed_web_config(root, name):
    return subprocess.check_output(['git', 'show', 'HEAD:' + name], cwd=root,
                                   stderr=subprocess.DEVNULL)


def web_control_diagnostics(root):
    """Read-only evidence, never admission. Emit fixed labels, not provider values.

    CLI build reads project settings and the selected workPath config. A dirty
    root config is not a proven CLI transformation. Keep the source gate closed
    and distinguish exact repository projections from unknown content safely.
    """
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate JSON field')
            result[key] = value
        return result

    def parse(raw):
        value = json.loads(raw, object_pairs_hook=pairs)
        if not isinstance(value, dict):
            raise ValueError('not an object')
        return value

    def read_control(parts):
        # Never follow links, block on a FIFO, or read unbounded provider data.
        directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for part in parts[:-1]:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                dir_fd=directory)
                os.close(directory)
                directory = child
            fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                         dir_fd=directory)
            try:
                info = os.fstat(fd)
                if not stat.S_ISREG(info.st_mode) or info.st_size > 65536:
                    return None
                raw = os.read(fd, 65537)
                return raw if len(raw) <= 65536 else None
            finally:
                os.close(fd)
        finally:
            os.close(directory)

    baselines = {}

    def source_configs():
        if not baselines:
            loaded = {}
            for name, path in [('root', 'vercel.json'), ('app', 'app/vercel.json')]:
                raw = committed_web_config(root, path)
                loaded[name] = (raw, parse(raw))
            baselines.update(loaded)
        return baselines['root'][1], baselines['app'][1]

    # These are the six CLI pickOverrides controls, not a provider settings schema.
    controls = {'buildCommand': 'buildCommand', 'installCommand': 'installCommand',
                'outputDirectory': 'outputDirectory', 'framework': 'framework',
                'devCommand': 'devCommand', 'commandForIgnoringBuildStep': 'ignoreCommand'}

    def comparison(values, key, root_config, app_config, config_key=None):
        target = config_key or key
        present = key in values
        value = values.get(key)
        equals = lambda config: present == (target in config) and (not present or
                                (type(value) is type(config[target]) and value == config[target]))
        same_root, same_app = equals(root_config), equals(app_config)
        label = ('absent' if not present else 'null' if value is None else
                 'type-invalid' if not isinstance(value, str) else 'empty' if value == '' else
                 'equal-to-root-and-app' if same_root and same_app else
                 'equal-to-root' if same_root else 'equal-to-app' if same_app else 'other')
        return {'classification': label, 'equalsRoot': same_root, 'equalsApp': same_app}

    def complete_config(value):
        head, app = source_configs()
        # Canonical JSON comparison does not equate booleans and numbers.
        canonical = lambda data: json.dumps(data, sort_keys=True, allow_nan=False)
        return ('equal-to-root' if canonical(value) == canonical(head) else
                'equal-to-app' if canonical(value) == canonical(app) else 'different-json')

    report = {}
    for label, parts in [('rootConfig', ('vercel.json',)),
                         ('projectMetadata', ('.vercel', 'project.json'))]:
        item = {'classification': 'unsafe-or-missing'}
        report[label] = item
        try:
            raw = read_control(parts)
            if raw is None:
                continue
            item['classification'] = 'invalid'
            value = parse(raw)
            if label == 'rootConfig':
                head, app = source_configs()
                head_raw = baselines['root'][0]
                item['classification'] = ('head-bytes' if raw == head_raw else
                                          'head-json' if value == head else
                                          'app-json' if value == app else 'different-json')
                fields = ('$schema', 'framework', 'installCommand', 'buildCommand',
                          'outputDirectory', 'headers', 'rewrites', 'redirects',
                          'routes', 'ignoreCommand', 'builds', 'functions')
                item['differsFromHead'] = [key for key in fields
                                           if (key in value) != (key in head) or value.get(key) != head.get(key)]
                item['unknownFieldCount'] = len(set(value) - set(fields))
            else:
                item['classification'] = 'json-object'
                fields = ('projectId', 'orgId', 'projectName', 'settings')
                item['fields'] = [key for key in fields if key in value]
                item['unknownFieldCount'] = len(set(value) - set(fields))
                item['identifiers'] = {}
                for key, variable in [('projectId', 'VERCEL_PROJECT_ID'),
                                      ('orgId', 'VERCEL_ORG_ID'),
                                      ('projectName', 'VERCEL_PROJECT_NAME')]:
                    identifier = value.get(key)
                    item['identifiers'][key] = {
                        'present': key in value,
                        'environmentPresent': variable in os.environ,
                        'equalsEnvironment': isinstance(identifier, str) and bool(identifier) and
                                             variable in os.environ and identifier == os.environ[variable],
                    }
                settings = value.get('settings')
                item['settingsObject'] = isinstance(settings, dict)
                if isinstance(settings, dict):
                    fields = ('createdAt', 'framework', 'devCommand', 'installCommand',
                              'buildCommand', 'outputDirectory', 'rootDirectory',
                              'nodeVersion', 'analyticsId', 'commandForIgnoringBuildStep')
                    item['settingsFields'] = [key for key in fields if key in settings]
                    item['unknownSettingsFieldCount'] = len(set(settings) - set(fields))
                    directory = settings.get('rootDirectory')
                    item['rootDirectory'] = directory if directory in (None, '.', '', 'app') else 'other'
                    item['sourceComparisonAvailable'] = False
                    head, app = source_configs()
                    item['sourceComparisonAvailable'] = True
                    item['controls'] = {key: comparison(settings, key, head, app, config_key)
                                        for key, config_key in controls.items()}
                    item['controls']['rootDirectory'] = comparison(
                        settings, 'rootDirectory', {'rootDirectory': '.'}, {'rootDirectory': 'app'})
                    # This is explicitly repository-relative, not proof of the
                    # provider's invocation root or of any settings' legitimacy.
                    selection = ('root' if directory in (None, '', '.') else
                                 'app' if directory == 'app' else 'unknown')
                    item['repositoryRelativeSelection'] = selection
                    selected = {'classification': 'unsafe-or-missing'}
                    item['selectedConfig'] = selected
                    if selection != 'unknown':
                        selected_raw = read_control(('vercel.json',) if selection == 'root' else ('app', 'vercel.json'))
                        if selected_raw is not None:
                            selected['classification'] = 'invalid'
                            effective = parse(selected_raw)
                            # Mirror only the six known CLI defaults. Retain ALL
                            # selected JSON fields so routing/unknown edits differ.
                            for key, config_key in controls.items():
                                if config_key not in effective and key in settings:
                                    effective[config_key] = settings[key]
                            selected['comparisonScope'] = 'selected-json-with-six-cli-control-defaults'
                            selected['completeConfigComparison'] = complete_config(effective)
                            selected['classification'] = 'json-object'
                            item['effectiveControls'] = {config_key: comparison(effective, config_key, head, app)
                                                         for config_key in controls.values()}
        except (OSError, ValueError, RecursionError, subprocess.CalledProcessError):
            # Diagnostics must not replace the original source rejection.
            pass
    return report


def verify_source_stage(root, stage):
    """Name the gate and diagnose controls without accepting any dirty source."""
    print(f"Release source check: {stage}", flush=True)
    try:
        commit = verify_source(root)
    except AssertionError:
        print('Web control diagnostics: ' + json.dumps(web_control_diagnostics(root), sort_keys=True), flush=True)
        raise
    print(f"Release source verified: {stage} {commit}", flush=True)
    return commit


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
    if verify_source_stage(app.parent, "after-sdk-before-pub-get") != commit:
        raise ValueError("Build commit differs from checked out source")
    analysis = app / "analysis_options.yaml"
    original_analysis = analysis.read_bytes()
    run([flutter, "pub", "get", "--enforce-lockfile"], cwd=app, env=env)
    restore_analysis(analysis, original_analysis)
    verify_source_stage(app.parent, "after-pub-get-and-checked-analysis-restore")
    with tempfile.TemporaryDirectory(prefix="pickteams-web-config-") as temporary:
        client = Path(temporary) / "client-config.json"
        client.touch(mode=0o600)
        client.write_text(json.dumps(config))
        run([flutter, "build", "web", "--release", "--no-pub", "--target=lib/main.dart",
             "--no-web-resources-cdn", "--no-wasm-dry-run", "--dart-define-from-file=" + str(client)],
            cwd=app, env=env)
    restore_analysis(analysis, original_analysis)
    verify_source_stage(app.parent, "after-compiler-and-checked-analysis-restore")
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
    verify_source_stage(APP.parent, "before-sdk")
    flutter = install_flutter(env)
    env["PATH"] = str(flutter.parent) + os.pathsep + env.get("PATH", "")
    build(APP, env, flutter)


if __name__ == "__main__":
    main()
