import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/presentation/widgets/match_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../fixtures/match_lists_app.dart';

Finder get tile => find.byType(MatchTile);

RenderParagraph paragraph(WidgetTester tester, String text) => tester
    .renderObjectList<RenderParagraph>(
      find.descendant(of: tile, matching: find.byType(RichText)),
    )
    .singleWhere((p) => p.text.toPlainText() == text);

// Text presence is not visibility: check every laid-out glyph box, overflow,
// and the painted paragraph's global bounds against the actual card.
Rect visibleText(WidgetTester tester, String text) {
  final p = paragraph(tester, text);
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
  return bounds;
}

Future<void> pumpList(
  WidgetTester tester, {
  required double width,
  Match? match,
  bool player = false,
  double scale = 1,
  double? contentWidth,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previous = FlutterError.onError;
  final shellErrors = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    // Existing branding Row overflows at 320/1.6. Branding is owned by
    // another slice. Allow only that verified error, never a card error.
    if (width == 320 &&
        scale == 1.6 &&
        details.toString().contains('root_shell.dart:281:19') &&
        details.exceptionAsString().contains('overflowed by 13 pixels')) {
      shellErrors.add(details);
    } else {
      previous?.call(details);
    }
  };
  await tester.pumpWidget(
    MatchListsFixture(
      key: UniqueKey(),
      player: player,
      matches: [match ?? sampleMatch()],
      textScale: scale,
      androidInsets: true,
      contentWidth: contentWidth,
    ),
  );
  await tester.pumpAndSettle();
  FlutterError.onError = previous;
  expect(shellErrors.length, width == 320 && scale == 1.6 ? 1 : 0);
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
    for (final width in [320.0, 360.0, 390.0]) {
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
              if (match.homeScore != null) {
                final homeScore = visibleText(tester, '${match.homeScore}');
                final awayScore = visibleText(tester, '${match.awayScore}');
                expect(homeScore.center.dy, closeTo(homeRect.center.dy, 0.01));
                expect(awayScore.center.dy, closeTo(awayRect.center.dy, 0.01));
                expect(homeScore.left, greaterThan(homeRect.right));
                expect(awayScore.left, greaterThan(awayRect.right));
                expect(homeScore.center.dx, closeTo(awayScore.center.dx, 0.01));
              } else if (match.matchId == 'pending') {
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
              visibleText(tester, '02.01.2026 18:00');
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
    for (final label in ['GOSPODARZE', 'GOŚCIE']) {
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

  testWidgets('desktop retains the horizontal title and score pair', (
    tester,
  ) async {
    await pumpList(tester, width: 1440);
    final title = tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: tile, matching: find.byType(RichText)),
        )
        .singleWhere((p) => p.text.toPlainText().contains('GOSPODARZE'));
    expect(title.text.toPlainText(), contains('GOŚCIE'));
    expect(title.didExceedMaxLines, isFalse);
    final home = visibleText(tester, '14');
    final away = visibleText(tester, '5');
    expect(home.center.dy, away.center.dy);
    expect(away.left, greaterThan(home.right));
    expect(find.text(':'), findsOneWidget);
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
      width: 320,
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
