#!/usr/bin/env python3
"""Generate the stars-only SQL Editor package. Standard library only."""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERSION = '20261116120000'
NAME = 'add_squad_star_thresholds'
SOURCE_SHA256 = '02cfb0ff0c766c77e76c75be115a981960a32db551b3cb5733f623ff61b4f35a'
SOURCE = ROOT / 'supabase/migrations' / f'{VERSION}_{NAME}.sql'
TEMPLATE = ROOT / 'supabase/tools/stars_operator.template.sql'
OUTPUT = ROOT / 'supabase/tools/squad_star_thresholds_operator.sql'
BEGIN_SOURCE = b'-- BEGIN CANONICAL MIGRATION\n'
END_SOURCE = b'-- END CANONICAL MIGRATION\n'


def generate(source: bytes) -> bytes:
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError('Stars migration differs from the reviewed SHA256')
    text = source.decode('utf-8')
    if any(tag in text for tag in ('$stars_source$', '$stars_body$', '@@')):
        raise ValueError('Unsafe canonical delimiter')
    body = text.split('as $$', 1)[1].split('$$;', 1)[0]
    substitutions = {
        'SOURCE_SHA256': SOURCE_SHA256,
        'SOURCE_DDL': (BEGIN_SOURCE + source + b'\n' + END_SOURCE).decode(),
        'SOURCE_LITERAL': '$stars_source$' + text + '$stars_source$',
        'FUNCTION_BODY': '$stars_body$' + body + '$stars_body$',
    }
    result = TEMPLATE.read_text(encoding='utf-8')
    for key, value in substitutions.items():
        marker = '@@' + key + '@@'
        if marker not in result:
            raise ValueError('Missing template marker: ' + key)
        result = result.replace(marker, value)
    if '@@' in result:
        raise ValueError('Unknown template marker')
    return result.encode('utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected = generate(SOURCE.read_bytes())
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != expected:
            parser.exit(1, 'Stale stars operator package\n')
        print('PASS exact reviewed source and reproducible stars operator package')
    else:
        OUTPUT.write_bytes(expected)
        print(f'Wrote {OUTPUT}')


if __name__ == '__main__':
    main()
