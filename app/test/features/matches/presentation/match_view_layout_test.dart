import 'package:app/features/matches/presentation/widgets/match_view_roster.dart';
import 'package:app/core/widgets/probability_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../fixtures/lineup_app.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });

  for (final width in [320.0, 360.0, 390.0, 1440.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final count in [2, 8, 11]) {
        testWidgets(
          'full inline names $width x $scale count=$count long=${count != 2}',
          (tester) async {
            tester.view.physicalSize = Size(width, 640);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final previousError = FlutterError.onError;
            FlutterError.onError = (details) {
              // ignore: avoid_print
              print(details.toString());
              previousError!(details);
            };
            await tester.pumpWidget(
              lineupFixture(
                count: count,
                scale: scale,
                longNames: count != 2,
                wideRankings: true,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final badge = find.byKey(const ValueKey('lineup-home-badge'));
            final name = find.text('Niebiescy');
            expect(tester.getSize(badge).width, 48);
            expect(
              tester.getRect(badge).bottom,
              lessThan(tester.getRect(name).top),
            );
            expect(
              tester.getCenter(badge).dx,
              closeTo(tester.getCenter(name).dx, .1),
            );
            final panels = find.byType(MatchViewPlayerPanel);
            expect(panels, findsNWidgets(count * 2));
            final height = tester.getSize(panels.first).height;
            for (final element in panels.evaluate()) {
              final panel = element.widget as MatchViewPlayerPanel;
              final finder = find.byWidget(panel);
              final bounds = tester.getRect(finder);
              expect(bounds.height, closeTo(height, .01));
              final textFinder = find.descendant(
                of: finder,
                matching: find.text(panel.player.name),
              );
              final text = tester.widget<Text>(textFinder);
              expect(text.maxLines, isNull);
              expect(text.overflow, isNot(TextOverflow.ellipsis));
              expect(text.style!.fontSize, 14);
              final paragraph = tester.renderObject<RenderParagraph>(
                textFinder,
              );
              expect(paragraph.didExceedMaxLines, isFalse);
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: panel.player.name.length,
                ),
              );
              expect(boxes, isNotEmpty);
              for (final box in boxes) {
                final topLeft = paragraph.localToGlobal(
                  Offset(box.left, box.top),
                );
                final bottomRight = paragraph.localToGlobal(
                  Offset(box.right, box.bottom),
                );
                expect(topLeft.dy, greaterThanOrEqualTo(bounds.top));
                expect(bottomRight.dy, lessThanOrEqualTo(bounds.bottom));
                expect(topLeft.dx, greaterThanOrEqualTo(bounds.left));
                expect(bottomRight.dx, lessThanOrEqualTo(bounds.right));
              }
              final rank = find.descendant(
                of: finder,
                matching: find.text(panel.player.ranking.toStringAsFixed(2)),
              );
              expect(tester.widget<Text>(rank).style!.fontSize, 12);
              expect(
                tester.getRect(textFinder).right,
                lessThan(tester.getRect(rank).left),
              );
              expect(tester.getCenter(rank).dy, closeTo(bounds.center.dy, .01));
              expect(
                tester.getCenter(textFinder).dy,
                closeTo(bounds.center.dy, .01),
              );
            }
            final scroll = tester.state<ScrollableState>(
              find.descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              ),
            );
            final footer = find.byType(ProbabilitySlider);
            final last = tester.getRect(panels.last);
            expect(
              tester.getRect(footer).top,
              greaterThanOrEqualTo(last.bottom),
            );
            if (count == 2) {
              expect(
                tester.getRect(footer).bottom,
                closeTo(
                  tester.getRect(find.byType(CustomScrollView)).bottom - 8,
                  .1,
                ),
              );
              expect(scroll.position.maxScrollExtent, closeTo(0, .1));
            } else {
              scroll.position.jumpTo(scroll.position.maxScrollExtent);
              await tester.pumpAndSettle();
              expect(tester.getSize(badge).width, 16);
              expect(
                tester.getCenter(badge).dy,
                closeTo(tester.getCenter(name).dy, .1),
              );
              expect(footer.hitTestable(), findsOneWidget);
              expect(
                tester.getRect(panels.last).bottom,
                lessThan(tester.getRect(footer).top),
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
