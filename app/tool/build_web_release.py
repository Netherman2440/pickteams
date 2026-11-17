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

from contextlib import contextmanager

from release_contract import ACCEPTED_SOURCE, restore_analysis, verify_source_history

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


def parse_control(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate JSON field')
            result[key] = value
        return result

    def invalid_constant(value):
        raise ValueError('non-JSON constant')

    value = json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid_constant)
    if not isinstance(value, dict):
        raise ValueError('not an object')
    return value


def same_json(left, right):
    # Unlike Python equality, JSON equality must distinguish bool from number.
    return json.dumps(left, sort_keys=True, allow_nan=False) == json.dumps(right, sort_keys=True, allow_nan=False)


@contextmanager
def source_directory(root, parts):
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=directory)
            os.close(directory)
            directory = child
        yield directory
    finally:
        os.close(directory)


@contextmanager
def source_file(root, parts):
    """Open a regular source file without following any path component's links."""
    with source_directory(root, parts[:-1]) as directory:
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                     dir_fd=directory)
        try:
            assert stat.S_ISREG(os.fstat(fd).st_mode), 'Nonregular source file'
            yield fd
        finally:
            os.close(fd)


def read_web_control(root, parts):
    with source_file(root, parts) as fd:
        info = os.fstat(fd)
        # Git records the executable bit, not umask-dependent group write bits.
        assert not info.st_mode & 0o7113, 'Unsafe web control mode'
        assert info.st_size <= 65536, 'Oversize web control'
        raw = os.read(fd, 65537)
        assert len(raw) <= 65536, 'Oversize web control'
        return raw


def checked_web_controls(root, env):
    """Validate the observed app-root projection, not arbitrary provider settings.

    IDs and system environment are consistency context, NOT authentication. The
    trust boundary is immutable Git source plus an exact, nonexecuting schema.
    Never accept commands, routing or environment from metadata by path alone.
    """
    app = parse_control(committed_web_config(root, 'app/vercel.json'))
    projected = parse_control(read_web_control(root, ('vercel.json',)))
    assert same_json(projected, app), 'Web root projection differs from immutable app config'
    with source_directory(root, ('.vercel',)) as directory:
        assert set(os.listdir(directory)) == {'project.json'}, 'Unknown web control files'
    metadata = parse_control(read_web_control(root, ('.vercel', 'project.json')))
    required = {'projectId', 'orgId', 'settings'}
    assert required <= metadata.keys() <= required | {'projectName'}, 'Unknown or missing project fields'
    assert env.get('VERCEL') == '1' and env.get('VERCEL_ENV') in ('preview', 'production'), 'Unsafe web provider context'
    for key, variable, pattern in [('projectId', 'VERCEL_PROJECT_ID', r'[A-Za-z0-9_-]{1,160}'),
                                   ('orgId', 'VERCEL_ORG_ID', r'[A-Za-z0-9_-]{1,160}'),
                                   ('projectName', 'VERCEL_PROJECT_NAME', r'[a-z0-9][a-z0-9._-]{0,99}')]:
        if key == 'projectName' and key not in metadata:
            continue  # CLI 65.15 omits this even when the system env has a name.
        value = metadata[key]
        assert isinstance(value, str) and re.fullmatch(pattern, value), 'Invalid project identity'
        assert value == env.get(variable), 'Project identity context mismatch'
    settings = metadata['settings']
    fields = {'createdAt', 'framework', 'devCommand', 'installCommand', 'buildCommand',
              'outputDirectory', 'rootDirectory', 'nodeVersion'}
    assert isinstance(settings, dict) and set(settings) == fields, 'Unknown or missing project settings'
    assert settings['rootDirectory'] == 'app', 'Unexpected project selection'
    for key in ('framework', 'installCommand', 'buildCommand', 'outputDirectory'):
        assert key in app and same_json(settings[key], app[key]), 'Project control mismatch'
    # The only execution-control normalization: absent devCommand in immutable
    # source equals the observed CLI null default. Ignore must remain absent.
    assert 'devCommand' not in app and settings['devCommand'] is None, 'Unexpected dev command'
    assert 'ignoreCommand' not in app, 'Unexpected ignore command'
    # These fields are not commands. Bound their types and syntax, not guessed
    # private values. nodeVersion is CLI runtime metadata; it never selects our
    # checksum/revision-pinned Flutter SDK or Python build command. CLI 65.15
    # preserves project.nodeVersion in settings and supports null (default).
    # This scalar type union does not normalize any command or source config.
    assert type(settings['createdAt']) is int and 0 <= settings['createdAt'] <= 9007199254740991, 'Invalid creation timestamp'
    assert settings['nodeVersion'] is None or (
        isinstance(settings['nodeVersion'], str) and re.fullmatch(r'[1-9][0-9]?\.x', settings['nodeVersion'])
    ), 'Invalid node metadata'


