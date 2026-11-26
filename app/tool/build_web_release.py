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


def _candidate_release_policy(git, base, head):
    """Read trust from the runner-bound base, never from candidate imports.

    A new descriptor pin is only a subordinate NONPROMOTABLE source identity.
    It must describe a metadata-only child of a runtime descended from base.
    This grants neither runtime approval nor production/native authority.
    """
    import ast

    path = 'app/tool/release_contract.py'

    def policy(commit):
        entry = git('ls-tree', commit, '--', path).split()
        assert entry[:2] == [b'100644', b'blob'], 'Unsafe candidate contract mode'
        raw = git('show', commit + ':' + path)
        assert len(raw) <= 65536, 'Oversize candidate contract'
        tree = ast.parse(raw)
        values = {}
        normalized = raw.decode()
        for name, pattern in (('ACCEPTED_SOURCE', r"'[a-f0-9]{40}'"),
                              ('VERSION', r"'[0-9]+\.[0-9]+\.[0-9]+'"),
                              ('VERSION_CODE', r'[1-9][0-9]{0,9}')):
            assignments = [node for node in tree.body if isinstance(node, ast.Assign)
                           and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
                           and node.targets[0].id == name]
            stores = [node for node in ast.walk(tree) if isinstance(node, ast.Name)
                      and isinstance(node.ctx, ast.Store) and node.id == name]
            assert len(assignments) == len(stores) == 1, 'Ambiguous candidate contract literal'
            values[name] = ast.literal_eval(assignments[0].value)
            normalized, count = re.subn('^' + name + ' = ' + pattern + '$',
                                        name + ' = <literal>', normalized, flags=re.M)
            assert count == 1, 'Nonliteral candidate contract'
        assert type(values['VERSION_CODE']) is int and values['VERSION_CODE'] <= 2100000000, 'Invalid candidate version code'
        return raw, normalized, values

    base_raw, base_shape, trusted = policy(base)
    head_raw, head_shape, candidate = policy(head)
    base_pubspec = git('show', base + ':app/pubspec.yaml').decode()
    assert re.findall(r'^version: (.+)$', base_pubspec, re.M) == [
        f"{trusted['VERSION']}+{trusted['VERSION_CODE']}"], 'Base contract version mismatch'
    runtime = candidate['ACCEPTED_SOURCE']
    if runtime != trusted['ACCEPTED_SOURCE']:
        assert head_shape == base_shape, 'Candidate changed trusted contract policy'
        git('merge-base', '--is-ancestor', base, runtime)
        git('merge-base', '--is-ancestor', runtime, head)
        assert git('show', runtime + ':' + path) == base_raw, 'Runtime changed trusted contract'
        assert git('show', runtime + ':app/pubspec.yaml').decode() == base_pubspec, 'Runtime changed release dependencies'
        changed = set(git('diff', '--name-only', runtime, head).decode().splitlines())
        assert changed == {'app/pubspec.yaml', path, 'app/tool/test_release_contract.py'}, 'Not a descriptor-only transition'
        assert git('diff', '--summary', runtime, head) == b'', 'Descriptor mode or type change'
        current = git('show', head + ':app/pubspec.yaml').decode()
        assert re.findall(r'^version: (.+)$', current, re.M) == [
            f"{candidate['VERSION']}+{candidate['VERSION_CODE']}"], 'Candidate descriptor version mismatch'
        assert re.sub(r'^version: .+$', 'version: <release>', current, flags=re.M) == re.sub(
            r'^version: .+$', 'version: <release>', base_pubspec, flags=re.M), 'Candidate changed release dependencies'
        assert tuple(map(int, candidate['VERSION'].split('.'))) > tuple(map(int, trusted['VERSION'].split('.'))), 'Candidate version must increase'
        assert candidate['VERSION_CODE'] > trusted['VERSION_CODE'], 'Candidate version code must increase'
    return trusted['ACCEPTED_SOURCE']


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
    # GitHub defines the runner merge SHA separately from PR-state test-merge
    # metadata. Keep that optional metadata typed, not authoritative. The exact
    # runner checkout, ordered parents and recomputed tree are required below.
    # Contract and limits: docs/operations/candidate-context.md.
    advisory_merge = pr.get('merge_commit_sha')
    if advisory_merge is not None:
        sha(advisory_merge)
    assert git('remote', 'get-url', 'origin').strip() in (
        b'https://github.com/Netherman2440/pickteams',
        b'https://github.com/Netherman2440/pickteams.git',
    ), 'Wrong candidate source origin'
    assert git('rev-parse', '--is-shallow-repository').strip() == b'false', 'Candidate requires complete history'
    assert git('rev-parse', 'HEAD').decode().strip() == checkout, 'Candidate checkout SHA mismatch'
    assert git('rev-list', '--parents', '-n', '1', checkout).decode().split() == [checkout, base, head], 'Candidate merge parents mismatch'
    trusted_source = _candidate_release_policy(git, base, head)
    subprocess.run(['git', 'merge-base', '--is-ancestor', trusted_source, base], cwd=root,
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


class _CandidateJsonError(AssertionError):
    """Structured candidate data is ambiguous, invalid or over budget.

    Deliberately not ValueError: the non-JSON/compiled-code fallback must never
    swallow duplicate members or other semantic JSON failures.
    """


def _candidate_json(data):
    """One lossless, bounded JSON profile for all candidate root formats.

    Syntax errors stay JSONDecodeError so the classifier can distinguish real
    non-JSON code/binary data. Semantic failures always propagate fail-closed.
    """
    import math

    try:
        size = len(data.encode('utf-8')) if isinstance(data, str) else len(data)
    except UnicodeError:
        raise _CandidateJsonError('Invalid candidate JSON Unicode') from None
    if size > 1048576:
        raise _CandidateJsonError('Candidate JSON size exceeded')

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise _CandidateJsonError('Duplicate candidate JSON member')
            result[key] = value
        return result

    def constant(value):
        raise _CandidateJsonError('Non-finite candidate JSON constant')

    def floating(value):
        result = float(value)
        if not math.isfinite(result):
            raise _CandidateJsonError('Non-finite candidate JSON number')
        return result

    try:
        value = json.loads(data, object_pairs_hook=pairs, parse_constant=constant,
                           parse_float=floating)
    except json.JSONDecodeError:
        raise
    except (ValueError, UnicodeError, RecursionError):
        raise _CandidateJsonError('Invalid or excessive candidate JSON') from None
    pending = [(value, 0)]
    nodes = 0
    while pending:
        item, depth = pending.pop()
        nodes += 1
        if nodes > 1024 or depth > 16:
            raise _CandidateJsonError('Candidate JSON structure budget exceeded')
        if isinstance(item, (dict, list)) and len(item) + nodes + len(pending) > 1024:
            raise _CandidateJsonError('Candidate JSON structure budget exceeded')
        strings = item.keys() if isinstance(item, dict) else (item,) if isinstance(item, str) else ()
        for text in strings:
            try:
                text.encode('utf-8')
            except UnicodeError:
                raise _CandidateJsonError('Invalid candidate JSON Unicode') from None
        children = item.values() if isinstance(item, dict) else item if isinstance(item, list) else ()
        pending.extend((child, depth + 1) for child in children)
    return value


def _candidate_public_payload(app):
    """Closed Flutter 3.47.9 dart2js payload, not a directory/suffix exemption.

    Generated names are finite. Other files must be public typed app/web copies
    or literal flutter assets/fonts under assets/ or fonts/, tracked in HEAD and
    byte-identical to that source. Unsupported YAML declarations fail closed.
    """
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=app.parent, stderr=subprocess.DEVNULL)

    revision = git('rev-parse', 'HEAD').decode().strip()
    assert re.fullmatch(r'[a-f0-9]{40}', revision), 'Invalid public-input snapshot'
    allowed = {name: (kind, None) for name, kind in {
        'index.html': 'html', 'main.dart.js': 'code', 'flutter.js': 'code',
        'flutter_bootstrap.js': 'code', 'flutter_service_worker.js': 'code',
        'version.json': 'version', '.last_build_id': 'build-id',
        'assets/AssetManifest.bin': 'asset-manifest', 'assets/AssetManifest.bin.json': 'asset-manifest-json',
        'assets/FontManifest.json': 'font-manifest', 'assets/NOTICES': 'notices',
        'assets/fonts/MaterialIcons-Regular.otf': 'font',
        'assets/fonts/fallback/Roboto-Regular.ttf': 'font',
        'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf': 'font',
        'assets/shaders/ink_sparkle.frag': 'shader',
        'assets/shaders/stretch_effect.frag': 'shader',
    }.items()}
    for stem in ('canvaskit', 'chromium/canvaskit', 'webparagraph/canvaskit',
                 'skwasm', 'skwasm_heavy', 'wimp'):
        for suffix, kind in (('.js', 'code'), ('.js.symbols', 'symbols'), ('.wasm', 'wasm')):
            allowed['canvaskit/' + stem + suffix] = (kind, None)

    def safe_path(value):
        assert value and not value.startswith('/') and len(value) <= 512, 'Invalid public source path'
        parts = value.rstrip('/').split('/')
        assert all(part and part not in ('.', '..') and not part.startswith('.') for part in parts), 'Unsafe public source path'
        assert not any(ord(char) < 32 or char in '\\:' for char in value), 'Unsafe public source path'
        return value

    def literal(value):
        value = value.strip()
        if value.startswith('"'):
            value = _candidate_json(value)
        elif value.startswith("'"):
            assert value.endswith("'"), 'Invalid public asset literal'
            value = value[1:-1].replace("''", "'")
        else:
            value = value.split(' #', 1)[0].strip()
            assert not any(char in value for char in '[]{}&*!|>'), 'Unsupported public asset declaration'
        assert isinstance(value, str), 'Public asset path must be literal text'
        return safe_path(value)

    raw_pubspec = git('show', revision + ':app/pubspec.yaml')
    assert len(raw_pubspec) <= 1048576, 'Public source declaration too large'
    pubspec = raw_pubspec.decode()
    assert '\t' not in pubspec, 'Unsupported pubspec indentation'
    declarations = []
    flutter = False
    flutter_seen = False
    sections = set()
    section = None
    for line in pubspec.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            flutter = line == 'flutter:'
            if flutter:
                assert not flutter_seen, 'Duplicate flutter declaration'
                flutter_seen = True
            section = None
            continue
        if not flutter:
            continue
        if indent == 2:
            section = line.strip()
            if section.split(':', 1)[0] in ('assets', 'fonts'):
                assert section in ('assets:', 'fonts:'), 'Unsupported public asset declaration'
                assert section not in sections, 'Duplicate public declaration'
                sections.add(section)
            continue
        if section == 'assets:':
            assert indent == 4 and line.strip().startswith('- '), 'Unsupported public asset declaration'
            declarations.append(literal(line.strip()[2:]))
        elif section == 'fonts:':
            match = re.fullmatch(r'\s+- asset: (.+)', line)
            if match:
                declarations.append(literal(match[1]))
            else:
                assert re.fullmatch(r'\s+(?:- family: .+|fonts:|weight: [0-9]+|style: (?:normal|italic))', line), 'Unsupported public font declaration'
    assert len(declarations) <= 256, 'Public declaration count exceeded'
    assert all(path.startswith(('assets/', 'fonts/')) for path in declarations), 'Public assets must use dedicated public roots'
    types = {'.png': 'png', '.jpg': 'jpeg', '.jpeg': 'jpeg', '.gif': 'gif', '.webp': 'webp',
             '.ico': 'ico', '.svg': 'svg', '.ttf': 'font', '.otf': 'font', '.woff': 'font',
             '.woff2': 'font', '.wasm': 'wasm', '.json': 'json', '.txt': 'text', '.csv': 'text',
             '.js': 'code', '.css': 'text', '.html': 'html'}
    source_hashes = set()
    for row in git('ls-tree', '-rz', revision).split(b'\0'):
        if not row:
            continue
        header, raw_path = row.split(b'\t', 1)
        mode, kind, oid = header.split()
        path = raw_path.decode()
        copied_web = path.startswith('app/web/')
        asset = path.startswith('app/') and any(
            path[4:].startswith(item) if item.endswith('/') else path[4:] == item
            for item in declarations)
        private_source = path.startswith(('app/lib/', 'app/tool/', '.github/', 'supabase/')) or path in (
            'app/pubspec.yaml', 'app/pubspec.lock', 'app/analysis_options.yaml', 'vercel.json', 'app/vercel.json')
        if not (copied_web or asset or private_source):
            continue
        assert kind == b'blob', 'Unsupported public/source entry'
        digest = hashlib.sha256(git('cat-file', 'blob', oid.decode())).hexdigest()
        if private_source:
            source_hashes.add(digest)
        if not (copied_web or asset):
            continue
        assert mode == b'100644', 'Executable public input'
        relative = safe_path(path[len('app/web/'):] if copied_web else 'assets/' + path[4:])
        public_kind = types.get(Path(relative).suffix.lower())
        assert public_kind, 'Unsupported public payload type'
        if copied_web and relative in ('index.html', 'flutter_bootstrap.js'):
            continue  # Flutter transforms these two explicit source templates.
        assert relative not in allowed, 'Public input collides with compiler output'
        allowed[relative] = (public_kind, digest)
        assert len(allowed) <= 2048, 'Public payload input count exceeded'
    return allowed, source_hashes, revision


