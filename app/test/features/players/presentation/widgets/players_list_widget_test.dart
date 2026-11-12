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

  for (final width in [360.0, 1440.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final position in ['midfielder', null]) {
        for (final difference in [10.25, -10.25, 0.0]) {
          testWidgets(
            'ordinary list $width/$scale position=$position delta=$difference',
            (tester) async {
              tester.view.physicalSize = Size(width, 1000);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              const name = 'Aleksander Konstanty Wiśniewski-Kowalski';
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
                    '$frameDirectory/$width-$scale-$position-$difference.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              final row = find.byType(PlayerListRow);
              final ranking = find.text(player.ranking.toStringAsFixed(2));
              final nameFinder = find.text(name);
              expect(row, findsOneWidget);
              expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
              expect(
                tester.getCenter(nameFinder).dy,
                closeTo(tester.getCenter(ranking).dy, 0.01),
              );
              final nameWidget = tester.widget<Text>(nameFinder);
              expect(nameWidget.maxLines, isNull);
              expect(nameWidget.overflow, isNull);
              expect(nameWidget.style!.fontSize, 14);
              for (final element
                  in find
                      .descendant(of: row, matching: find.byType(RichText))
                      .evaluate()) {
                expect(
                  (element.renderObject! as RenderParagraph).didExceedMaxLines,
                  isFalse,
                );
              }
              if (position != null) {
                final label = find.text(playerPositionPolishLabel(position)!);
                expect(label, findsOneWidget);
                expect(
                  tester.getRect(label).left,
                  closeTo(tester.getRect(nameFinder).left, 0.01),
                );
              }
              if (difference == 0) {
                expect(
                  find.descendant(of: row, matching: find.byType(Icon)),
                  findsNothing,
                );
                expect(find.text('+0.00'), findsNothing);
                expect(
                  tester.widget<PlayerListRow>(row).supporting,
                  position == null ? isNull : isNotNull,
                );
              } else {
                final delta = find.text(
                  '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(2)}',
                );
                expect(delta, findsOneWidget);
                expect(
                  tester.getRect(delta).right,
                  closeTo(tester.getRect(ranking).right, 0.01),
                );
                expect(
                  tester.getRect(delta).top,
                  greaterThan(tester.getRect(ranking).bottom),
                );
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
              expect(tester.takeException(), isNull);
              await tester.tap(nameFinder);
              await tester.pumpAndSettle();
              expect(find.text('Profile: delta-player'), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}
