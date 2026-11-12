import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/core/widgets/player_list_row.dart';
import 'package:app/core/widgets/probability_slider.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';

import '../../../fixtures/lineup_app.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });
  for (final width in [360.0, 1440.0]) {
    testWidgets('read-only missing score stays centered at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        lineupFixture(role: SquadRole.guest, savedScore: false),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Akcje meczu'), findsNothing);
      expect(find.byTooltip('Zapisz'), findsNothing);
      expect(find.text('-'), findsNWidgets(2));
      final center = tester.getRect(find.byType(CustomScrollView)).center.dx;
      expect(tester.getCenter(find.text(':')).dx, closeTo(center, .5));
      expect(
        tester.getCenter(find.textContaining('10.11.2026')).dx,
        closeTo(center, .5),
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('score editing shows each ranking once at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, width == 360 ? 640 : 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(lineupFixture(savedScore: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Akcje meczu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wprowadź wynik'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Zapisz'), findsOneWidget);
      expect(find.textContaining('Ranking:'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
  for (final page in ['results']) {
    for (final count in [8, 11]) {
      testWidgets('$page collapses above $count complete rows in RootShell', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(lineupFixture(page: page, count: count));
        await tester.pumpAndSettle();
        final home = find.byKey(const ValueKey('lineup-home-badge'));
        final away = find.byKey(const ValueKey('lineup-away-badge'));
        final expanded = tester.getSize(home).width;
        Color? color(Finder finder) =>
            (tester.widget<Container>(finder).decoration as BoxDecoration)
                .color;
        final homeColor = color(home);
        final awayColor = color(away);
        expect(expanded, 48);
        expect(homeColor, isNot(awayColor));
        if (page == 'match') {
          expect(homeColor, const Color(0xFF1E88E5));
          expect(awayColor, const Color(0xFFE53935));
        }
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          ),
        );
        scroll.position.jumpTo(page == 'match' ? 48 : 96);
        await tester.pumpAndSettle();
        expect(tester.getSize(home).width, 16);
        expect(color(home), homeColor);
        expect(color(away), awayColor);
        expect(tester.getCenter(home).dx, lessThan(180));
        expect(tester.getCenter(away).dx, greaterThan(180));
        final rows = find.byType(PlayerListRow);
        expect(rows, findsNWidgets(count * 2));
        final headerBottom = tester
            .getRect(find.text(page == 'match' ? 'Niebiescy' : 'Gospodarze'))
            .bottom;
        for (final row in rows.evaluate()) {
          final bounds = tester.getRect(find.byWidget(row.widget));
          expect(bounds.height, greaterThanOrEqualTo(32));
          expect(bounds.top, greaterThanOrEqualTo(headerBottom));
          // Eleven is measured honestly, not made to fit by reducing text.
          if (count == 8) expect(bounds.bottom, lessThanOrEqualTo(640));
        }
        final lastBottom = rows
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)).bottom)
            .reduce((a, b) => a > b ? a : b);
        // ignore: avoid_print
        print(
          '$page $count collapsed last row bottom=$lastBottom viewport=640',
        );
        expect(
          tester.getRect(find.byType(ProbabilitySlider)).top,
          greaterThanOrEqualTo(lastBottom),
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(home.hitTestable(), findsOneWidget);
        expect(away.hitTestable(), findsOneWidget);
        expect(find.byType(ProbabilitySlider).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets(
      '$page long names at 1.6x remain reachable below pinned identity',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          lineupFixture(page: page, count: 11, scale: 1.6, longNames: true),
        );
        await tester.pumpAndSettle();
        for (final row in find.byType(PlayerListRow).evaluate()) {
          final finder = find.byWidget(row.widget);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(finder.hitTestable(), findsOneWidget);
          final text = tester.widget<Text>(
            find.descendant(
              of: finder,
              matching: find.text((row.widget as PlayerListRow).name),
            ),
          );
          expect(text.maxLines, isNull);
          expect(text.style!.fontSize, 14);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