def verify_web_source(root, env):
    """Full source admission plus one checked, unstaged web materialization."""
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root)

    head = git('rev-parse', 'HEAD').decode().strip()
    assert re.fullmatch(r'[a-f0-9]{40}', head), 'Invalid source SHA'
    if b'origin' in git('remote').splitlines():
        assert git('remote', 'get-url', 'origin').strip() in (
            b'https://github.com/Netherman2440/pickteams',
            b'https://github.com/Netherman2440/pickteams.git',
        ), 'Unexpected source origin'
    else:
        # Hosted Vercel Git checkouts can omit remotes. Admit only the exact
        # provider-supplied repository identity and checkout SHA. The pinned
        # history, index, physical source and web-control checks below still
        # apply. Never create an origin or accept an existing wrong origin.
        expected = {
            'VERCEL': '1',
            'VERCEL_GIT_PROVIDER': 'github',
            'VERCEL_GIT_REPO_OWNER': 'Netherman2440',
            'VERCEL_GIT_REPO_SLUG': 'pickteams',
            'VERCEL_GIT_COMMIT_SHA': head,
        }
        assert env.get('VERCEL_ENV') in ('preview', 'production'), 'Missing hosted source context'
        assert all(env.get(key) == value for key, value in expected.items()), 'Unexpected hosted source identity'
    if 'VERCEL_GIT_COMMIT_SHA' in env:
        assert env['VERCEL_GIT_COMMIT_SHA'] == head, 'Build commit differs from checked out source'
    # Index equality is mandatory even for the checked paths. No caller can
    # supply exclusions, alternate baselines, or repaired metadata.
    assert git('write-tree').strip() == git('rev-parse', 'HEAD^{tree}').strip(), 'Staged source mutation'
    status = set(filter(None, git('status', '--porcelain=v1', '-z', '--untracked-files=all').split(b'\0')))
    materialized = status == {b' M vercel.json', b'?? .vercel/project.json'}
    assert not status or materialized, 'Source mutation outside checked web controls'
    # Check physical presence too: an ignored/symlinked metadata path must not
    # bypass admission just because Git status omits it.
    metadata_present = os.path.lexists(root / '.vercel')
    if materialized:
        assert env.get('VERCEL_GIT_COMMIT_SHA') == head, 'Missing web source context'
        checked_web_controls(root, env)
    elif metadata_present:
        # Root output is not used by the app-root CLI. Do not bless ignored
        # project settings (or a .vercel directory symlink) in a clean checkout.
        with source_directory(root, ('.vercel',)) as directory:
            assert not os.listdir(directory), 'Unchecked web metadata'
    if os.path.lexists(root / 'app/.vercel'):
        with source_directory(root, ('app', '.vercel')) as directory:
            assert set(os.listdir(directory)) <= {'output'}, 'Unchecked app web controls'

    # Git status alone misses assume-unchanged/skip-worktree and core.fileMode.
    # Compare all HEAD blobs and physical modes independently of Git's cache.
    accepted_modes = {entry.split(b'\t', 1)[1]: entry.split(b' ', 1)[0]
                      for entry in git('ls-tree', '-rz', ACCEPTED_SOURCE).split(b'\0') if entry}
    for entry in git('ls-tree', '-rz', 'HEAD').split(b'\0'):
        if not entry:
            continue
        header, path = entry.split(b'\t', 1)
        mode, kind, oid = header.split()
        assert kind == b'blob' and mode in (b'100644', b'100755'), 'Unsupported source entry'
        assert mode == accepted_modes.get(path, b'100644'), 'Changed source mode'
        parts = os.fsdecode(path).split('/')
        with source_file(root, parts) as fd:
            info = os.fstat(fd)
            assert not info.st_mode & 0o7000, 'Source special mode mutation'
            if mode == b'100755':
                # Git records owner execute; umask may remove group/other X.
                assert info.st_mode & stat.S_IXUSR, 'Source mode mutation'
            else:
                assert not info.st_mode & 0o111, 'Source mode mutation'
            if materialized and path == b'vercel.json':
                continue  # All schema/values were compared to immutable APP.
            digest = hashlib.sha1(b'blob ' + str(info.st_size).encode() + b'\0')
            while chunk := os.read(fd, 1024 * 1024):
                digest.update(chunk)
            assert digest.hexdigest().encode() == oid, 'Source byte mutation'
    assert verify_source_history(root) == head, 'Source HEAD changed'
    return head