def _candidate_private_content(raw, code=False):
    """Bounded data classifier; compiled public defines are not secret matches.

    Like native archive privacy, reject PEM/JKS/JCEKS/callback credentials by
    content. Decode only whole JSON/string/list/dict, ENV and whole base64 data,
    never arbitrary JS tokens, archives, encryption or unbounded nested blobs.
    """
    from build_native_candidate import CALLBACK_CREDENTIALS

    budget = [0, 0]
    fields = {b'SUPABASE_URL', b'SUPABASE_ANON_KEY'}

    def inspect(data, depth=0):
        assert depth <= 8, 'Candidate serialization depth exceeded'
        budget[0] += 1
        assert budget[0] <= 1024, 'Candidate serialization node limit exceeded'
        assert not re.search(rb'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY', data), 'Private key content'
        assert not data.startswith((b'\xfe\xed\xfe\xed', b'\xce\xce\xce\xce')), 'Keystore content'
        assert not CALLBACK_CREDENTIALS.search(data), 'Captured callback credentials'
        assert not re.search(rb'(?m)^\s*(?:storeFile|storePassword|keyPassword|keyAlias|keystore)\s*[:=]', data), 'Signing configuration content'
        if not code:
            assert not all(field in data for field in fields), 'Raw client configuration content'
        env_fields = set(re.findall(rb'(?m)^\s*(?:export\s+)?(SUPABASE_URL|SUPABASE_ANON_KEY)\s*=', data))
        assert env_fields != fields, 'Client environment dump'
        stripped = data.strip()
        base64_data = len(stripped) >= 16 and re.fullmatch(rb'[A-Za-z0-9+/_=\s-]+', stripped)
        sniff = stripped[3:].lstrip() if stripped.startswith(b'\xef\xbb\xbf') else stripped
        structured = sniff.startswith((b'{', b'[', b'"', b'\xff\xfe', b'\xfe\xff', b'{\0', b'\0{')) or sniff in (b'NaN', b'Infinity', b'-Infinity')
        if not (structured or base64_data):
            return
        assert len(data) <= 1048576, 'Candidate serialized data too large'
        budget[1] += len(data)
        assert budget[1] <= 4194304, 'Candidate decoded data budget exceeded'
        try:
            value = _candidate_json(data)
        except (json.JSONDecodeError, UnicodeError):
            directive = code and re.match(rb'^"(?:use strict|use asm)"\s*;', stripped)
            if structured and not directive:
                raise _CandidateJsonError('Invalid candidate structured data') from None
            value = None
        if value is not None:
            walk(value, depth + 1)
        elif base64_data:
            compact = re.sub(rb'\s+', b'', stripped).translate(bytes.maketrans(b'-_', b'+/'))
            try:
                decoded = base64.b64decode(compact + b'=' * (-len(compact) % 4), validate=True)
            except ValueError:
                return
            inspect(decoded, depth + 1)

    def walk(value, depth):
        assert depth <= 16, 'Candidate JSON depth exceeded'
        budget[0] += 1
        assert budget[0] <= 1024, 'Candidate serialization node limit exceeded'
        if isinstance(value, dict):
            assert not {field.decode() for field in fields} <= value.keys(), 'Raw client configuration object'
            assert not {'storePassword', 'keyPassword', 'keystore'} & value.keys(), 'Signing configuration object'
            for child in value.values():
                walk(child, depth + 1)
        elif isinstance(value, list):
            for child in value:
                walk(child, depth + 1)
        elif isinstance(value, str):
            inspect(value.encode(), depth + 1)

    inspect(raw)


