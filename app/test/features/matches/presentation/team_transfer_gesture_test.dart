import 'dart:ui';
import 'package:app/features/matches/application/dto/player_dto.dart';
import 'package:app/features/matches/presentation/widgets/match_player_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../fixtures/player_lists_app.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('empty team target extends to the last opposite player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PlayerListsFixture(
        match: fixtureMatch(
          homeIds: fixturePlayers.take(8).map((p) => p.playerId).toList(),
          awayIds: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Akcje meczu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edytuj składy'));
    await tester.pumpAndSettle();
    final targets = find.byType(DragTarget<Object>);
    expect(targets, findsNWidgets(2));
    expect(
      tester.getSize(targets.at(1)).height,
      tester.getSize(targets.at(0)).height,
    );
  });
  testWidgets('quick touch swipe scrolls instead of starting a transfer', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var starts = 0;
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              MatchPlayerTile(
                player: PlayerDto(
                  playerId: 'p',
                  name: 'Full Player Name',
                  ranking: 50,
                ),
                dragData: 'p',
                onDragStarted: () => starts++,
              ),
              const SizedBox(height: 1800),
            ],
          ),
        ),
      ),
    );
    await tester.drag(
      find.text('Full Player Name'),
      const Offset(0, -180),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
