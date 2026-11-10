import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

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

  testWidgets('narrow real page has one closed menu and all open actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const PlayerListsFixture());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Akcje meczu'), findsOneWidget);
    expect(find.byTooltip('Edytuj składy'), findsNothing);
    expect(find.byTooltip('Usuń mecz'), findsNothing);
    expect(find.text('Wprowadź wynik'), findsNothing);
    expect(find.text('Podgląd propozycji'), findsNothing);
    expect(find.text('Wylosuj jeszcze raz'), findsNothing);
    expect(find.text('Rewanż'), findsNothing);
    await tester.tap(find.byTooltip('Akcje meczu'));
    await tester.pumpAndSettle();
    for (final label in [
      'Edytuj składy',
      'Usuń mecz',
      'Wprowadź wynik',
      'Podgląd propozycji',
      'Wylosuj jeszcze raz',
      'Rewanż',
    ]) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
