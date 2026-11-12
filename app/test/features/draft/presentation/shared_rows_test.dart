import 'package:app/core/widgets/player_list_row.dart';
import 'package:app/features/matches/application/dto/player_dto.dart';
import 'package:app/features/matches/presentation/widgets/match_player_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../fixtures/shared_rows_app.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });

  testWidgets('compact inline row is 32px; comfortable row has a 48px target', (
    tester,
  ) async {
    var taps = 0;
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PlayerListRow(
                name: 'Anna',
                ranking: 50.125,
                density: PlayerRowDensity.compact,
                onTap: () => taps++,
              ),
              PlayerListRow(
                name: 'Bartek',
                ranking: 51,
                density: PlayerRowDensity.comfortable,
                leading: const Icon(Icons.check_circle),
                trailing: IconButton(
                  tooltip: 'Remove',
                  onPressed: () => actions++,
                  icon: const Icon(Icons.remove),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PlayerListRow).first).height, 32);
    expect(
      tester.getCenter(find.text('Anna')).dy,
      tester.getCenter(find.text('50.13')).dy,
    );
    expect(
      tester.getSize(find.byType(PlayerListRow).last).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('Anna'));
    await tester.tap(find.byTooltip('Remove'));
    expect(taps, 1);
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow compact row wraps full long name at 1.6x with snapshot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final name = sharedRowsPlayers.first.name;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 170,
                child: MatchPlayerTile(
                  player: PlayerDto(playerId: 'p1', name: name, ranking: 88),
                  snapshotRanking: 50.125,
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text(name), findsOneWidget);
    expect(find.text('50.13'), findsOneWidget);
    expect(find.text('88.00'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(name))), findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(name), matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(find.byType(PlayerListRow)).height, greaterThan(32));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final width in [360.0, 1440.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'RootShell selection $width at $scale keeps full names reachable',
        (tester) async {
          tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(SharedRowsFixture(textScale: scale));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Otwórz nawigację'), findsOneWidget);
          expect(find.text(sharedRowsPlayers.first.name), findsOneWidget);
          await tester.ensureVisible(find.text('Gracz 100'));
          await tester.pumpAndSettle();
          expect(find.text('Gracz 100').hitTestable(), findsOneWidget);
          expect(find.byType(TextField).hitTestable(), findsOneWidget);
          for (final element
              in find
                  .descendant(
                    of: find.byType(PlayerListRow),
                    matching: find.byType(RichText),
                  )
                  .evaluate()) {
            expect(
              (element.renderObject! as RenderParagraph).didExceedMaxLines,
              isFalse,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'selection load failure shows error without stale rows or actions',
    (tester) async {
      await tester.pumpWidget(
        const SharedRowsFixture(error: 'Synthetic load failure'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic load failure'), findsOneWidget);
      expect(find.byType(PlayerListRow), findsNothing);
      expect(find.text('Wygeneruj'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
