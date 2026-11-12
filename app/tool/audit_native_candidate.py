"""Offline compiled-APK checks. Called only after SDK dumps and local signing."""
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from build_native_candidate import ABIS, audit_apk

CERTIFICATE = 'b33c674d593a79cce25b7b98c78b2eedd4cfea49b93538f23c10d30059b31e18'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(apk, source, base, evidence):
    # Use the existing local image-tools environment; never install dependencies.
    from PIL import Image

    checks = []

    def check(name, condition):
        assert condition, name
        checks.append(name)

    a = '{http://schemas.android.com/apk/res/android}'
    m = ET.fromstring((evidence/'manifest.stdout').read_text())
    app, sdk = m.find('application'), m.find('uses-sdk')
    check('package/version/min24/target36/nondebuggable',
          m.get('package') == 'com.example.app' and m.get(a+'versionName') == '1.0.3'
          and m.get(a+'versionCode') == '2026111202' and sdk.get(a+'minSdkVersion') == '24'
          and sdk.get(a+'targetSdkVersion') == '36' and app.get(a+'debuggable', 'false') == 'false')
    check('exact permissions', sorted(x.get(a+'name') for x in m.findall('uses-permission')) == [
        'android.permission.INTERNET', 'com.example.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'])
    check('signature-protected receiver', [(x.get(a+'name'), x.get(a+'protectionLevel')) for x in m.findall('permission')] == [
        ('com.example.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION', '0x2')])
    main = [x for x in app.findall('activity') if x.get(a+'name') == 'com.example.app.MainActivity']
    check('unique exported launcher inherits label', len(main) == 1 and main[0].get(a+'exported') == 'true' and a+'label' not in main[0].attrib)
    main = main[0]
    launch = [f for f in main.findall('intent-filter') if any(x.get(a+'name') == 'android.intent.action.MAIN' for x in f.findall('action'))]
    check('MAIN LAUNCHER no label override', len(launch) == 1 and a+'label' not in launch[0].attrib and [x.get(a+'name') for x in launch[0].findall('category')] == ['android.intent.category.LAUNCHER'])
    check('Flutter deep linking disabled', [x.get(a+'value') for x in main.findall('meta-data') if x.get(a+'name') == 'flutter_deeplinking_enabled'] == ['false'])
    callbacks = [f for f in main.findall('intent-filter') if any(x.get(a+'name') == 'android.intent.action.VIEW' for x in f.findall('action'))]
    check('single callback', len(callbacks) == 1)
    check('exact callback URI and categories', [x.attrib for x in callbacks[0].findall('data')] == [{a+'scheme': 'pl.pickteams', a+'host': 'auth', a+'path': '/callback'}] and sorted(x.get(a+'name') for x in callbacks[0].findall('category')) == ['android.intent.category.BROWSABLE', 'android.intent.category.DEFAULT'])
    signature = (evidence/'signature.stdout').read_text()
    check('v2 signature and unchanged local certificate', 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature and 'Signer #1 certificate SHA-256 digest: '+CERTIFICATE in signature and digest(base/'signing-certificate.der') == CERTIFICATE)
    check('private APK and directory', apk.stat().st_mode & 0o777 == 0o600 and apk.parent.stat().st_mode & 0o777 == 0o700)

    resources, config, current = {}, None, None
    for line in (evidence/'resources.stdout').read_text().splitlines():
        match = re.fullmatch(r'\s*config (.+):', line)
        if match:
            config = match[1]
        match = re.fullmatch(r'\s*resource (0x[0-9a-f]+) (\S+): t=(0x[0-9a-f]+) d=(0x[0-9a-f]+).*', line)
        if match:
            current = {'config': config, 'name': match[2], 'type': int(match[3], 16), 'data': int(match[4], 16)}
            resources.setdefault(match[1], []).append(current)
        match = re.fullmatch(r'\s*\(string8\) "(.*)"', line)
        if match and current is not None:
            current['string'] = match[1]

    def resolve(value):
        assert re.fullmatch(r'@ref/0x[0-9a-f]{8}', value)
        return resources[value[5:]]

    labels = resolve(app.get(a+'label'))
    check('compiled Pickteams label in every configuration', bool(labels) and all(r['type'] == 3 and r.get('string') == 'Pickteams' for r in labels))
    icons = resolve(app.get(a+'icon'))
    densities = {'mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'}
    check('five launcher densities and adaptive', len(icons) == 6 and {r['config'] for r in icons} == densities | {'anydpi-v26'})
    adaptive = ET.fromstring((evidence/'adaptive.stdout').read_text())
    check('adaptive structure', adaptive.tag == 'adaptive-icon' and [x.tag for x in adaptive] == ['background', 'foreground'])
    background = resolve(adaptive.find('background').get(a+'drawable'))
    check('adaptive background matches source', len(background) == 1 and background[0]['data'] == 0xff2e2c29 and '#2e2c29' in (source/'app/android/app/src/main/res/values/colors.xml').read_text().lower())
    fg = adaptive.find('foreground')
    check('foreground inset structure', not fg.attrib and len(fg) == 1 and fg[0].tag == 'inset')
    inset = fg[0]
    check('16 percent inset', set(inset.attrib) == {a+'inset', a+'drawable'} and abs(float(inset.get(a+'inset').rstrip('%')) - 16) < 0.00001)
    foreground = resolve(inset.get(a+'drawable'))
    check('five foreground densities', len(foreground) == 5 and {r['config'] for r in foreground} == densities)
    public = json.loads((base/'client-config.json').read_text())
    check('exact public config fields', set(public) == {'SUPABASE_URL', 'SUPABASE_ANON_KEY'})
    tracked = subprocess.check_output(['git', 'ls-files', '-z', 'app'], cwd=source).decode().split('\0')
    hashes = {digest(source/n) for n in tracked if n and Path(n).suffix in {'.dart', '.kt', '.java', '.gradle', '.kts', '.yaml', '.yml', '.env', '.json', '.py'}}
    hashes |= {digest(base/'client-config.json'), digest(Path.home()/'.android/debug.keystore')}
    names = audit_apk(apk, public, hashes)
    check('raw source/key/config/callback exclusion and all-ABI public values', True)
    (evidence/'archive-files.txt').write_text('\n'.join(names)+'\n')
    elf, pixels = [], []
    with zipfile.ZipFile(apk) as z:
        check('exact engine and AOT ABI sets', all({n.split('/')[1] for n in names if n.startswith('lib/') and n.endswith('/'+library)} == set(ABIS) for library in ('libapp.so', 'libflutter.so')))
        for name in names:
            if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
                data = z.read(name)
                assert data[:6] == b'\x7fELF\x02\x01'
                assert struct.unpack_from('<H', data, 18)[0] == (183 if '/arm64-v8a/' in name else 62)
                phoff = struct.unpack_from('<Q', data, 32)[0]
                size, count = struct.unpack_from('<HH', data, 54)
                assert size == 56 and count > 0 and phoff + size*count <= len(data)
                loads = []
                for i in range(count):
                    kind, flags, off, va, pa, fs, ms, alignment = struct.unpack_from('<IIQQQQQQ', data, phoff+size*i)
                    if kind == 1:
                        assert alignment >= 16384 and alignment & (alignment-1) == 0 and off % alignment == va % alignment and fs <= ms and off+fs <= len(data)
                        loads.append({'offset': off, 'vaddr': va, 'alignment': alignment})
                assert loads
                info = z.getinfo(name)
                assert info.compress_type == zipfile.ZIP_STORED
                with apk.open('rb') as raw:
                    raw.seek(info.header_offset)
                    header = raw.read(30)
                name_size, extra_size = struct.unpack_from('<HH', header, 26)
                assert (info.header_offset+30+name_size+extra_size) % 16384 == 0
                elf.append({'file': name, 'loads': loads})
        check('every 64-bit ELF LOAD and ZIP offset is 16KiB aligned', bool(elf))
        for group, prefix, filename in (([r for r in icons if r['config'] != 'anydpi-v26'], 'mipmap', 'ic_launcher.png'), (foreground, 'drawable', 'ic_launcher_foreground.png')):
            for resource in group:
                original_path = source/'app/android/app/src/main/res'/(prefix+'-'+resource['config'])/filename
                compiled = Image.open(io.BytesIO(z.read(resource['string']))).convert('RGBA')
                original = Image.open(original_path).convert('RGBA')
                assert compiled.size == original.size
                assert all(x[3] == y[3] and (x[3] == 0 or x[:3] == y[:3]) for x, y in zip(compiled.getdata(), original.getdata()))
                pixels.append({'archive': resource['string'], 'source': str(original_path), 'size': compiled.size, 'alpha_and_visible_rgb_exact': True})
                if prefix == 'mipmap' and resource['config'] == 'mdpi':
                    compiled.save(evidence/'compiled-mdpi.png')
                    original.save(evidence/'source-mdpi.png')
        check('ten rasters match source alpha and visible RGB', len(pixels) == 10)
        check('badging icon paths resolve', all(n in {r['string'] for r in icons} and n in names for n in re.findall(r"application-icon[^:]*:'([^']+)'", (evidence/'badging.stdout').read_text())))
    for name, data in [('audit-results', checks), ('pixels', pixels), ('elf', elf), ('resource-resolution', {'labels': labels, 'launcher': icons, 'background': background, 'foreground': foreground})]:
        (evidence/(name+'.json')).write_text(json.dumps(data, indent=2)+'\n')
    # Evidence is private, but still must not contain actual public-client values.
    check('no client values in evidence files', all(value.encode() not in p.read_bytes() for p in evidence.iterdir() if p.is_file() for value in public.values()))
    return checks
