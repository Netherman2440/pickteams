import copy
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw
from capture_match_view import check_panels, identity
from match_view_pixels import inspect


def metrics():
    def text(value, rect, font):
        x, y, w, h = rect
        return dict(text=value, rect=rect, maxLines=None, exceeded=False,
                    fontSize=font, scaledFontSize=font,
                    glyphs=[dict(char=c, index=i, boxes=[[x + i * w / len(value), y, w / len(value), h]])
                            for i, c in enumerate(value)])
    return dict(viewport=[0, 0, 210, 640], footer=[0, 170, 210, 60],
                teams={'home': {'name': 'Home', 'color': 1}, 'away': {'name': 'Away', 'color': 2}},
                panels=[dict(id=str(x), name='Ab', ranking='9.90', rect=[x, 100, 100, 60],
                    texts=[text('Ab', [x + 2, 120, 20, 20], 14),
                           text('9.90', [x + 40, 122, 30, 16], 12)]) for x in [0, 110]])


class MatchViewProofTest(unittest.TestCase):
    def test_geometry_rejects_clipping_shrink_stacking_and_unequal_rows(self):
        good = metrics()
        check_panels(good, 1)
        mutations = [
            lambda m: m['panels'][0]['texts'][0].update(maxLines=2),
            lambda m: m['panels'][0]['texts'][0].update(fontSize=12),
            lambda m: m['panels'][0]['texts'][1]['rect'].__setitem__(1, 150),
            lambda m: m['panels'][0]['rect'].__setitem__(3, 80),
            lambda m: m['panels'][0]['texts'][0]['glyphs'][0].update(boxes=[]),
            lambda m: m['footer'].__setitem__(1, 120),
        ]
        for mutation in mutations:
            bad = copy.deepcopy(good)
            mutation(bad)
            with self.assertRaises(AssertionError):
                check_panels(bad, 1)

    def test_saved_identity_detects_names_ranks_teams_and_sides(self):
        good = metrics()
        for mutation in [
            lambda m: m['panels'][0].update(name='shortened'),
            lambda m: m['panels'][0].update(ranking='19.90'),
            lambda m: m['panels'].pop(),
            lambda m: m['teams']['home'].update(color=99),
            lambda m: m['teams']['home'].update(name='changed'),
            lambda m: m['panels'][0]['rect'].__setitem__(0, 111),
        ]:
            changed = copy.deepcopy(good)
            mutation(changed)
            self.assertNotEqual(identity(good), identity(changed))

    def test_raster_check_rejects_a_blank_glyph_not_just_semantics(self):
        data = metrics()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'frame.png'
            image = Image.new('RGB', (210, 640), (40, 40, 40))
            draw = ImageDraw.Draw(image)
            for panel in data['panels']:
                for text in panel['texts']:
                    for glyph in text['glyphs']:
                        x, y, w, h = glyph['boxes'][0]
                        draw.rectangle((x + 1, y + 1, x + w - 1, y + h - 1), fill='white')
            image.save(path)
            self.assertEqual(len(inspect(path, data)), 2)
            draw.rectangle((2, 120, 11, 140), fill=(40, 40, 40))
            image.save(path)
            with self.assertRaises(AssertionError):
                inspect(path, data)


if __name__ == '__main__':
    unittest.main()
