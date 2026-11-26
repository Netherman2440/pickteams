"""Vercel-only target router. Previews never inherit release approval."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess

import build_web_release as release

APP = release.APP


def target_context(root, env):
    """System env is supplied by the hosted provider, not local authentication.

    Require provider provenance even when an origin exists. Missing/custom or
    contradictory target metadata must never select the preview policy.
    """
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()

    target = env.get('VERCEL_ENV')
    assert env.get('VERCEL') == '1', 'Missing Vercel provider context'
    assert target in ('preview', 'production'), 'Unknown Vercel target'
    assert env.get('VERCEL_TARGET_ENV') == target, 'Inconsistent Vercel target'
    expected = {'VERCEL_GIT_PROVIDER': 'github',
                'VERCEL_GIT_REPO_OWNER': 'Netherman2440',
                'VERCEL_GIT_REPO_SLUG': 'pickteams'}
    assert all(env.get(key) == value for key, value in expected.items()), 'Wrong Vercel repository'
    commit = env.get('VERCEL_GIT_COMMIT_SHA')
    assert isinstance(commit, str) and re.fullmatch(r'[a-f0-9]{40}', commit), 'Missing Vercel commit'
    assert git('rev-parse', 'HEAD') == commit, 'Vercel checkout SHA mismatch'
    ref = env.get('VERCEL_GIT_COMMIT_REF')
    assert isinstance(ref, str) and 0 < len(ref) <= 255, 'Missing Vercel branch'
    subprocess.run(['git', 'check-ref-format', '--branch', ref], cwd=root, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pr = env.get('VERCEL_GIT_PULL_REQUEST_ID', '')
    if target == 'production':
        assert ref == 'main' and pr == '', 'Production requires main without a PR'
        return {'target': target, 'checkoutCommit': commit}
    assert ref != 'main', 'Preview requires a feature branch'
    assert isinstance(pr, str) and re.fullmatch(r'[1-9][0-9]{0,8}', pr), 'Preview requires a PR'
    assert git('rev-parse', '--is-shallow-repository') == 'false', 'Preview requires complete history'
    subprocess.run(['git', 'merge-base', '--is-ancestor', release.ACCEPTED_SOURCE, commit],
                   cwd=root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {'target': target, 'provider': 'vercel', 'repository': release.CANDIDATE_REPOSITORY,
            'pullRequest': int(pr), 'headRef': ref, 'checkoutCommit': commit,
            'runtimeTree': git('rev-parse', 'HEAD^{tree}')}


class VercelPreviewSource:
    """PR head policy, separate from GitHub merge candidates and production."""
    def __init__(self, root, env):
        self.env = dict(env)
        self.identity = target_context(root, self.env)
        assert self.identity['target'] == 'preview', 'Not a Vercel preview'

    def verify_stage(self, root, stage):
        print(f'Preview source check: {stage}', flush=True)
        assert target_context(root, self.env) == self.identity, 'Preview context changed'
        commit = release.verify_web_worktree(root, self.env)
        assert commit == self.identity['checkoutCommit'], 'Preview source changed'
        assert not os.path.lexists(root / 'app/build/candidate-web'), 'Stale preview evidence'
        assert not os.path.lexists(root / 'app/build/vercel-web'), 'Stale Vercel output'
        if stage != 'after-compiler-and-checked-analysis-restore':
            assert not os.path.lexists(root / 'app/build/web'), 'Stale preview compiler output'
        assert target_context(root, self.env) == self.identity, 'Preview source history changed'
        return commit


def preview_config(env):
    """Only Preview-scoped inputs. Never fall back to production input names."""
    result = dict(env)
    for name in ('SUPABASE_URL', 'SUPABASE_ANON_KEY'):
        result[name] = env.get('PICKTEAMS_PREVIEW_' + name, '')
    release.client_config(result)
    return result


def build_vercel(app, env):
    identity = target_context(app.parent, env)
    destination = app / 'build/vercel-web'
    assert not os.path.lexists(destination), 'Stale Vercel output'
    if identity['target'] == 'preview':
        env = preview_config(env)
        source = VercelPreviewSource(app.parent, env)
        source.verify_stage(app.parent, 'before-sdk')
    else:
        release.client_config(env)
        release.verify_source_stage(app.parent, 'before-sdk')
        # Keep the full production entrypoint/history checks, with target
        # consistency checked again before and after every compiler stage.
        def check_source(root, stage):
            assert target_context(root, env) == identity, 'Production context changed'
            return release.verify_source_stage(root, stage)
    flutter = release.install_flutter(env)
    env = dict(env, PATH=str(flutter.parent) + os.pathsep + env.get('PATH', ''))
    if identity['target'] == 'preview':
        manifest = release._build_candidate(app, env, flutter, source)
        output = app / 'build/candidate-web/web'
        # Publish an explicitly unaccepted receipt, never /release.json. Keep
        # the complete candidate envelope outside the published directory.
        shutil.copytree(output, destination, symlinks=True)
        paths = list(destination.rglob('*'))
        assert all(not path.is_symlink() for path in paths), 'Linked published preview payload'
        published = {'web/' + path.relative_to(destination).as_posix():
                     release.hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in paths if path.is_file()}
        assert published == manifest['files'], 'Published preview payload differs from audit'
        (destination / 'preview.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
    else:
        # build() uses the strict source callback. The router cannot grant
        # approval to config edits or runtime changes outside the frozen pin.
        check_source(app.parent, 'after-sdk')
        manifest = release._build_release(app, env, flutter, check_source)
        check_source(app.parent, 'before-publish')
        output = app / 'build/web'
    assert target_context(app.parent, env) == identity, 'Vercel context changed before publish'
    if identity['target'] == 'production':
        output.rename(destination)
    return manifest


def main():
    env = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    build_vercel(APP, env)


if __name__ == '__main__':
    main()
