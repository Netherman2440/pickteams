import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/presentation/widgets/match_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../fixtures/match_lists_app.dart';

Finder get tile => find.byType(MatchTile);

RenderParagraph paragraph(WidgetTester tester, String text, int occurrence) =>
    tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: tile, matching: find.byType(RichText)),
        )
        .where((p) => p.text.toPlainText() == text)
        .elementAt(occurrence);

// Text presence is not visibility: check every laid-out glyph box, overflow,
// and the painted paragraph's global bounds against the actual card.
Rect visibleText(
  WidgetTester tester,
  String text, {
  int occurrence = 0,
  bool ink = false,
}) {
  final p = paragraph(tester, text, occurrence);
  expect(p.didExceedMaxLines, isFalse, reason: text);
  for (var i = 0; i < text.length; i++) {
    // A wrapping space has a selection box beyond the line, but no ink.
    if (text[i].trim().isEmpty) continue;
    final glyphs = p.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    expect(glyphs, isNotEmpty, reason: '$text glyph $i');
    for (final box in glyphs) {
      expect(box.left, greaterThanOrEqualTo(-0.5), reason: text);
      expect(box.right, lessThanOrEqualTo(p.size.width + 0.5), reason: text);
      expect(box.bottom, lessThanOrEqualTo(p.size.height + 0.5), reason: text);
    }
  }
  final bounds = p.localToGlobal(Offset.zero) & p.size;
  final card = tester.getRect(tile);
  expect(bounds.left, greaterThanOrEqualTo(card.left));
  expect(bounds.right, lessThanOrEqualTo(card.right));
  expect(bounds.top, greaterThanOrEqualTo(card.top));
  expect(bounds.bottom, lessThanOrEqualTo(card.bottom));
  if (!ink) return bounds;
  return p
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      )
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b))
      .shift(p.localToGlobal(Offset.zero));
}

