"""Measure badge paint in original viewport PNGs without modifying the images."""
import json
from pathlib import Path
import sys

from PIL import Image


def _expand_to_border(pixels, left, right, y, core_width):
    """Grow a core color run to the badge outline and report its geometry."""
    width, height = pixels.size
    background = pixels.getpixel((left - 3, y))

    def background_at(x, row):
        return max(abs(a - b) for a, b in zip(pixels.getpixel((x, row)), background)) <= 2

    while left > 0 and not background_at(left - 1, y):
        left -= 1
    while right < width and not background_at(right, y):
        right += 1
    center = (left + right) // 2
    top = bottom = y
    while top > 0 and not background_at(center, top - 1):
        top -= 1
    while bottom < height and not background_at(center, bottom):
        bottom += 1
    return dict(x=left, y=top, width=right - left, height=bottom - top,
                coreWidth=core_width)


def badge_geometry(pixels, label, color):
    """Find the color run immediately left of a team name, then its border."""
    width, height = pixels.size
    y = round(label['y'] + label['height'] / 2)
    right = min(width, int(label['x']))
    runs = []
    start = None
    for x in range(max(0, right - 90), right):
        matches = pixels.getpixel((x, y)) == tuple(color)
        if matches and start is None:
            start = x
        if not matches and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, right))
    runs = [(a, b) for a, b in runs if b - a >= 8]
    assert runs, f'No badge color {color} beside {label}'
    left, right = runs[-1]
    geometry = _expand_to_border(pixels, left, right, y, right - left)
    geometry['color'] = list(color)
    return geometry


def badge_by_color(pixels, color, midpoint, side):
    """Locate a collapsed badge by its solid color, topmost in its half.

    The collapsed stacked header shows no team-name text to anchor on; the
    pinned badge is the first solid team-color block below the toolbar.
    """
    width, height = pixels.size
    x_range = (0, int(midpoint)) if side == 'home' else (int(midpoint), width)
    target = tuple(color)
    for y in range(height):
        start = None
        for x in range(*x_range):
            if pixels.getpixel((x, y)) == target:
                if start is None:
                    start = x
            elif start is not None:
                if x - start >= 8:
                    geometry = _expand_to_border(pixels, start, x, y, x - start)
                    geometry['color'] = list(color)
                    return geometry
                start = None
        if start is not None and x_range[1] - start >= 8:
            geometry = _expand_to_border(pixels, start, x_range[1], y,
                                         x_range[1] - start)
            geometry['color'] = list(color)
            return geometry
    raise AssertionError(f'No badge color {color} within {x_range}')


def measure(path, identities):
    with Image.open(path) as image:
        pixels = image.convert('RGB')
        return {
            side: (badge_by_color(pixels, identity['color'],
                                  identity.get('midpoint', pixels.size[0] / 2), side)
                   if identity.get('label') is None
                   else badge_geometry(pixels, identity['label'], identity['color']))
            for side, identity in identities.items()
        }


if __name__ == '__main__':
    print(json.dumps(measure(Path(sys.argv[1]), json.load(sys.stdin))))