def _candidate_asset_manifest(raw, asset_keys):
    """Bounded StandardMessageCodec subset used by Flutter's asset manifest.

    No extensions, binary blobs, archives or trailing data. Every string which
    may name a payload must point to the closed authorized public asset set.
    """
    import struct

    assert len(raw) <= 1048576, 'Asset manifest too large'
    position = 0
    nodes = 0

    def take(length):
        nonlocal position
        assert 0 <= length <= 1048576 and position + length <= len(raw), 'Truncated asset manifest'
        result = raw[position:position + length]
        position += length
        return result

    def number(length):
        return int.from_bytes(take(length), 'little')

    def read(depth=0):
        nonlocal nodes
        nodes += 1
        assert nodes <= 32768 and depth <= 16, 'Asset manifest structure limit'
        tag = number(1)
        if tag in (3, 4):
            return int.from_bytes(take(4 if tag == 3 else 8), 'little', signed=True)
        if tag == 6:
            assert not any(take((-position) % 8)), 'Invalid asset float alignment'
            return struct.unpack('<d', take(8))[0]
        assert tag in (7, 12, 13), 'Unknown asset manifest type'
        size = number(1)
        length = number(2 if size == 254 else 4) if size >= 254 else size
        assert length <= 2048, 'Asset manifest collection/string limit'
        if tag == 7:
            return take(length).decode('utf-8')
        if tag == 12:
            return [read(depth + 1) for _ in range(length)]
        result = {}
        for _ in range(length):
            key = read(depth + 1)
            assert isinstance(key, str) and key not in result, 'Invalid asset manifest key'
            result[key] = read(depth + 1)
        return result

    value = read()
    assert position == len(raw) and isinstance(value, dict), 'Invalid asset manifest envelope'
    references = set()
    for key, variants in value.items():
        assert key in asset_keys and isinstance(variants, list) and variants, 'Unknown asset manifest reference'
        for variant in variants:
            assert isinstance(variant, dict) and {'asset'} <= variant.keys() <= {'asset', 'dpr'}, 'Invalid asset variant'
            assert isinstance(variant['asset'], str) and variant['asset'] in asset_keys, 'Unknown asset variant reference'
            references.add(variant['asset'])
            if 'dpr' in variant:
                assert type(variant['dpr']) in (int, float) and 0 < variant['dpr'] <= 64, 'Invalid asset pixel ratio'
    return references


