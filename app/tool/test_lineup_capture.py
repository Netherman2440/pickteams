import copy
import struct
import unittest

from PIL import Image, ImageDraw

from capture_lineups import check_badges, check_viewport, png_size, roster_snapshot
from lineup_pixels import badge_by_color, badge_geometry


class CaptureContractTest(unittest.TestCase):
    def test_png_dimensions_are_not_dom_dimensions(self):
        prefix = b'\x89PNG\r\n\x1a\n' + b'\0' * 8
        self.assertEqual(png_size(prefix + struct.pack('>II', 473, 640)), (473, 640))
        self.assertNotEqual(png_size(prefix + struct.pack('>II', 473, 640)), (360, 640))
        with self.assertRaises(AssertionError):
            png_size(b'not a screenshot')

    def metrics(self):
        return dict(viewport=[360, 640], document=dict(scroll=[360, 640]),
                    body=dict(scroll=[473, 640]), canvases=[],
                    flutter=dict(rect=dict(x=0, y=0, width=360, height=640)),
                    overflowText=[dict(text='fixture@example.invalid', rect=dict(right=473),
                        ancestors=[dict(tag='FLT-SEMANTICS', filter='opacity(0)')])])

    def test_only_explained_invisible_semantics_overflow_is_allowed(self):
        metrics = self.metrics()
        check_viewport(metrics, (360, 640))
        # Chromium reports integer scrollWidth, but Range geometry is fractional.
        metrics['overflowText'][0]['rect']['right'] = 473.015625
        check_viewport(metrics, (360, 640))
        for mutation in ['visible', 'body', 'document', 'flutter', 'canvas']:
            changed = copy.deepcopy(metrics)
            if mutation == 'visible':
                changed['overflowText'][0]['ancestors'][0]['filter'] = 'none'
            elif mutation == 'body':
                changed['body']['scroll'][0] = 500
            elif mutation == 'document':
                changed['document']['scroll'][0] = 473
            elif mutation == 'flutter':
                changed['flutter']['rect']['width'] = 473
            else:
                changed['canvases'] = [dict(rect=dict(left=0, right=473))]
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                check_viewport(changed, (360, 640))

    def test_badges_measure_paint_not_screenshot_hash_changes(self):
        for size in [48, 16]:
            image = Image.new('RGB', (360, 640), (43, 42, 38))
            draw = ImageDraw.Draw(image)
            draw.rectangle((30, 50-size//2, 30+size-1, 50+size//2-1), fill=(150, 150, 150))
            draw.rectangle((31, 51-size//2, 30+size-2, 50+size//2-2), fill=(30, 136, 229))
            badge = badge_geometry(image, dict(x=86, y=40, height=20), [30, 136, 229])
            self.assertEqual(badge['width'], size)
            self.assertEqual(badge['height'], size)
            check_badges({'home': badge}, size, 180)
            with self.assertRaises(AssertionError):
                check_badges({'home': badge}, 16 if size == 48 else 48, 180)
            with self.assertRaises(AssertionError):
                check_badges({'away': badge}, size, 180)

    def test_collapsed_badges_are_found_by_color_without_a_label(self):
        image = Image.new('RGB', (360, 640), (43, 42, 38))
        draw = ImageDraw.Draw(image)

        def badge(cx, color):
            draw.rectangle((cx - 8, 42, cx + 7, 57), fill=(150, 150, 150))
            draw.rectangle((cx - 7, 43, cx + 6, 56), fill=color)

        badge(92, (30, 136, 229))
        badge(268, (229, 57, 53))
        pixels = image.convert('RGB')
        home = badge_by_color(pixels, [30, 136, 229], 180, 'home')
        away = badge_by_color(pixels, [229, 57, 53], 180, 'away')
        self.assertEqual((home['x'], home['y'], home['width'], home['height']),
                         (84, 42, 16, 16))
        self.assertEqual((away['x'], away['y'], away['width'], away['height']),
                         (260, 42, 16, 16))
        check_badges({'home': home, 'away': away}, 16, 180)
        with self.assertRaises(AssertionError):
            check_badges({'home': home, 'away': away}, 48, 180)
        # A missing badge color and a badge in the wrong half both fail.
        with self.assertRaises(AssertionError):
            badge_by_color(pixels, [1, 2, 3], 180, 'home')
        with self.assertRaises(AssertionError):
            badge_by_color(pixels, [30, 136, 229], 180, 'away')

    def test_roster_snapshot_detects_side_changes_and_keeps_rating(self):
        nodes = [dict(role='button', text='Player One 50.13', rect=dict(x=8)),
                 dict(role='button', text='Player Two 40.25', rect=dict(x=184)),
                 dict(role='button', text='Akcje meczu', rect=dict(x=320))]
        original = roster_snapshot(nodes, 180)
        self.assertEqual(original, [('Player One 50.13', 'home'), ('Player Two 40.25', 'away')])
        nodes[0]['rect']['x'] = 184
        self.assertNotEqual(roster_snapshot(nodes, 180), original)


if __name__ == '__main__':
    unittest.main()
