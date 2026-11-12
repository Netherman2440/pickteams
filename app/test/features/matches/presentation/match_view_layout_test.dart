import 'package:app/features/matches/presentation/widgets/match_view_roster.dart';
import 'package:app/core/widgets/probability_slider.dart';
import 'package:app/core/widgets/lineup_header.dart';
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

  for (final stacked in [false, true]) {
    testWidgets(
      'shared identity opt-in=$stacked keeps long team names visible',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const name = 'Drużyna zawodników z bardzo długą pełną nazwą klubu';
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    LineupHeader(
                      homeName: name,
                      awayName: 'Goście',
                      homeColor: Colors.blue,
                      awayColor: Colors.red,
                      stackedIdentity: stacked,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final badge = find.byKey(const ValueKey('lineup-home-badge'));
        final label = find.text(name);
        expect(tester.getSize(badge).width, 48);
        if (stacked) {
          expect(
            tester.getRect(badge).bottom,
            lessThan(tester.getRect(label).top),
          );
        } else {
          expect(
            tester.getCenter(badge).dy,
            closeTo(tester.getCenter(label).dy, .01),
          );
        }
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .jumpTo(1000);
        await tester.pumpAndSettle();
        expect(tester.getSize(badge).width, 16);
        expect(
          tester.getCenter(badge).dy,
          closeTo(tester.getCenter(label).dy, .01),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('shared widgets retain the draft defaults', () {
    const header = LineupHeader(
      homeName: 'Home',
      awayName: 'Away',
      homeColor: Colors.blue,
      awayColor: Colors.red,
    );
    const probability = ProbabilitySlider(
      homeColor: Colors.blue,
      awayColor: Colors.red,
      homeProbability: .52,
    );
    expect(header.stackedIdentity, isFalse);
    expect(probability.compact, isFalse);
  });

  for (final awayCount in [0, 5, 8]) {
    testWidgets(
      'uneven short names keep equal panels and footer: 8/$awayCount',
      (tester) async {
        tester.view.physicalSize = const Size(390, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          lineupFixture(count: 8, awayCount: awayCount, wideRankings: true),
        );
        await tester.pumpAndSettle();
        final panels = find.byType(MatchViewPlayerPanel);
        expect(panels, findsNWidgets(8 + awayCount));
        final height = tester.getSize(panels.first).height;
        for (final panel in panels.evaluate()) {
          expect(
            tester.getSize(find.byWidget(panel.widget)).height,
            closeTo(height, .01),
          );
        }
        expect(find.text('105.25'), findsOneWidget);
        expect(find.text('115.38'), findsNothing);
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ),
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final footer = find.byType(ProbabilitySlider);
        for (final panel in panels.evaluate()) {
          expect(
            tester.getRect(find.byWidget(panel.widget)).bottom,
            lessThan(tester.getRect(footer).top),
          );
        }
        await tester.tap(find.byTooltip('Jak to obliczamy?'));
        await tester.pumpAndSettle();
        expect(find.textContaining('historycznych wyników'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
            final minimums = <double>[14 * scale * 1.35 * 2 + 16];
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
              minimums.add(paragraph.size.height + 16);
              final boxes = [
                for (var i = 0; i < panel.player.name.length; i++)
                  if (panel.player.name[i].trim().isNotEmpty)
                    ...paragraph.getBoxesForSelection(
                      TextSelection(baseOffset: i, extentOffset: i + 1),
                    ),
              ];
              expect(
                boxes.length,
                panel.player.name.replaceAll(RegExp(r'\s'), '').length,
              );
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
            if (count != 2) {
              expect(
                height,
                closeTo(minimums.reduce((a, b) => a > b ? a : b), .01),
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