def _candidate_public_type(raw, kind, asset_keys=()):
    """Positive types/schemas, including generated metadata, not opaque slots."""
    if kind == 'asset-manifest':
        return raw, _candidate_asset_manifest(raw, asset_keys)
    json_kinds = ('json', 'version', 'font-manifest', 'shader', 'asset-manifest-json')
    if kind in ('code', 'html', 'text', 'svg', 'symbols', 'notices', 'build-id') + json_kinds:
        text = raw.decode('utf-8-sig')
        assert '\0' not in text, 'Binary content in public text'
        if kind in json_kinds:
            assert len(raw) <= 1048576, 'Generated/public JSON too large'

            try:
                value = _candidate_json(text)
            except json.JSONDecodeError:
                raise _CandidateJsonError('Invalid public JSON') from None
            if kind == 'asset-manifest-json':
                assert isinstance(value, str), 'Invalid JSON asset manifest'
                try:
                    data = base64.b64decode(value, validate=True)
                except ValueError:
                    raise AssertionError('Invalid JSON asset encoding') from None
                return data, _candidate_asset_manifest(data, asset_keys)
            if kind == 'version':
                assert isinstance(value, dict) and set(value) == {'app_name', 'version', 'build_number', 'package_name'}, 'Invalid compiler version metadata'
                assert all(isinstance(item, str) for item in value.values()), 'Invalid version metadata type'
                assert re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', value['version']), 'Invalid compiler version'
                assert re.fullmatch(r'[0-9]{1,20}', value['build_number']), 'Invalid compiler build number'
                assert all(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]{0,127}', value[key]) for key in ('app_name', 'package_name')), 'Invalid compiler package name'
            elif kind == 'font-manifest':
                assert isinstance(value, list) and len(value) <= 256, 'Invalid font manifest'
                references = set()
                for family in value:
                    assert isinstance(family, dict) and set(family) == {'family', 'fonts'}, 'Invalid font family metadata'
                    assert isinstance(family['family'], str) and re.fullmatch(r'[\w ./-]{1,128}', family['family']), 'Invalid font family'
                    assert isinstance(family['fonts'], list) and len(family['fonts']) <= 256, 'Invalid font variants'
                    for font in family['fonts']:
                        assert isinstance(font, dict) and {'asset'} <= font.keys() <= {'asset', 'weight', 'style'}, 'Invalid font variant'
                        assert isinstance(font['asset'], str) and font['asset'] in asset_keys, 'Unknown font asset'
                        references.add(font['asset'])
                        assert 'weight' not in font or (type(font['weight']) is int and 1 <= font['weight'] <= 1000), 'Invalid font weight'
                        assert 'style' not in font or font['style'] in ('normal', 'italic'), 'Invalid font style'
                return None, references
            elif kind == 'shader':
                assert isinstance(value, dict) and set(value) == {'format_version', 'sksl'}, 'Invalid shader envelope'
                assert type(value['format_version']) is int and value['format_version'] == 2, 'Invalid shader version'
                shader = value['sksl']
                assert isinstance(shader, dict) and set(shader) == {'entrypoint', 'shader', 'stage', 'uniforms'}, 'Invalid shader metadata'
                assert isinstance(shader['entrypoint'], str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,127}', shader['entrypoint']), 'Invalid shader entrypoint'
                assert isinstance(shader['shader'], str) and shader['shader'].startswith('// This SkSL shader is autogenerated by spirv-cross.'), 'Invalid compiled shader'
                assert type(shader['stage']) is int and shader['stage'] == 1, 'Invalid shader stage'
                assert isinstance(shader['uniforms'], list) and len(shader['uniforms']) <= 256, 'Invalid shader uniforms'
                for uniform in shader['uniforms']:
                    assert isinstance(uniform, dict) and set(uniform) == {'array_elements', 'bit_width', 'columns', 'location', 'name', 'rows', 'type'}, 'Invalid shader uniform'
                    assert isinstance(uniform['name'], str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,127}', uniform['name']), 'Invalid uniform name'
                    assert all(type(item) is int and 0 <= item <= 65536 for key, item in uniform.items() if key != 'name'), 'Invalid uniform type'
        elif kind == 'symbols':
            assert all(re.fullmatch(r'[0-9]+:.{1,65536}', line) for line in text.splitlines()), 'Invalid SDK symbol metadata'
        elif kind == 'notices':
            assert '\n\n' in text and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]{0,127}', text.splitlines()[0]), 'Invalid compiler license metadata'
        elif kind == 'build-id':
            assert re.fullmatch(r'[a-f0-9-]{16,64}', text.strip()), 'Invalid compiler build identifier'
        elif kind == 'html':
            assert re.match(r'\s*(?:<!doctype html|<html)', text, re.I), 'Invalid public HTML'
        elif kind == 'svg':
            assert '<svg' in text and '<!ENTITY' not in text and '<!DOCTYPE' not in text, 'Invalid public SVG'
        elif kind == 'code':
            assert not re.match(r'\s*(?:#|def\s+\w+\s*\(|from\s+[\w.]+\s+import\s)', text), 'Source content masquerading as compiled JS'
    elif kind == 'font':
        assert raw.startswith((b'OTTO', b'\x00\x01\x00\x00', b'ttcf', b'wOFF', b'wOF2')), 'Invalid public font'
    elif kind == 'wasm':
        assert raw.startswith(b'\0asm\x01\0\0\0'), 'Invalid public WASM'
    elif kind == 'png':
        assert raw.startswith(b'\x89PNG\r\n\x1a\n'), 'Invalid public PNG'
    elif kind == 'jpeg':
        assert raw.startswith(b'\xff\xd8\xff'), 'Invalid public JPEG'
    elif kind == 'gif':
        assert raw.startswith((b'GIF87a', b'GIF89a')), 'Invalid public GIF'
    elif kind == 'webp':
        assert raw.startswith(b'RIFF') and raw[8:12] == b'WEBP', 'Invalid public WebP'
    elif kind == 'ico':
        assert raw.startswith(b'\0\0\x01\0'), 'Invalid public icon'
    else:
        raise AssertionError('Unknown public payload role')


