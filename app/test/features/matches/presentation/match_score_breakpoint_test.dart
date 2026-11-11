import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app/features/matches/presentation/widgets/match_player_tile.dart';
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
        expect(defaultTargetPlatform, TargetPlatform.android);
        tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          PlayerListsFixture(match: fixtureMatch(homeScore: 14, awayScore: 5)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(':'), findsOneWidget);
        final scoreY = tester.getCenter(find.text(':')).dy;
        final teamY = tester.getTopLeft(find.text('Niebiescy')).dy;
        final scoreBounds = tester
            .getRect(find.text('14'))
            .expandToInclude(tester.getRect(find.text('5')));
        final pageCenter = tester
            .getRect(find.byType(CustomScrollView))
            .center
            .dx;
        expect(scoreBounds.center.dx, closeTo(pageCenter, 0.5));
        expect(scoreY, lessThan(teamY));
        expect(
          tester.getCenter(find.textContaining('10.11.2026')).dx,
          closeTo(pageCenter, 0.5),
        );
        expect(find.byTooltip('Edytuj składy'), findsNothing);
        expect(find.byTooltip('Usuń mecz'), findsNothing);
        expect(find.text('Wprowadź wynik'), findsNothing);
        await tester.tap(find.byTooltip('Akcje meczu'));
        await tester.pumpAndSettle();
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
        final inputBounds = tester
            .getRect(inputs.first)
            .expandToInclude(tester.getRect(inputs.last));
        expect(inputBounds.center.dx, closeTo(pageCenter, 0.5));
        await tester.enterText(inputs.first, '14');
        await tester.enterText(inputs.last, '5');
        await tester.tap(find.byTooltip('Zapisz'));
        await tester.pumpAndSettle();
        expect(inputs, findsNothing);
        expect(find.text('14'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.text(':'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 360.0, 393.0, 412.0]) {
    // At 320px enlarged text overflows the existing RootShell title Row.
    // Keep that navigation defect separate from match-header coverage.
    for (final scale in width == 320 ? [1.0] : [1.0, 1.6, 2.0]) {
      for (final scores in [(14, 5), (null, null), (123, 98)]) {
        testWidgets(
          'phone $width scale $scale score $scores with Android keyboard',
          (tester) async {
            expect(defaultTargetPlatform, TargetPlatform.android);
            tester.view.physicalSize = Size(width, 640);
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
            tester.view.viewPadding = const FakeViewPadding(
              top: 24,
              bottom: 24,
            );
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpWidget(
              PlayerListsFixture(
                match: fixtureMatch(homeScore: scores.$1, awayScore: scores.$2),
              ),
            );
            await tester.pumpAndSettle();
            _expectPhoneScore(
              tester,
              width,
              scores.$1?.toString() ?? '-',
              scores.$2?.toString() ?? '-',
            );
            final rows = find.byType(MatchPlayerTile);
            expect(rows, findsNWidgets(16));
            expect(find.text('50.13'), findsOneWidget);
            expect(find.text('60.25'), findsNothing);
            if (width == 360 && scale == 1) {
              tester
                  .state<ScrollableState>(find.byType(Scrollable).last)
                  .position
                  .jumpTo(48);
              await tester.pumpAndSettle();
              for (final row in rows.evaluate()) {
                expect(
                  tester.getRect(find.byWidget(row.widget)).bottom,
                  lessThanOrEqualTo(616),
                  reason: 'The collapsed identity must leave all eight rows visible',
                );
              }
            }
            await tester.tap(find.byTooltip('Akcje meczu'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Wprowadź wynik'));
            await tester.pumpAndSettle();
            final fields = find.byType(TextField);
            expect(fields, findsNWidgets(2));
            final fieldBounds = tester
                .getRect(fields.first)
                .expandToInclude(tester.getRect(fields.last));
            expect(fieldBounds.center.dx, closeTo(width / 2, 0.5));
            final date = tester.getRect(find.textContaining('10.11.2026'));
            expect(date.bottom, lessThanOrEqualTo(fieldBounds.top));
            _expectScoreLabelsBelowDate(tester, date);
            expect(fieldBounds.left, greaterThanOrEqualTo(8));
            expect(fieldBounds.right, lessThanOrEqualTo(width - 8));
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            tester.view.padding = const FakeViewPadding(top: 24);
            for (final (field, value) in [
              (fields.first, '14'),
              (fields.last, '5'),
            ]) {
              await tester.enterText(field, value);
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
              expect(field.hitTestable(), findsOneWidget);
              expect(tester.getRect(field).bottom, lessThanOrEqualTo(360));
            }
            expect(find.byTooltip('Zapisz').hitTestable(), findsOneWidget);
            await tester.tap(find.byTooltip('Zapisz'));
            await tester.pumpAndSettle();
            expect(fields, findsNothing);
            tester.view.viewInsets = const FakeViewPadding();
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
            await tester.pumpAndSettle();
            _expectPhoneScore(tester, width, '14', '5');
            await tester.ensureVisible(rows.last);
            await tester.pumpAndSettle();
            expect(rows.last.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

void _expectScoreLabelsBelowDate(WidgetTester tester, Rect date) {
  for (final text in ['Gospodarze', 'Goście']) {
    final label = find.descendant(
      of: find.byType(TextField),
      matching: find.text(text),
    );
    expect(label, findsOneWidget);
    final box = tester.renderObject<RenderBox>(label);
    final paintedBounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    expect(
      paintedBounds.top,
      greaterThanOrEqualTo(date.bottom),
      reason: 'The floating $text label must not overlap the date',
    );
  }
}

void _expectPhoneScore(
  WidgetTester tester,
  double width,
  String home,
  String away,
) {
  final homeText = find.text(home).first;
  final awayText = find.text(away).last;
  final bounds = tester
      .getRect(homeText)
      .expandToInclude(tester.getRect(awayText));
  expect(bounds.center.dx, closeTo(width / 2, 0.5));
  expect(bounds.left, greaterThanOrEqualTo(8));
  expect(bounds.right, lessThanOrEqualTo(width - 8));
  expect(
    tester.getRect(find.textContaining('10.11.2026')).bottom,
    lessThanOrEqualTo(bounds.top),
  );
  expect(
    bounds.bottom,
    lessThanOrEqualTo(tester.getRect(find.text('Niebiescy')).top),
  );
  expect(tester.takeException(), isNull);
}
