"""Reviewed joint-release boundary. No environment or command-line pin overrides."""
import re
import subprocess

ACCEPTED_SOURCE = '6383c1cf3363cddeebcfe22395183df84f153cc1'
VERSION = '1.0.9'
VERSION_CODE = 2026112602
# These files cannot change runtime behavior. Each remains subject to review.
RELEASE_FILES = (
    'app/tool/release_contract.py',
    'app/tool/test_release_contract.py',
    'app/tool/build_native_candidate.py',
    'app/tool/test_build_native_candidate.py',
    'app/tool/sign_native_candidate.py',
    'app/tool/audit_native_candidate.py',
    'app/tool/build_web_release.py',
    'app/tool/test_build_web_release.py',
    '.github/workflows/private-native-candidate.yml',
    '.github/workflows/main.yml',
)


# Flutter 3.47.9 pub-get migration, restored before exact-config analysis/build.
ANALYSIS_MIGRATION = b'''analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
    - web/**
    - windows/**
    - macos/**
    - linux/**
'''


def restore_analysis(path, original):
    expected = original.replace(b'include: package:flutter_lints/flutter.yaml',
                                ANALYSIS_MIGRATION + b'include: package:flutter_lints/flutter.yaml')
    assert path.read_bytes() in (original, expected), 'Unknown analysis migration'
    path.write_bytes(original)


def validate_version(pubspec):
    versions = re.findall(r'^version: (.+)$', pubspec, re.MULTILINE)
    assert versions == [f'{VERSION}+{VERSION_CODE}'], 'Release version mismatch'


def validate_metadata(metadata):
    assert metadata['reviewed_ui_source'] == ACCEPTED_SOURCE, 'Unaccepted runtime source'
    assert (metadata['build_name'], metadata['build_number']) == (VERSION, VERSION_CODE), 'Release version mismatch'
    assert metadata['entrypoint'] == 'lib/main.dart', 'Wrong production entrypoint'


# Only this append is allowed against the accepted .gitignore bytes. Vercel
# creates output/builds.json before invoking our build command. Project settings
# and all other .vercel paths remain source inputs, not ignored build output.
WEB_OUTPUT_IGNORE = b'\n# Generated Vercel Build Output API artifacts (not project settings).\n/.vercel/output/\n'


def verify_source(root):
    """Compare the whole repository, not only lib; pubspec may change version only."""
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root)

    status = git('status', '--porcelain', '--untracked-files=all')
    # Status contains paths only; never dump diffs or configuration contents.
    assert not status, f'Source mutation (status paths only): {status!r}'
    return verify_source_history(root)


def verify_source_history(root):
    """Immutable release policy, separate from each caller's worktree admission.

    This is not source admission by itself. Generic/native callers must use
    verify_source; web also checks every tracked byte, mode, index and control.
    """
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root)

    subprocess.run(['git', 'merge-base', '--is-ancestor', ACCEPTED_SOURCE, 'HEAD'], cwd=root, check=True)
    changed = git('diff', '--name-only', ACCEPTED_SOURCE, 'HEAD').decode().splitlines()
    assert set(changed) <= set(RELEASE_FILES) | {'app/pubspec.yaml', 'app/.gitignore'}, 'Unapproved source differences'
    if 'app/.gitignore' in changed:
        accepted_ignore = git('show', ACCEPTED_SOURCE + ':app/.gitignore')
        expected_ignore = accepted_ignore + WEB_OUTPUT_IGNORE
        assert git('show', 'HEAD:app/.gitignore') == expected_ignore, 'Unapproved web output ignore change'
        assert (root / 'app/.gitignore').read_bytes() == expected_ignore, 'Unapproved web output ignore change'
        assert git('ls-tree', 'HEAD', '--', 'app/.gitignore').split()[:2] == [b'100644', b'blob'], 'Unapproved web output ignore mode'
    original = git('show', ACCEPTED_SOURCE + ':app/pubspec.yaml').decode()
    current = (root / 'app/pubspec.yaml').read_text()
    validate_version(current)
    assert re.sub(r'^version: .+$', 'version: <release>', original, flags=re.MULTILINE) == re.sub(
        r'^version: .+$', 'version: <release>', current, flags=re.MULTILINE), 'Non-version pubspec change'
    return git('rev-parse', 'HEAD').decode().strip()