Future<void> pumpList(
  WidgetTester tester, {
  required double width,
  Match? match,
  bool player = false,
  double scale = 1,
  double? contentWidth,
  List<Match>? matches,
  bool fail = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MatchListsFixture(
      key: UniqueKey(),
      player: player,
      matches: matches ?? [match ?? sampleMatch()],
      fail: fail,
      textScale: scale,
      androidInsets: true,
      contentWidth: contentWidth,
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      final loader = FontLoader('${family}_regular')
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      await loader.load();
    }
  });

  for (final player in [false, true]) {
    for (final width in [360.0, 768.0, 1440.0]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets(
          '${player ? 'player' : 'squad'} $width scale $scale paints complete independent rows',
          (tester) async {
            for (final match in sampleMatches) {
              await pumpList(
                tester,
                width: width,
                match: match,
                player: player,
                scale: scale,
              );
              final home =
                  (match.homeTeam!.name!.trim().isEmpty
                          ? 'Gospodarze'
                          : match.homeTeam!.name!)
                      .toUpperCase();
              final away =
                  (match.awayTeam!.name!.trim().isEmpty
                          ? 'Goście'
                          : match.awayTeam!.name!)
                      .toUpperCase();
              final homeRect = visibleText(tester, home);
              final awayRect = visibleText(tester, away);
              expect(awayRect.top, greaterThan(homeRect.bottom));
              expect(awayRect.left, homeRect.left);
              expect(
                tester.getRect(tile).top,
                greaterThanOrEqualTo(24 + 2 * kToolbarHeight),
              );
              final colors = tester
                  .widgetList<Container>(
                    find.descendant(of: tile, matching: find.byType(Container)),
                  )
                  .where(
                    (c) =>
                        c.decoration is BoxDecoration &&
                        (c.decoration as BoxDecoration).color != null,
                  )
                  .toList();
              expect(colors.map((c) => (c.decoration as BoxDecoration).color), [
                const Color(0xFFE57373),
                const Color(0xFF64B5F6),
              ]);
              for (final (index, rowRect) in [homeRect, awayRect].indexed) {
                final marker = tester.getRect(find.byWidget(colors[index]));
                expect(marker.center.dy, closeTo(rowRect.center.dy, 0.01));
                expect(marker.right, lessThan(rowRect.left));
              }
              if (match.homeScore != null && match.awayScore != null) {
                final homeScore = visibleText(
                  tester,
                  '${match.homeScore}',
                  ink: true,
                );
                final awayScore = visibleText(
                  tester,
                  '${match.awayScore}',
                  ink: true,
                  occurrence: match.homeScore == match.awayScore ? 1 : 0,
                );
                // Glyph metrics can differ from the paragraph center by a
                // fraction of a pixel; the painted scores must stay on-row.
                expect(homeScore.center.dy, closeTo(homeRect.center.dy, 0.5));
                expect(awayScore.center.dy, closeTo(awayRect.center.dy, 0.5));
                expect(homeScore.left, greaterThan(homeRect.right));
                expect(awayScore.left, greaterThan(awayRect.right));
                expect(homeScore.right, closeTo(awayScore.right, 0.5));
                for (final score in [homeScore, awayScore]) {
                  for (final container in tester.widgetList<Container>(
                    find.descendant(of: tile, matching: find.byType(Container)),
                  )) {
                    final decoration = container.decoration;
                    if (decoration is BoxDecoration &&
                        decoration.border != null) {
                      expect(
                        tester
                            .getRect(find.byWidget(container))
                            .overlaps(score),
                        isFalse,
                        reason: 'Scores must not have bordered boxes',
                      );
                    }
                  }
                }
              } else if (['pending', 'partial'].contains(match.matchId)) {
                expect(
                  find.descendant(of: tile, matching: find.text('-')),
                  findsNWidgets(2),
                );
              } else {
                visibleText(tester, 'Nie wybrano jeszcze drużyn');
                expect(
                  find.descendant(of: tile, matching: find.text('-')),
                  findsNothing,
                );
              }
              final date = visibleText(tester, '02.01');
              expect(date.right, lessThan(homeRect.left - 18));
              expect(date.right, lessThan(awayRect.left - 18));
              expect(
                date.center.dy,
                closeTo((homeRect.top + awayRect.bottom) / 2, 0.01),
              );
              expect(find.byTooltip('02.01.2026 18:00'), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
    testWidgets(
      '${player ? 'player' : 'squad'} keeps provider order and whole-card navigation',
      (tester) async {
        final matches = [
          sampleMatch(id: 'third'),
          sampleMatch(id: 'first'),
          sampleMatch(id: 'second'),
        ];
        await pumpList(tester, width: 360, player: player, matches: matches);
        expect(tester.widgetList<MatchTile>(tile).map((t) => t.match.matchId), [
          'third',
          'first',
          'second',
        ]);
        expect(
          find.byType(FloatingActionButton),
          findsNothing,
          reason: 'Member cannot create matches',
        );
        final card = tester.getRect(tile.at(1));
        await tester.tapAt(card.topLeft + const Offset(24, 12));
        await tester.pumpAndSettle();
        expect(find.text('route: original-squad/first'), findsOneWidget);
      },
    );

    testWidgets('${player ? 'player' : 'squad'} keeps empty and error states', (
      tester,
    ) async {
      await pumpList(tester, width: 360, player: player, matches: []);
      expect(find.text('Nie znaleziono meczów.'), findsOneWidget);
      expect(tile, findsNothing);
      await pumpList(tester, width: 360, player: player, fail: true);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tile, findsNothing);
    });

    for (final label in ['GOSPODARZE', 'GOŚCIE', '02.01', '14']) {
      testWidgets(
        '${player ? 'player' : 'squad'} tapping $label preserves route IDs',
        (tester) async {
          await pumpList(tester, width: 360, player: player);
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(
            find.text('route: original-squad/original-match'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('card width selects rows even inside a desktop shell', (
    tester,
  ) async {
    await pumpList(tester, width: 1440, contentWidth: 360);
    expect(
      visibleText(tester, 'GOŚCIE').top,
      greaterThan(visibleText(tester, 'GOSPODARZE').bottom),
    );
  });

  testWidgets('date exposes the full timestamp to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpList(tester, width: 360);
      expect(find.bySemanticsLabel('02.01.2026 18:00'), findsOneWidget);
      expect(find.text('02.01.2026 18:00'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'shell and card breakpoint neighbors do not clip ordinary labels',
    (tester) async {
      for (final width in [599.0, 600.0, 711.0, 712.0, 713.0]) {
        await pumpList(tester, width: width);
        for (final p in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: tile, matching: find.byType(RichText)),
        )) {
          expect(
            p.didExceedMaxLines,
            isFalse,
            reason: 'width $width: ${p.text.toPlainText()}',
          );
        }
      }
    },
  );

  testWidgets('null teams and a partial result retain the unselected state', (
    tester,
  ) async {
    await pumpList(
      tester,
      width: 360,
      scale: 1.6,
      match: Match(
        matchId: 'empty',
        squadId: 'original-squad',
        createdAt: DateTime(2026, 1, 2, 18),
        homeScore: 8,
      ),
    );
    visibleText(tester, 'GOSPODARZE');
    visibleText(tester, 'GOŚCIE');
    visibleText(tester, 'Nie wybrano jeszcze drużyn');
    expect(find.text('8'), findsNothing);
  });
}