def web_control_diagnostics(root):
    """Read-only fixed labels, never admission or complete provider equality."""
    parse = parse_control

    def read_control(parts):
        try:
            return read_web_control(root, parts)
        except AssertionError:
            return None

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
    """Recheck immutable source and web controls at every existing build stage."""
    print(f"Release source check: {stage}", flush=True)
    try:
        commit = verify_web_source(root, os.environ)
    except (AssertionError, OSError, ValueError, RecursionError, subprocess.CalledProcessError):
        print('Web control diagnostics: ' + json.dumps(web_control_diagnostics(root), sort_keys=True), flush=True)
        raise
    print(f"Release source verified: {stage} {commit}", flush=True)
    return commit


CANDIDATE_REPOSITORY = 'Netherman2440/pickteams'


def candidate_context(root, env):
    """Bind a GitHub PR merge checkout, never production acceptance.

    Trust comes from the reviewed GitHub workflow/runner context, not IDs alone.
    Local synthetic contexts are useful tests, not hosted authentication proof.
    """
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL)

    expected = {'GITHUB_ACTIONS': 'true', 'GITHUB_EVENT_NAME': 'pull_request',
                'GITHUB_REPOSITORY': CANDIDATE_REPOSITORY,
                'GITHUB_SERVER_URL': 'https://github.com'}
    assert all(env.get(key) == value for key, value in expected.items()), 'Untrusted candidate context'
    for key in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT'):
        assert isinstance(env.get(key), str) and re.fullmatch(r'[1-9][0-9]{0,19}', env[key]), 'Invalid candidate run context'
    event_path = Path(env.get('GITHUB_EVENT_PATH', ''))
    assert event_path.is_absolute() and '..' not in event_path.parts, 'Invalid candidate event path'
    with source_file(Path('/'), event_path.parts[1:]) as fd:
        info = os.fstat(fd)
        assert not info.st_mode & 0o7113 and info.st_size <= 1048576, 'Unsafe candidate event'
        raw = os.read(fd, 1048577)
        assert len(raw) <= 1048576, 'Oversize candidate event'
    event = parse_control(raw)

    def obj(value):
        assert isinstance(value, dict), 'Invalid candidate event structure'
        return value

    def sha(value):
        assert isinstance(value, str) and re.fullmatch(r'[a-f0-9]{40}', value), 'Invalid candidate SHA'
        return value

    assert obj(event.get('repository')).get('full_name') == CANDIDATE_REPOSITORY, 'Wrong candidate repository'
    pr = obj(event.get('pull_request'))
    number = event.get('number')
    assert (type(number) is int and type(pr.get('number')) is int and
            0 < number < 1000000000 and pr['number'] == number), 'Invalid candidate PR'
    ref = f'refs/pull/{number}/merge'
    assert env.get('GITHUB_REF') == ref, 'Candidate must use the actual PR merge checkout'
    assert env.get('GITHUB_WORKFLOW_REF') == f'{CANDIDATE_REPOSITORY}/.github/workflows/main.yml@{ref}', 'Wrong candidate workflow'
    head_info, base_info = obj(pr.get('head')), obj(pr.get('base'))
    for branch in (head_info, base_info):
        repository = obj(branch.get('repo'))
        assert repository.get('full_name') == CANDIDATE_REPOSITORY and repository.get('fork') is False, 'Unsafe candidate repository context'
    assert base_info.get('ref') == 'main', 'Candidate base must be main'
    head, base, checkout = sha(head_info.get('sha')), sha(base_info.get('sha')), sha(env.get('GITHUB_SHA'))
    if pr.get('merge_commit_sha') is not None:
        assert sha(pr['merge_commit_sha']) == checkout, 'Candidate event merge mismatch'
    assert git('remote', 'get-url', 'origin').strip() in (
        b'https://github.com/Netherman2440/pickteams',
        b'https://github.com/Netherman2440/pickteams.git',
    ), 'Wrong candidate source origin'
    assert git('rev-parse', '--is-shallow-repository').strip() == b'false', 'Candidate requires complete history'
    assert git('rev-parse', 'HEAD').decode().strip() == checkout, 'Candidate checkout SHA mismatch'
    assert git('rev-list', '--parents', '-n', '1', checkout).decode().split() == [checkout, base, head], 'Candidate merge parents mismatch'
    subprocess.run(['git', 'merge-base', '--is-ancestor', ACCEPTED_SOURCE, base], cwd=root,
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tree = git('rev-parse', checkout + '^{tree}').decode().strip()
    merged = git('merge-tree', '--write-tree', base, head).decode().splitlines()[0]
    assert tree == merged, 'Candidate merge tree mismatch'
    return {'repository': CANDIDATE_REPOSITORY, 'pullRequest': number,
            'headCommit': head, 'baseCommit': base, 'checkoutCommit': checkout,
            'headTree': git('rev-parse', head + '^{tree}').decode().strip(),
            'baseTree': git('rev-parse', base + '^{tree}').decode().strip(),
            'runtimeTree': tree, 'mergeParents': [base, head],
            'runId': env['GITHUB_RUN_ID'], 'runAttempt': env['GITHUB_RUN_ATTEMPT'],
            'workflowRef': env['GITHUB_WORKFLOW_REF']}


class CandidateSource:
    """Closed PR-only policy. No production pin, exclusion or authority switch."""
    def __init__(self, root, env):
        self.env = dict(env)
        self.identity = candidate_context(root, self.env)

    def verify_stage(self, root, stage):
        print(f'Candidate source check: {stage}', flush=True)
        assert candidate_context(root, self.env) == self.identity, 'Candidate context changed'

        def git(*args):
            return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL)

        assert git('write-tree').strip() == git('rev-parse', 'HEAD^{tree}').strip(), 'Staged candidate mutation'
        assert not git('status', '--porcelain=v1', '-z', '--untracked-files=all'), 'Dirty candidate source'
        for parts in (('.vercel',), ('app', '.vercel')):
            if os.path.lexists(root.joinpath(*parts)):
                with source_directory(root, parts) as directory:
                    assert not os.listdir(directory), 'Unexpected candidate provider controls'
        base_modes = {entry.split(b'\t', 1)[1]: entry.split(b' ', 1)[0]
                      for entry in git('ls-tree', '-rz', self.identity['baseCommit']).split(b'\0') if entry}
        for entry in git('ls-tree', '-rz', 'HEAD').split(b'\0'):
            if not entry:
                continue
            header, path = entry.split(b'\t', 1)
            mode, kind, oid = header.split()
            assert kind == b'blob' and mode in (b'100644', b'100755'), 'Unsafe candidate source entry'
            assert mode == base_modes.get(path, b'100644'), 'Candidate Git mode change'
            with source_file(root, os.fsdecode(path).split('/')) as fd:
                info = os.fstat(fd)
                assert not info.st_mode & 0o7000, 'Candidate special mode mutation'
                assert (bool(info.st_mode & stat.S_IXUSR) if mode == b'100755' else
                        not info.st_mode & 0o111), 'Candidate execute mode mutation'
                digest = hashlib.sha1(b'blob ' + str(info.st_size).encode() + b'\0')
                while chunk := os.read(fd, 1024 * 1024):
                    digest.update(chunk)
                assert digest.hexdigest().encode() == oid, 'Candidate byte mutation'
        assert candidate_context(root, self.env) == self.identity, 'Candidate source history changed'
        assert git('write-tree').strip() == git('rev-parse', 'HEAD^{tree}').strip(), 'Candidate index changed'
        assert not os.path.lexists(root / 'app/build/candidate-web'), 'Candidate evidence already exists'
        if stage != 'after-compiler-and-checked-analysis-restore':
            assert not os.path.lexists(root / 'app/build/web'), 'Stale candidate compiler output'
        return self.identity['checkoutCommit']


