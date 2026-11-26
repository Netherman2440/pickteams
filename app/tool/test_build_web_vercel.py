"""Offline Vercel target tests. Synthetic provider env is not hosted proof."""
from contextlib import redirect_stdout
from email.message import Message
from io import BytesIO, StringIO
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import URLError
from urllib.parse import parse_qs, urlparse

import build_web_release as release
import build_web_vercel as vercel
import release_contract as contract
import test_build_web_release as fixtures


class VercelTargetTest(unittest.TestCase):
    # Reuse the existing full-history fixture and compiler probe, not a second
    # mock Git/status implementation or another Flutter build lane.
    git = fixtures.CandidatePolicyTest.git
    sha = fixtures.CandidatePolicyTest.sha
    put = fixtures.CandidatePolicyTest.put
    commit = fixtures.CandidatePolicyTest.commit
    reset_fixture = fixtures.CandidatePolicyTest.reset_fixture
    fake_compile = fixtures.CandidatePolicyTest.fake_compile

    def setUp(self):
        network = patch.object(vercel, 'build_opener')
        self.opener = network.start()
        self.addCleanup(network.stop)
        self.opener.return_value.open.side_effect = URLError('offline fixture')
        fixtures.CandidatePolicyTest.setUp(self)
        self.git('checkout', '-q', '--detach', self.head)
        self.checkout = self.head
        self.env.update(VERCEL='1', VERCEL_ENV='preview', VERCEL_TARGET_ENV='preview',
                        VERCEL_GIT_PROVIDER='github', VERCEL_GIT_REPO_OWNER='Netherman2440',
                        VERCEL_GIT_REPO_SLUG='pickteams', VERCEL_GIT_COMMIT_SHA=self.head,
                        VERCEL_GIT_COMMIT_REF='feature/synthetic', VERCEL_GIT_PULL_REQUEST_ID='81',
                        PICKTEAMS_PREVIEW_SUPABASE_URL=fixtures.config()['SUPABASE_URL'],
                        PICKTEAMS_PREVIEW_SUPABASE_ANON_KEY=fixtures.config()['SUPABASE_ANON_KEY'])

    def check(self, env=None, stage='before-sdk'):
        env = self.env if env is None else env
        with redirect_stdout(StringIO()):
            return vercel.VercelPreviewSource(self.root, env).verify_stage(self.root, stage)

    def build(self, env=None, extra=None):
        env = self.env if env is None else env
        with patch.dict(os.environ, env, clear=True), \
                patch.object(release, 'install_flutter', return_value=Path('/synthetic/sdk/flutter')), \
                patch.object(release, 'run', side_effect=self.fake_compile(extra)), \
                redirect_stdout(StringIO()):
            return vercel.build_vercel(self.root / 'app', env)

    def github_pull(self):
        repo = {'full_name': release.CANDIDATE_REPOSITORY, 'fork': False}
        return {'state': 'open', 'number': 82,
                'url': 'https://api.github.com/repos/Netherman2440/pickteams/pulls/82',
                'merged_at': None, 'closed_at': None,
                'head': {'ref': self.env['VERCEL_GIT_COMMIT_REF'], 'sha': self.head, 'repo': repo},
                'base': {'ref': 'main', 'sha': self.base, 'repo': dict(repo)}}

    def github_response(self, pulls=None, *, raw=None, status=200, headers=None, redirected=False):
        raw = json.dumps([self.github_pull()] if pulls is None else pulls).encode() if raw is None else raw

        def respond(request, timeout):
            self.assertEqual(timeout, 20)
            response = BytesIO(raw)
            response.status = status
            response.geturl = lambda: 'https://untrusted.invalid/' if redirected else request.full_url
            response.headers = Message()
            response.headers['Content-Type'] = 'application/json'
            for name, value in (headers or {}).items():
                response.headers.replace_header(name, value) if name in response.headers else response.headers.add_header(name, value)
            return response
        self.opener.return_value.open.side_effect = respond

    def test_missing_or_empty_provider_id_resolves_one_exact_open_pr_once(self):
        for absent in (True, False):
            self.reset_fixture()
            self.opener.reset_mock()
            self.github_response()
            env = dict(self.env)
            if absent:
                del env['VERCEL_GIT_PULL_REQUEST_ID']
            else:
                env['VERCEL_GIT_PULL_REQUEST_ID'] = ''
            manifest = self.build(env)
            identity = manifest['source']
            self.assertEqual(identity['pullRequest'], 82)
            self.assertEqual(identity['pullRequestAuthority'], 'github-open-pr')
            self.assertEqual(identity['baseCommit'], self.base)
            self.assertEqual(identity['checkoutCommit'], self.head)
            self.assertIs(manifest['productionAccepted'], False)
            self.assertIs(manifest['promotable'], False)
            self.assertFalse(list((self.root / 'app/build').rglob('release.json')))
            self.opener.return_value.open.assert_called_once()
            request = self.opener.return_value.open.call_args.args[0]
            parsed = urlparse(request.full_url)
            self.assertEqual((parsed.scheme, parsed.netloc, parsed.path),
                             ('https', 'api.github.com', '/repos/Netherman2440/pickteams/pulls'))
            self.assertEqual(parse_qs(parsed.query), {'state': ['open'], 'head': ['Netherman2440:feature/synthetic'],
                                                    'base': ['main'], 'per_page': ['2']})
            self.assertEqual(request.get_method(), 'GET')
            self.assertIsNone(request.get_header('Authorization'))
            self.assertIsInstance(self.opener.call_args.args[0], vercel._NoRedirect)
            self.assertEqual(env.get('VERCEL_GIT_PULL_REQUEST_ID', ''), '')

    def test_malformed_provider_id_never_falls_back_to_github(self):
        for value in ('unknown', '0', '82\\n', ' 82', '82 ', '-1', '1.0', None, True, 82):
            with self.subTest(value=value), patch.object(release, 'install_flutter') as sdk:
                with self.assertRaisesRegex(AssertionError, 'Malformed Vercel PR ID'):
                    vercel.build_vercel(self.root / 'app', dict(self.env, VERCEL_GIT_PULL_REQUEST_ID=value))
                sdk.assert_not_called()
                self.opener.assert_not_called()

    def test_unavailable_empty_ambiguous_and_invalid_pr_evidence_fail_closed(self):
        env = dict(self.env, VERCEL_GIT_PULL_REQUEST_ID='')
        for pulls in ([], [self.github_pull(), self.github_pull()], {}, [None]):
            self.github_response(pulls)
            with self.subTest(pulls_type=type(pulls).__name__), patch.object(release, 'install_flutter') as sdk:
                with self.assertRaises(AssertionError):
                    vercel.build_vercel(self.root / 'app', env)
                sdk.assert_not_called()
        for raw in (b'invalid', b'[{"state":"open","state":"closed"}]', b'[NaN]', b' ' * 1048577):
            self.github_response(raw=raw)
            with self.subTest(raw_size=len(raw)), self.assertRaises(AssertionError):
                self.check(env)
        for options in ({'status': 403}, {'status': 429}, {'status': 500}, {'redirected': True},
                        {'headers': {'Link': '<https://api.github.com/next>; rel="next"'}},
                        {'headers': {'Content-Type': 'text/html'}}):
            self.github_response(**options)
            with self.subTest(options=options), self.assertRaises(AssertionError):
                self.check(env)
        for error in (URLError('private response must not echo'), TimeoutError('private response must not echo')):
            self.opener.return_value.open.side_effect = error
            with self.assertRaisesRegex(AssertionError, '^GitHub PR evidence unavailable or invalid$'):
                self.check(env)
        self.assertIsNone(vercel._NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.invalid'))

    def test_github_evidence_requires_exact_head_repository_and_trusted_main_base(self):
        tree = self.git('rev-parse', 'HEAD^{tree}').decode().strip()
        unrelated = self.git('commit-tree', tree, input=b'unrelated fixture\\n').decode().strip()
        for side, key, value in (
            ('pr', 'state', 'closed'), ('pr', 'number', True), ('pr', 'number', 0),
            ('pr', 'url', 'https://api.github.com/repos/other/repo/pulls/82'),
            ('pr', 'merged_at', '2026-01-01'), ('pr', 'closed_at', '2026-01-01'),
            ('head', 'ref', 'other'), ('head', 'sha', self.base), ('head', 'repo', None),
            ('head', 'repo', {'full_name': release.CANDIDATE_REPOSITORY, 'fork': True}),
            ('base', 'repo', {'full_name': 'other/repo', 'fork': False}),
            ('base', 'repo', {'full_name': release.CANDIDATE_REPOSITORY, 'fork': True}),
            ('base', 'ref', 'other'), ('base', 'sha', 'invalid'), ('base', 'sha', 'a' * 40),
            ('base', 'sha', unrelated),
        ):
            pr = self.github_pull()
            target = pr if side == 'pr' else pr[side]
            target[key] = value
            self.github_response([pr])
            with self.subTest(side=side, key=key, value=value), self.assertRaises((AssertionError, subprocess.CalledProcessError)):
                self.check(dict(self.env, VERCEL_GIT_PULL_REQUEST_ID=''))

    def test_feature_head_passes_preview_but_never_frozen_release_or_native(self):
        for stage in ('before-sdk', 'after-sdk-before-pub-get',
                      'after-pub-get-and-checked-analysis-restore',
                      'after-compiler-and-checked-analysis-restore'):
            self.assertEqual(self.check(stage=stage), self.head)
        for strict in (contract.verify_source_history, contract.verify_source, release.verify_web_source):
            with self.assertRaisesRegex(AssertionError, 'Unapproved source differences'):
                strict(self.root, {}) if strict is release.verify_web_source else strict(self.root)
        self.assertIs(fixtures.native.verify_source, contract.verify_source)
        with self.assertRaisesRegex(AssertionError, 'Unapproved source differences'):
            fixtures.native.verify_source(self.root)

    def test_target_and_provider_metadata_fail_before_sdk_and_no_output(self):
        for key in ('VERCEL', 'VERCEL_ENV', 'VERCEL_TARGET_ENV', 'VERCEL_GIT_PROVIDER',
                    'VERCEL_GIT_REPO_OWNER', 'VERCEL_GIT_REPO_SLUG', 'VERCEL_GIT_COMMIT_SHA',
                    'VERCEL_GIT_COMMIT_REF', 'VERCEL_GIT_PULL_REQUEST_ID'):
            for value in (None, '', 'unknown'):
                env = dict(self.env)
                if value is None:
                    del env[key]
                else:
                    env[key] = 'bad branch' if key == 'VERCEL_GIT_COMMIT_REF' and value == 'unknown' else value
                with self.subTest(key=key, value=value), patch.object(release, 'install_flutter') as sdk, \
                        patch.object(release, 'run') as compiler:
                    with self.assertRaises((AssertionError, subprocess.CalledProcessError)):
                        vercel.build_vercel(self.root / 'app', env)
                    sdk.assert_not_called()
                    compiler.assert_not_called()
        for changes in ({'VERCEL_ENV': 'production'}, {'VERCEL_TARGET_ENV': 'production'},
                        {'VERCEL_GIT_COMMIT_SHA': self.base}, {'VERCEL_GIT_COMMIT_REF': 'main'},
                        {'VERCEL_GIT_PULL_REQUEST_ID': '0'}, {'VERCEL_GIT_PULL_REQUEST_ID': '81\n'},
                        {'VERCEL_GIT_COMMIT_REF': 'bad branch'}):
            with self.subTest(changes=changes), self.assertRaises((AssertionError, subprocess.CalledProcessError)):
                self.check(dict(self.env, **changes))
        self.assertFalse((self.root / 'app/build/vercel-web').exists())

    def test_preview_has_no_fallback_to_production_configuration(self):
        for key in ('PICKTEAMS_PREVIEW_SUPABASE_URL', 'PICKTEAMS_PREVIEW_SUPABASE_ANON_KEY'):
            env = dict(self.env)
            del env[key]
            with patch.object(release, 'install_flutter') as sdk:
                with self.assertRaisesRegex(ValueError, 'Missing build environment'):
                    vercel.build_vercel(self.root / 'app', env)
                sdk.assert_not_called()
        env = dict(self.env, SUPABASE_URL='production-must-not-be-used',
                   SUPABASE_ANON_KEY='production-must-not-be-used')
        self.assertEqual(release.client_config(vercel.preview_config(env)), release.client_config(self.env))

    def test_preview_emits_only_isolated_nonpromotable_output(self):
        manifest = self.build()
        output = self.root / 'app/build/vercel-web'
        self.assertEqual(manifest['source']['checkoutCommit'], self.head)
        self.assertEqual(manifest['source']['provider'], 'vercel')
        self.assertIs(manifest['promotable'], False)
        self.assertIs(manifest['productionAccepted'], False)
        self.assertEqual(json.loads((output / 'preview.json').read_bytes()), manifest)
        envelope = self.root / 'app/build/candidate-web'
        self.assertEqual(json.loads((envelope / 'candidate.json').read_bytes()), manifest)
        actual = {path.relative_to(envelope).as_posix(): release.hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in (envelope / 'web').rglob('*') if path.is_file()}
        self.assertEqual(actual, manifest['files'])
        self.assertTrue((output / 'main.dart.js').is_file())
        self.assertFalse(list((self.root / 'app/build').rglob('release.json')))
        self.assertFalse((self.root / 'app/build/web').exists())
        self.assertFalse(self.config_path.exists())
        with self.assertRaises(KeyError):
            contract.validate_metadata(manifest)
        with self.assertRaisesRegex(AssertionError, 'Stale Vercel output'):
            vercel.build_vercel(self.root / 'app', self.env)

    def test_preview_rejects_release_metadata_and_private_compiler_payload(self):
        for name, raw in (('release.json', '{}'),
                          ('main.dart.js', '-----BEGIN PRIVATE KEY-----'),
                          ('leak.json', json.dumps(release.client_config(self.env)))):
            self.reset_fixture()
            with self.subTest(name=name), self.assertRaises(AssertionError):
                self.build(extra=lambda: self.put('app/build/web/' + name, raw))
            self.assertFalse((self.root / 'app/build/vercel-web').exists())
            self.assertFalse(self.config_path.exists())

    def test_preview_keeps_controls_index_physical_bytes_and_modes(self):
        app = json.loads(self.git('show', 'HEAD:app/vercel.json'))
        self.env.update(VERCEL_PROJECT_ID='prj_SYNTHETIC', VERCEL_ORG_ID='team_SYNTHETIC')
        metadata = {'projectId': 'prj_SYNTHETIC', 'orgId': 'team_SYNTHETIC', 'settings': {
            'createdAt': 1, 'framework': app['framework'], 'installCommand': app['installCommand'],
            'buildCommand': app['buildCommand'], 'outputDirectory': app['outputDirectory'],
            'devCommand': None, 'rootDirectory': 'app', 'nodeVersion': None}}
        self.put('vercel.json', json.dumps(app))
        self.put('.vercel/project.json', json.dumps(metadata))
        self.assertEqual(self.check(), self.head)
        metadata['settings']['buildCommand'] = 'untrusted command'
        self.put('.vercel/project.json', json.dumps(metadata))
        with self.assertRaisesRegex(AssertionError, 'Project control mismatch'):
            self.check()
        self.reset_fixture()
        self.git('update-index', '--assume-unchanged', 'app/lib/main.dart')
        self.put('app/lib/main.dart', 'hidden mutation')
        with self.assertRaisesRegex(AssertionError, 'Source byte mutation'):
            self.check()
        self.git('update-index', '--no-assume-unchanged', 'app/lib/main.dart')
        self.reset_fixture()
        self.put('app/lib/main.dart', 'staged mutation')
        self.git('add', 'app/lib/main.dart')
        with self.assertRaisesRegex(AssertionError, 'Staged source mutation'):
            self.check()
        self.reset_fixture()
        self.git('config', 'core.fileMode', 'false')
        (self.root / 'app/lib/main.dart').chmod(0o755)
        with self.assertRaisesRegex(AssertionError, 'Source mode mutation'):
            self.check()

    def test_preview_keeps_wrong_origin_no_origin_and_full_history_guards(self):
        self.git('remote', 'set-url', 'origin', 'https://untrusted.invalid/repo')
        with self.assertRaisesRegex(AssertionError, 'Unexpected source origin'):
            self.check()
        self.git('remote', 'remove', 'origin')
        self.assertEqual(self.check(), self.head)
        self.put('.git/shallow', self.base + '\n')
        with self.assertRaisesRegex(AssertionError, 'Preview requires complete history'):
            self.check()

    def test_production_rejects_feature_before_sdk_but_builds_accepted_fixture(self):
        env = dict(self.env, VERCEL_ENV='production', VERCEL_TARGET_ENV='production',
                   VERCEL_GIT_COMMIT_REF='main', VERCEL_GIT_PULL_REQUEST_ID='')
        with patch.dict(os.environ, env, clear=True), patch.object(release, 'install_flutter') as sdk:
            with redirect_stdout(StringIO()), self.assertRaisesRegex(AssertionError, 'Unapproved source differences'):
                vercel.build_vercel(self.root / 'app', env)
            sdk.assert_not_called()
        self.git('checkout', '-q', '--detach', self.base)
        env['VERCEL_GIT_COMMIT_SHA'] = self.base
        manifest = self.build(env)
        output = self.root / 'app/build/vercel-web'
        self.assertEqual(manifest['commit'], self.base)
        self.assertEqual(json.loads((output / 'release.json').read_bytes()), manifest)
        self.assertFalse((output / 'preview.json').exists())
        self.opener.assert_not_called()

    def test_target_change_during_compile_cannot_publish(self):
        # Mutable caller env and physical HEAD cannot change the policy identity.
        for production in (False, True):
            self.reset_fixture()
            env = dict(self.env)
            if production:
                self.git('checkout', '-q', '--detach', self.base)
                env.update(VERCEL_ENV='production', VERCEL_TARGET_ENV='production',
                           VERCEL_GIT_COMMIT_REF='main', VERCEL_GIT_PULL_REQUEST_ID='',
                           VERCEL_GIT_COMMIT_SHA=self.base)
            with self.subTest(production=production), self.assertRaises(AssertionError):
                self.build(env, extra=lambda: self.git('checkout', '-q', '--detach', self.base if not production else self.head))
            self.assertFalse((self.root / 'app/build/vercel-web').exists())


class ActualFeatureHistoryTest(unittest.TestCase):
    def test_actual_issue80_history_rejects_release_and_admits_exact_preview(self):
        sha = '179df8dc5802c4cf55a14bd3dc9c4ac50273911d'
        # No network fetch or replacement synthetic history. CI may not have
        # this independent PR object; the local evidence run must not skip it.
        available = subprocess.run(['git', 'cat-file', '-e', sha + '^{commit}'], cwd=release.APP.parent,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if available.returncode:
            self.skipTest('Actual #80 object is not in this checkout; use recorded local evidence')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'source'
            subprocess.run(['git', 'clone', '-q', '--shared', '--no-checkout', str(release.APP.parent), str(root)], check=True)
            subprocess.run(['git', 'checkout', '-q', '--detach', sha], cwd=root, check=True)
            subprocess.run(['git', 'remote', 'set-url', 'origin', 'https://github.com/Netherman2440/pickteams'], cwd=root, check=True)
            with self.assertRaisesRegex(AssertionError, 'Unapproved source differences'):
                release.verify_web_source(root, {})
            env = {'VERCEL': '1', 'VERCEL_ENV': 'preview', 'VERCEL_TARGET_ENV': 'preview',
                   'VERCEL_GIT_PROVIDER': 'github', 'VERCEL_GIT_REPO_OWNER': 'Netherman2440',
                   'VERCEL_GIT_REPO_SLUG': 'pickteams', 'VERCEL_GIT_COMMIT_SHA': sha,
                   'VERCEL_GIT_COMMIT_REF': 'limen/issue-79-player-profile-stats', 'VERCEL_GIT_PULL_REQUEST_ID': '80'}
            for stage in ('before-sdk', 'after-sdk-before-pub-get',
                          'after-pub-get-and-checked-analysis-restore',
                          'after-compiler-and-checked-analysis-restore'):
                self.assertEqual(vercel.VercelPreviewSource(root, env).verify_stage(root, stage), sha)
            env.update(VERCEL_ENV='production', VERCEL_TARGET_ENV='production',
                       VERCEL_GIT_COMMIT_REF='main', VERCEL_GIT_PULL_REQUEST_ID='')
            with patch.dict(os.environ, env, clear=True), patch.object(release, 'install_flutter') as sdk:
                # Legitimate fixture client data. No production credentials.
                env.update(fixtures.config(), VERCEL_GIT_COMMIT_SHA=sha)
                with redirect_stdout(StringIO()), self.assertRaisesRegex(AssertionError, 'Unapproved source differences'):
                    vercel.build_vercel(root / 'app', env)
                sdk.assert_not_called()
