import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/matches/presentation/widgets/match_player_tile.dart';
import '../../../fixtures/player_lists_app.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      final loader = FontLoader('${family}_regular')
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      await loader.load();
    }
  });
  for (final page in ['match', 'results']) {
    testWidgets('$page shows both eight-player rosters with Android insets', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(PlayerListsFixture(page: page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rows = page == 'match'
          ? find.byType(MatchPlayerTile)
          : find.byType(DraftDraggablePlayerTile);
      expect(rows, findsNWidgets(16));
      for (final element in rows.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(
          rect.bottom,
          lessThanOrEqualTo(616),
          reason: 'Every row must fit above the system inset',
        );
      }
      expect(find.byTooltip('Otwórz nawigację'), findsOneWidget);
    });
  }
}