def _compile_web(app, env, flutter, check_source):
    """Shared compiler only; public entrypoints fix their policy and evidence."""
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
    if check_source(app.parent, "after-sdk-before-pub-get") != commit:
        raise ValueError("Build commit differs from checked out source")
    analysis = app / "analysis_options.yaml"
    original_analysis = analysis.read_bytes()
    run([flutter, "pub", "get", "--enforce-lockfile"], cwd=app, env=env)
    restore_analysis(analysis, original_analysis)
    check_source(app.parent, "after-pub-get-and-checked-analysis-restore")
    with tempfile.TemporaryDirectory(prefix="pickteams-web-config-") as temporary:
        client = Path(temporary) / "client-config.json"
        client.touch(mode=0o600)
        client.write_text(json.dumps(config))
        run([flutter, "build", "web", "--release", "--no-pub", "--target=lib/main.dart",
             "--no-web-resources-cdn", "--no-wasm-dry-run", "--dart-define-from-file=" + str(client)],
            cwd=app, env=env)
    restore_analysis(analysis, original_analysis)
    check_source(app.parent, "after-compiler-and-checked-analysis-restore")
    output = app / "build/web"
    if not (output / "index.html").is_file() or not (output / "main.dart.js").is_file():
        raise ValueError("Web build did not produce the real application entrypoint")
    return output, config, version, commit


