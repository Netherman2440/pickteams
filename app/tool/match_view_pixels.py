"""Check real raster ink within visible Flutter glyph boxes (Pillow runner)."""
import json
import math
import sys
from PIL import Image


def inside(rect, area):
    x, y, w, h = rect
    a, b, c, d = area
    return x >= a and y >= b and x + w <= a + c and y + h <= b + d


def inspect(path, metrics):
    image = Image.open(path).convert('RGB')
    width, height = image.size
    clear = metrics.get('clearRegion', [0, 0, width, height])
    inspected = []
    for panel in metrics['panels']:
        if not inside(panel['rect'], clear):
            continue
        x, y, _, _ = panel['rect']
        background = image.getpixel((math.ceil(x) + 1, math.ceil(y) + 1))
        glyphs = []
        for text in panel['texts']:
            for glyph in text['glyphs']:
                pixels = []
                for gx, gy, gw, gh in glyph['boxes']:
                    for py in range(max(0, math.floor(gy)), min(height, math.ceil(gy + gh))):
                        for px in range(max(0, math.floor(gx)), min(width, math.ceil(gx + gw))):
                            color = image.getpixel((px, py))
                            if max(abs(a - b) for a, b in zip(color, background)) > 24:
                                pixels.append((px, py))
                assert pixels, {'panel': panel['id'], 'glyph': glyph, 'reason': 'no raster ink'}
                glyphs.append(dict(char=glyph['char'], index=glyph['index'],
                    ink=[min(p[0] for p in pixels), min(p[1] for p in pixels),
                         max(p[0] for p in pixels) + 1, max(p[1] for p in pixels) + 1]))
        inspected.append(dict(id=panel['id'], glyphs=glyphs))
    return inspected


if __name__ == '__main__':
    print(json.dumps(inspect(sys.argv[1], json.load(sys.stdin))))
