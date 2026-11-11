"""Measure badge paint in original viewport PNGs without modifying the images."""
import json
from pathlib import Path
import sys

from PIL import Image


def badge_geometry(image, label, color):
    """Find the color run immediately left of a team name, then its border."""
    pixels = image.convert('RGB')
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
    core_width = right - left
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
    return dict(x=left, y=top, width=right-left, height=bottom-top,
                coreWidth=core_width, color=list(color))


def measure(path, identities):
    with Image.open(path) as image:
        return {side: badge_geometry(image, identity['label'], identity['color'])
                for side, identity in identities.items()}


if __name__ == '__main__':
    print(json.dumps(measure(Path(sys.argv[1]), json.load(sys.stdin))))