def build(app, env, flutter):
    output, config, version, commit = _compile_web(app, env, flutter, verify_source_stage)
    manifest = {"schemaVersion": 1, "version": version, "commit": commit,
                "flutter": FLUTTER_VERSION, "flutterRevision": FLUTTER_REVISION,
                "files": {name: hashlib.sha256((output / name).read_bytes()).hexdigest()
                          for name in ("index.html", "main.dart.js")}}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built Pickteams {version} from {commit}")
    return manifest


def build_candidate(app, env, flutter):
    """Compile an unaccepted PR tree. This entrypoint cannot emit release.json."""
    source = CandidateSource(app.parent, env)
    output, config, version, commit = _compile_web(app, env, flutter, source.verify_stage)
    raw_config = json.dumps(config).encode()
    files = {}
    for directory, directories, names in os.walk(output, followlinks=False):
        assert all(not (Path(directory) / name).is_symlink() for name in directories), 'Linked candidate output directory'
        for name in names:
            path = Path(directory) / name
            relative = path.relative_to(output).as_posix()
            assert not any(ord(char) < 32 or char == '\\' for char in relative), 'Unsafe candidate output path'
            assert name.lower() not in ('release.json', 'client-config.json') and not name.lower().startswith('.env'), 'Private or release output in candidate'
            assert not name.lower().endswith(('.jks', '.pem', '.dart')), 'Unexpected candidate source/key output'
            with source_file(output, relative.split('/')) as fd:
                assert not os.fstat(fd).st_mode & 0o7000, 'Special candidate output mode'
                chunks = []
                while chunk := os.read(fd, 1024 * 1024):
                    chunks.append(chunk)
                raw = b''.join(chunks)
            assert raw_config not in raw and base64.b64encode(raw_config) not in raw, 'Raw client configuration in candidate output'
            if path.suffix == '.json':
                try:
                    value = json.loads(raw)
                except (ValueError, UnicodeError):
                    value = None

                def raw_client(value):
                    if isinstance(value, dict):
                        return set(config) <= value.keys() or any(raw_client(child) for child in value.values())
                    return isinstance(value, list) and any(raw_client(child) for child in value)

                assert not raw_client(value), 'Raw client configuration object in candidate output'
            files['web/' + relative] = hashlib.sha256(raw).hexdigest()
    assert {'web/index.html', 'web/main.dart.js'} <= files.keys(), 'Missing runnable candidate entrypoint'
    manifest = {'schemaVersion': 1, 'kind': 'pickteams-unaccepted-web-candidate',
                'promotable': False, 'productionAccepted': False,
                'notice': 'UNACCEPTED CANDIDATE - NOT FOR PRODUCTION OR NATIVE PROMOTION',
                'source': source.identity, 'version': version, 'entrypoint': 'lib/main.dart',
                'flutter': FLUTTER_VERSION, 'flutterRevision': FLUTTER_REVISION,
                'configurationSha256': hashlib.sha256(raw_config).hexdigest(),
                'files': files,
                'payloadTreeSha256': hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
    # Hash every runnable payload file. A detached digest covers the manifest;
    # GitHub's artifact digest is the external envelope binding both receipts.
    container = app / 'build/candidate-web'
    container.mkdir()
    output.rename(container / 'web')
    raw_manifest = (json.dumps(manifest, sort_keys=True, indent=2) + '\n').encode()
    (container / 'candidate.json').write_bytes(raw_manifest)
    (container / 'candidate.json.sha256').write_text(hashlib.sha256(raw_manifest).hexdigest() + '  candidate.json\n')
    assert commit == source.identity['checkoutCommit'], 'Candidate provenance mismatch'
    print(f'Built NONPROMOTABLE candidate {commit} from PR {source.identity["pullRequest"]}')
    return manifest


def candidate_main():
    """GitHub PR-only CLI, distinct from the unchanged production main()."""
    env = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    client_config(env)
    CandidateSource(APP.parent, env).verify_stage(APP.parent, 'before-sdk')
    flutter = install_flutter(env)
    env['PATH'] = str(flutter.parent) + os.pathsep + env.get('PATH', '')
    build_candidate(APP, env, flutter)


def main():
    env = dict(os.environ, CI="true", FLUTTER_SUPPRESS_ANALYTICS="true")
    client_config(env)  # Fail before downloading the SDK when configuration is missing.
    verify_source_stage(APP.parent, "before-sdk")
    flutter = install_flutter(env)
    env["PATH"] = str(flutter.parent) + os.pathsep + env.get("PATH", "")
    build(APP, env, flutter)


if __name__ == "__main__":
    main()
