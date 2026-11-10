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

  // Retains the reviewer's 768px reproduction. Check both sides of the shell
  // switch (600), old viewport decision (720), and content decision (792):
  // desktop rail 56 + page padding 16 + compact content threshold 720.
  for (final width in [
    360.0,
    599.0,
    600.0,
    601.0,
    719.0,
    720.0,
    721.0,
    767.0,
    768.0,
    769.0,
    791.0,
    792.0,
    793.0,
    1440.0,
  ]) {
    testWidgets(
      'score display and entry remain available at ${width}px in the real shell',
      (tester) async {
        tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const PlayerListsFixture(page: 'match'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(':'), findsOneWidget);
        final scoreY = tester.getCenter(find.text(':')).dy;
        final teamY = tester.getTopLeft(find.text('Niebiescy')).dy;
        if (width < 792) {
          expect(scoreY, lessThan(teamY));
        } else {
          expect(scoreY, greaterThan(teamY));
        }
        if (width < 792) {
          expect(find.byTooltip('Edytuj składy'), findsNothing);
          expect(find.text('Wprowadź wynik'), findsNothing);
          await tester.tap(find.byTooltip('Akcje meczu'));
          await tester.pumpAndSettle();
        } else {
          expect(find.byTooltip('Akcje meczu'), findsNothing);
          expect(find.byTooltip('Edytuj składy'), findsOneWidget);
          expect(find.byTooltip('Usuń mecz'), findsOneWidget);
        }
        await tester.ensureVisible(find.text('Wprowadź wynik'));
        await tester.tap(find.text('Wprowadź wynik'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Zapisz'), findsOneWidget);
        final inputs = find.byType(TextField);
        expect(
          inputs,
          findsNWidgets(2),
          reason: 'Score editing must expose both score inputs',
        );
        for (final input in [inputs.first, inputs.last]) {
          await tester.ensureVisible(input);
          await tester.pumpAndSettle();
          expect(input.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(input);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(width));
        }
        await tester.enterText(inputs.first, '3');
        await tester.enterText(inputs.last, '2');
        await tester.tap(find.byTooltip('Zapisz'));
        await tester.pumpAndSettle();
        expect(inputs, findsNothing);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text(':'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
