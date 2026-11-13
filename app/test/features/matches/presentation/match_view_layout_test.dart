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
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'shared identity opt-in=$stacked at ${scale}x keeps long team names visible',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const name = 'Drużyna zawodników z bardzo długą pełną nazwą klubu';
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
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
          if (stacked) {
            final header = tester.widget<SliverPersistentHeader>(
              find.byType(SliverPersistentHeader),
            );
            final extent =
                header.delegate.maxExtent - header.delegate.minExtent;
            for (final fraction in [.25, .5, .75]) {
              tester
                  .state<ScrollableState>(find.byType(Scrollable))
                  .position
                  .jumpTo(extent * fraction);
              await tester.pumpAndSettle();
              final render = tester.renderObject<RenderSliverPersistentHeader>(
                find.byType(SliverPersistentHeader),
              );
              final clip = Rect.fromLTWH(
                0,
                0,
                320,
                render.geometry!.paintExtent,
              );
              // A shrinking stacked header shows either the complete identity
              // or only the badges; it never renders cut-off content.
              expect(clip.contains(tester.getRect(badge).topLeft), isTrue);
              expect(
                tester.getRect(badge).bottom,
                lessThanOrEqualTo(clip.bottom),
              );
              final visible = find.text(name);
              if (visible.evaluate().isNotEmpty) {
                expect(clip.contains(tester.getRect(visible).topLeft), isTrue);
                expect(
                  tester.getRect(visible).bottom,
                  lessThanOrEqualTo(clip.bottom),
                );
              }
              expect(tester.takeException(), isNull);
            }
          }
          tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position
              .jumpTo(1000);
          await tester.pumpAndSettle();
          expect(tester.getSize(badge).width, 16);
          if (stacked) {
            // Collapsed stacked identity: only the pinned badges remain.
            expect(find.text(name), findsNothing);
            expect(find.text('Goście'), findsNothing);
          } else {
            expect(
              tester.getCenter(badge).dy,
              closeTo(tester.getCenter(label).dy, .01),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'stacked totals sit under the names while expanded at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const homeTotal = 'Ranking: 174.6';
        const awayTotal = 'Ranking: 79.2';
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    LineupHeader(
                      homeName: 'Niebiescy',
                      awayName: 'Czerwoni',
                      homeColor: Colors.blue,
                      awayColor: Colors.red,
                      stackedIdentity: true,
                      homeRanking: homeTotal,
                      awayRanking: awayTotal,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final homeBadge = find.byKey(const ValueKey('lineup-home-badge'));
        final homeName = find.text('Niebiescy');
        final awayName = find.text('Czerwoni');
        final home = find.text(homeTotal);
        final away = find.text(awayTotal);
        expect(tester.getSize(homeBadge).width, 48);
        expect(
          tester.getRect(home).top,
          greaterThan(tester.getRect(homeName).bottom),
        );
        expect(
          tester.getCenter(home).dx,
          closeTo(tester.getCenter(homeName).dx, .1),
        );
        expect(
          tester.getCenter(away).dx,
          closeTo(tester.getCenter(awayName).dx, .1),
        );
        // Totals never overlap the roster space below the header.
        final render = tester.renderObject<RenderSliverPersistentHeader>(
          find.byType(SliverPersistentHeader),
        );
        expect(
          tester.getRect(home).bottom,
          lessThanOrEqualTo(render.geometry!.paintExtent),
        );
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .jumpTo(1000);
        await tester.pumpAndSettle();
        // Collapsed: badges stay pinned, names and totals hide.
        expect(tester.getSize(homeBadge).width, 16);
        expect(find.text('Niebiescy'), findsNothing);
        expect(find.text(homeTotal), findsNothing);
        expect(find.text(awayTotal), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'roster measures actual children before imposing uniform height',
    (tester) async {
      final constraints = <BoxConstraints>[];
      var taps = 0;
      final semantics = tester.ensureSemantics();
      Widget panel(String label, double naturalHeight) => LayoutBuilder(
        builder: (context, limits) {
          constraints.add(limits);
          return Semantics(
            label: label,
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: SizedBox(height: naturalHeight),
            ),
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 304,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: MatchViewRosterLayout(
                        rowCount: 2,
                        gap: 8,
                        minimumRowHeight: 76,
                        minimumHeight: 500,
                        children: [
                          panel('Tall player', 257),
                          panel('Short player', 76),
                          panel('Third player', 100),
                          const SizedBox.shrink(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // LayoutBuilder has no intrinsic-height implementation. Only real layout
      // can supply its natural height, at exactly the final 148px column width.
      expect(constraints.length, 6);
      for (final limits in constraints.take(3)) {
        expect(limits.minWidth, 148);
        expect(limits.maxWidth, 148);
        expect(limits.minHeight, 0);
        expect(limits.maxHeight, double.infinity);
      }
      for (final limits in constraints.skip(3)) {
        expect(limits, BoxConstraints.tight(const Size(148, 257)));
      }
      expect(
        tester.getSize(find.byType(MatchViewRosterLayout)),
        const Size(304, 554),
      );
      expect(find.bySemanticsLabel('Tall player'), findsOneWidget);
      await tester.tapAt(const Offset(74, 128));
      expect(taps, 1);
      semantics.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: MatchViewRosterLayout(
              rowCount: 0,
              gap: 8,
              minimumRowHeight: 76,
              minimumHeight: 500,
              children: [SizedBox(key: ValueKey('empty-footer'), height: 40)],
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(MatchViewRosterLayout)).height, 500);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('empty-footer'))).dy,
        460,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
            // Team totals moved into the expanded header, one per column,
            // centered under their team names.
            final totals = switch (count) {
              2 => const ['Ranking: 115.2', 'Ranking: 19.8'],
              8 => const ['Ranking: 174.6', 'Ranking: 79.2'],
              11 => const ['Ranking: 204.3', 'Ranking: 108.9'],
              _ => const <String>[],
            };
            for (final total in totals) {
              final totalFinder = find.text(total);
              expect(totalFinder, findsOneWidget);
            }
            expect(
              tester.getRect(find.text(totals.first)).top,
              greaterThan(tester.getRect(name).bottom),
            );
            expect(
              tester.getCenter(find.text(totals.first)).dx,
              closeTo(tester.getCenter(name).dx, .1),
            );
            expect(
              tester.getCenter(find.text(totals.last)).dx,
              closeTo(tester.getCenter(find.text('Czerwoni')).dx, .1),
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
              // Collapsed header: pinned color badges only.
              expect(tester.getSize(badge).width, 16);
              expect(find.text('Niebiescy'), findsNothing);
              expect(find.text('Czerwoni'), findsNothing);
              for (final total in totals) {
                expect(find.text(total), findsNothing);
              }
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
