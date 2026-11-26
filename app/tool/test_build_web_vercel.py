"""Offline Vercel target tests. Synthetic provider env is not hosted proof."""
from contextlib import redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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