def build_candidate(app, env, flutter):
    """Compile an unaccepted PR tree. This entrypoint cannot emit release.json."""
    source = CandidateSource(app.parent, env)
    output, config, version, commit = _compile_web(app, env, flutter, source.verify_stage)
    raw_config = json.dumps(config).encode()
    allowed, source_hashes, public_revision = _candidate_public_payload(app)
    assert public_revision == source.identity['checkoutCommit'], 'Public input source context changed'
    pubspec = subprocess.check_output(['git', 'show', public_revision + ':app/pubspec.yaml'],
                                      cwd=app.parent, stderr=subprocess.DEVNULL).decode()
    names = re.findall(r'^name:\s*([a-z_][a-z0-9_]*)\s*$', pubspec, re.M)
    versions = re.findall(r'^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$', pubspec, re.M)
    assert len(names) == 1 and versions == [version], 'Ambiguous candidate build metadata source'
    version_name, build_number = version.split('+')
    build_metadata = {'app_name': names[0], 'package_name': names[0],
                      'version': version_name, 'build_number': build_number}
    files = {}
    total = 0
    asset_keys = frozenset(path[7:] for path in allowed if path.startswith('assets/'))
    asset_manifests = {}
    references = set()
    for directory, directories, names in os.walk(output, followlinks=False):
        assert all(not (Path(directory) / name).is_symlink() for name in directories), 'Linked candidate output directory'
        for name in directories:
            relative_dir = (Path(directory) / name).relative_to(output).as_posix()
            assert any(path.startswith(relative_dir + '/') for path in allowed), 'Unexpected candidate payload directory'
        for name in names:
            path = Path(directory) / name
            relative = path.relative_to(output).as_posix()
            assert relative in allowed, 'Unexpected candidate payload file'
            assert len(files) < 2048, 'Candidate payload file limit exceeded'
            kind, source_digest = allowed[relative]
            with source_file(output, relative.split('/')) as fd:
                info = os.fstat(fd)
                assert not info.st_mode & 0o7000, 'Special candidate output mode'
                assert info.st_size <= 67108864, 'Candidate payload file too large'
                total += info.st_size
                assert total <= 268435456, 'Candidate payload total size exceeded'
                chunks = []
                length = 0
                while chunk := os.read(fd, min(1048576, 67108865 - length)):
                    length += len(chunk)
                    assert length <= 67108864, 'Candidate payload grew beyond limit'
                    chunks.append(chunk)
                assert length == info.st_size, 'Candidate payload changed while reading'
                raw = b''.join(chunks)
            digest = hashlib.sha256(raw).hexdigest()
            assert digest not in source_hashes, 'Renamed non-public source/control input'
            assert source_digest is None or digest == source_digest, 'Public source payload differs from immutable input'
            _candidate_private_content(raw, code=kind == 'code')
            metadata = _candidate_public_type(raw, kind, asset_keys)
            if kind == 'version':
                assert _candidate_json(raw) == build_metadata, 'Compiler metadata differs from immutable source/build'
            if metadata is not None:
                asset_manifest, refs = metadata
                if asset_manifest is not None:
                    asset_manifests[kind] = hashlib.sha256(asset_manifest).hexdigest()
                references.update('web/assets/' + ref for ref in refs)
            files['web/' + relative] = digest
    assert {'web/index.html', 'web/main.dart.js'} <= files.keys(), 'Missing runnable candidate entrypoint'
    assert len(set(asset_manifests.values())) <= 1, 'Asset manifest representations differ'
    assert references <= files.keys(), 'Public metadata references a missing payload'
    source.verify_stage(app.parent, 'after-compiler-and-checked-analysis-restore')
    manifest = {'schemaVersion': 1, 'kind': 'pickteams-unaccepted-web-candidate',
                'payloadPolicy': 'flutter-3.47.9-dart2js-public-v1',
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
