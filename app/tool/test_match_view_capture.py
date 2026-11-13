import copy
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw
from capture_match_view import check_header, check_panels, identity
from match_view_pixels import inspect


def header_metrics(**overrides):
    metrics = dict(
        viewport=[0, 80, 210, 560],
        headerGeometry=dict(minExtent=36, maxExtent=111, scrollOffset=0, paintExtent=111),
        identities={
            'lineup-home-badge': [10, 90, 48, 48],
            'lineup-away-badge': [112, 90, 48, 48],
        },
        labels=[
            dict(text='Home', rect=[10, 146, 48, 18]),
            dict(text='Away', rect=[112, 146, 48, 18]),
            dict(text='Ranking: 174.6', rect=[10, 168, 48, 16]),
            dict(text='Ranking: 79.2', rect=[112, 168, 48, 16]),
        ],
        teams={'home': {'name': 'Home', 'color': 1}, 'away': {'name': 'Away', 'color': 2}},
    )
    metrics.update(overrides)
    return metrics


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


class MatchViewHeaderTest(unittest.TestCase):
    def test_expanded_header_requires_two_totals_under_their_names(self):
        check_header(header_metrics())
        mutations = [
            lambda m: m['labels'].pop(2),
            lambda m: [m['labels'].pop(2) for _ in range(2)],
            lambda m: m['labels'].__setitem__(2, dict(text='Ranking: 174.6', rect=[10, 140, 48, 16])),
            lambda m: m['labels'][2]['rect'].__setitem__(0, 15),
            lambda m: m['headerGeometry'].update(paintExtent=100),
            lambda m: m['identities']['lineup-home-badge'].__setitem__(2, 16),
            lambda m: m['labels'].append(dict(text='Home', rect=[10, 146, 48, 18])),
        ]
        for mutation in mutations:
            bad = header_metrics()
            mutation(bad)
            with self.assertRaises(AssertionError):
                check_header(bad)

    def test_collapsed_header_rejects_names_totals_and_large_badges(self):
        collapsed = header_metrics(
            headerGeometry=dict(minExtent=36, maxExtent=111, scrollOffset=75, paintExtent=36),
            identities={
                'lineup-home-badge': [53, 100, 16, 16],
                'lineup-away-badge': [141, 100, 16, 16],
            },
            labels=[],
        )
        check_header(collapsed, collapsed=True)
        for mutation in [
            lambda m: m['labels'].append(dict(text='Home', rect=[10, 100, 48, 18])),
            lambda m: m['labels'].append(dict(text='Ranking: 174.6', rect=[10, 100, 48, 16])),
            lambda m: m['identities']['lineup-home-badge'].__setitem__(2, 48),
        ]:
            bad = header_metrics(
                headerGeometry=collapsed['headerGeometry'],
                identities=collapsed['identities'],
                labels=[],
            )
            mutation(bad)
            with self.assertRaises(AssertionError):
                check_header(bad, collapsed=True)


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
