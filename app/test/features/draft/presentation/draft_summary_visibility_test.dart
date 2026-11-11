import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../fixtures/player_lists_app.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });

  for (final width in [360.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('complete proposal totals at $width and $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          PlayerListsFixture(page: 'results', textScale: scale),
        );
        await tester.pumpAndSettle();

        for (final label in [
          'Ranking gospodarzy: 468.0',
          'Ranking gości: 436.0',
        ]) {
          final finder = find.text(label);
          expect(finder, findsOneWidget);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          for (var index = 0; index < label.length; index++) {
            if (label[index] == ' ') continue;
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: index, extentOffset: index + 1),
            );
            expect(boxes, isNotEmpty, reason: '$label loses character $index');
            for (final box in boxes) {
              expect(box.left, greaterThanOrEqualTo(-0.5), reason: label);
              expect(
                box.right,
                lessThanOrEqualTo(paragraph.size.width + 0.5),
                reason: '$label clips character $index horizontally',
              );
              expect(
                box.bottom,
                lessThanOrEqualTo(paragraph.size.height + 0.5),
                reason: '$label clips character $index vertically',
              );
            }
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
