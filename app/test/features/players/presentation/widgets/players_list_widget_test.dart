import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/core/widgets/player_list_row.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/domain/entities/player_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../fixtures/shared_rows_app.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });

  // The ordinary list must center a full name against the ranking+delta
  // block whenever there is no position line, and keep the historical
  // name/position arrangement otherwise, at phone widths and large text.
  const longName = 'Aleksander Konstanty Wiśniewski-Kowalski';
  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final position in ['midfielder', null]) {
        for (final difference in [10.25, -10.25, 0.0]) {
          for (final name in ['Anna', longName]) {
            testWidgets(
              'list row $width/$scale position=$position delta=$difference '
              'name=${name == longName ? 'long' : 'short'}',
              (tester) async {
                tester.view.physicalSize = Size(width, 1000);
                tester.view.devicePixelRatio = 1;
                addTearDown(tester.view.reset);
                final player = Player(
                  playerId: 'delta-player',
                  squadId: 'fixture',
                  name: name,
                  position: position,
                  ranking: 50 + difference,
                  baseRanking: 50,
                  createdAt: DateTime(2026, 1, 1),
                );
                final frameKey = GlobalKey();
                await tester.pumpWidget(
                  RepaintBoundary(
                    key: frameKey,
                    child: SharedRowsFixture(
                      page: 'players',
                      players: [player],
                      textScale: scale,
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                // Optional review artifacts, never fetched or compared remotely.
                final frameDirectory =
                    Platform.environment['PLAYERS_DELTA_FRAMES'];
                if (frameDirectory != null) {
                  await tester.runAsync(() async {
                    final boundary =
                        frameKey.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary;
                    final image = await boundary.toImage();
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    await File(
                      '$frameDirectory/$width-$scale-$position-$difference-'
                      '${name == longName ? 'long' : 'short'}.png',
                    ).writeAsBytes(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
                final row = find.byType(PlayerListRow);
                final ranking = find.text(player.ranking.toStringAsFixed(2));
                final nameFinder = find.text(name);
                expect(row, findsOneWidget);
                expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
                // The name is never capped, shrunk or ellipsized.
                final nameWidget = tester.widget<Text>(nameFinder);
                expect(nameWidget.maxLines, isNull);
                expect(nameWidget.overflow, isNull);
                expect(nameWidget.style!.fontSize, 14);
                for (final element
                    in find
                        .descendant(of: row, matching: find.byType(RichText))
                        .evaluate()) {
                  expect(
                    (element.renderObject! as RenderParagraph)
                        .didExceedMaxLines,
                    isFalse,
                  );
                }
                final nameParagraph = tester.renderObject<RenderParagraph>(
                  nameFinder,
                );
                expect(nameParagraph.didExceedMaxLines, isFalse);
                final namePainter = TextPainter(
                  text: TextSpan(text: name, style: nameWidget.style),
                  textDirection: TextDirection.ltr,
                  textScaler: TextScaler.linear(scale),
                );
                try {
                  namePainter.layout(
                    maxWidth: tester.getSize(nameFinder).width,
                  );
                  expect(
                    namePainter.computeLineMetrics().length,
                    name == longName ? greaterThan(1) : 1,
                  );
                } finally {
                  namePainter.dispose();
                }
                // Horizontal geometry: name left aligned, rating flush right.
                expect(
                  tester.getRect(nameFinder).left,
                  closeTo(tester.getRect(row).left + 4, .01),
                );
                final rankingRect = tester.getRect(ranking);
                final deltaFinder = difference == 0
                    ? null
                    : find.text(
                        '${difference > 0 ? '+' : ''}'
                        '${difference.toStringAsFixed(2)}',
                      );
                if (position == null) {
                  if (difference == 0) {
                    // Plain row: name and ranking share the inline baseline.
                    expect(
                      tester.widget<PlayerListRow>(row).supporting,
                      isNull,
                    );
                    expect(
                      tester.widget<PlayerListRow>(row).rankingSupport,
                      isNull,
                    );
                    expect(
                      tester.getCenter(nameFinder).dy,
                      closeTo(tester.getCenter(ranking).dy, .01),
                    );
                    expect(
                      find.descendant(of: row, matching: find.byType(Icon)),
                      findsNothing,
                    );
                    expect(find.text('+0.00'), findsNothing);
                  } else {
                    // No position: ranking and delta stack into one
                    // right-hand block and the full name centers against it.
                    expect(
                      tester.widget<PlayerListRow>(row).supporting,
                      isNull,
                    );
                    expect(
                      tester.widget<PlayerListRow>(row).rankingSupport,
                      isNotNull,
                    );
                    final delta = deltaFinder!;
                    final deltaRect = tester.getRect(delta);
                    final blockCenter =
                        (rankingRect.top + deltaRect.bottom) / 2;
                    expect(
                      tester.getCenter(nameFinder).dy,
                      closeTo(blockCenter, .5),
                    );
                    expect(deltaRect.right, closeTo(rankingRect.right, .01));
                    expect(deltaRect.top, greaterThan(rankingRect.bottom));
                    final color = difference > 0 ? Colors.green : Colors.red;
                    expect(tester.widget<Text>(delta).style!.color, color);
                    expect(
                      tester.widget<Text>(delta).style!.fontWeight,
                      FontWeight.w600,
                    );
                    final icon = tester.widget<Icon>(
                      find.descendant(
                        of: row,
                        matching: find.byIcon(
                          difference > 0
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
                        ),
                      ),
                    );
                    expect(icon.color, color);
                    expect(icon.size, 16);
                  }
                } else {
                  // With a position the name keeps the inline arrangement and
                  // the supporting line below it.
                  expect(
                    tester.widget<PlayerListRow>(row).supporting,
                    isNotNull,
                  );
                  expect(
                    tester.widget<PlayerListRow>(row).rankingSupport,
                    isNull,
                  );
                  expect(
                    tester.getCenter(nameFinder).dy,
                    closeTo(tester.getCenter(ranking).dy, .01),
                  );
                  final label = find.text(playerPositionPolishLabel(position)!);
                  expect(label, findsOneWidget);
                  expect(
                    tester.getRect(label).left,
                    closeTo(tester.getRect(nameFinder).left, .01),
                  );
                  expect(
                    tester.getRect(label).top,
                    greaterThan(tester.getRect(nameFinder).bottom),
                  );
                  if (difference == 0) {
                    expect(
                      find.descendant(of: row, matching: find.byType(Icon)),
                      findsNothing,
                    );
                  } else {
                    final delta = deltaFinder!;
                    final deltaRect = tester.getRect(delta);
                    expect(deltaRect.right, closeTo(rankingRect.right, .01));
                    expect(deltaRect.top, greaterThan(rankingRect.bottom));
                  }
                }
                expect(tester.takeException(), isNull);
                if (name == longName &&
                    position == null &&
                    difference == 10.25) {
                  await tester.tap(nameFinder);
                  await tester.pumpAndSettle();
                  expect(find.text('Profile: delta-player'), findsOneWidget);
                  expect(tester.takeException(), isNull);
                }
              },
            );
          }
        }
      }
    }
  }
}
