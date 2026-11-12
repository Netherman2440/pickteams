import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/core/widgets/player_list_row.dart';
import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/matches/presentation/widgets/match_view_roster.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
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
    testWidgets('$page keeps both rosters reachable with Android insets', (
      tester,
    ) async {
      await _pump(tester, page);
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(page == 'match' ? 48 : 96);
      await tester.pumpAndSettle();
      final rows = _rows(page);
      expect(rows, findsNWidgets(16));
      for (final element in rows.evaluate()) {
        final widget = element.widget;
        final row = widget is MatchViewPlayerPanel
            ? find.byWidgetPredicate(
                (candidate) =>
                    candidate is MatchViewPlayerPanel &&
                    candidate.player.playerId == widget.player.playerId,
              )
            : find.byWidget(widget);
        if (page == 'match') {
          // Full two-line panels need scrolling; the old all-eight-at-once
          // assertion conflicts with the approved full-name layout.
          await Scrollable.ensureVisible(tester.element(row), alignment: 1);
          await tester.pumpAndSettle();
        }
        final rect = tester.getRect(row);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(
          rect.top,
          greaterThanOrEqualTo(128),
        ); // status + shell + feature header
        expect(
          rect.bottom,
          lessThanOrEqualTo(616),
          reason: 'Every complete row must be reachable above the system inset',
        );
      }
      expect(find.byTooltip('Otwórz nawigację'), findsOneWidget);
      if (page == 'match') {
        expect(
          tester.getRect(find.text('Niebiescy')).right,
          lessThanOrEqualTo(tester.getRect(rows.first).right),
        );
        expect(
          tester.getRect(find.text('Czerwoni')).left,
          greaterThanOrEqualTo(tester.getRect(rows.last).left),
        );
        expect(
          find.text('50.13'),
          findsOneWidget,
        ); // historical snapshot, not today's 60.25
        expect(find.text('60.25'), findsNothing);
      } else {
        expect(find.text('Zakceptuj propozycję').hitTestable(), findsOneWidget);
      }
      _expectUnclipped(tester);
    });
    testWidgets('$page enlarged names wrap and final rows remain reachable', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, page);
      final last = _rows(page).last;
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(last).dy, lessThanOrEqualTo(616));
      _expectUnclipped(tester);
    });
  }
  for (final width in [320.0, 1440.0, 2560.0]) {
    for (final (page, bound) in [
      ('selection', 600.0),
      ('results', 900.0),
      ('match', 1000.0),
    ]) {
      testWidgets(
        '$page at $width stays bounded and has no horizontal overflow',
        (tester) async {
          await _pump(
            tester,
            page,
            size: Size(width, width < 600 ? 640 : 1000),
          );
          final panel = find.byWidgetPredicate(
            (w) => w is ConstrainedBox && w.constraints.maxWidth == bound,
          );
          expect(panel, findsOneWidget);
          expect(tester.getSize(panel).width, lessThanOrEqualTo(bound));
          for (final element
              in find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is PlayerListRow ||
                        widget is MatchViewPlayerPanel,
                  )
                  .evaluate()) {
            final row = find.byWidget(element.widget);
            final rect = tester.getRect(row);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            if (width > 600) {
              final texts = find.descendant(
                of: row,
                matching: find.byType(Text),
              );
              expect(
                tester.getCenter(texts.first).dy,
                closeTo(tester.getCenter(texts.at(1)).dy, 1),
              );
            }
          }
          _expectUnclipped(tester);
        },
      );
    }
  }
  testWidgets('phone selection removes, searches, adds and generates', (
    tester,
  ) async {
    final writes = FixtureWrites();
    await _pump(tester, 'selection', writes: writes);
    expect(find.text('Wybrani gracze (16)'), findsOneWidget);
    await tester.tap(find.text('Michał Kowalski'));
    await tester.pumpAndSettle();
    expect(find.text('Wybrani gracze (15)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Michał');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Wybrani gracze (16)'), findsOneWidget);
    await tester.tap(find.text('Wygeneruj'));
    await tester.pumpAndSettle();
    expect(find.text('Propozycja 1 z 2'), findsOneWidget);
    expect(writes.acceptances, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('proposal navigation, drag and acceptance use the actual page', (
    tester,
  ) async {
    final writes = FixtureWrites();
    await _pump(tester, 'results', writes: writes);
    final firstName = find.text('Michał Kowalski');
    expect(tester.getCenter(firstName).dx, lessThan(180));
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('Propozycja 2 z 2'), findsOneWidget);
    expect(tester.getCenter(firstName).dx, greaterThan(180));
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await _drag(tester, firstName, find.text('Adam Dąbrowski'));
    expect(tester.getCenter(firstName).dx, greaterThan(180));
    await tester.tap(find.text('Zakceptuj propozycję'));
    await tester.pumpAndSettle();
    expect(find.byType(MatchDetailsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('lineup-home-badge')), findsOneWidget);
    expect(writes.acceptances, 1);
    expect(writes.homeIds, hasLength(7));
    expect(writes.awayIds, hasLength(9));
    expect(writes.awayIds, contains('p0'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'match team drag, redraft, rematch and player navigation remain available',
    (tester) async {
      await _pump(tester, 'match');
      await tester.tap(find.byTooltip('Akcje meczu'));
      await tester.pumpAndSettle();
      for (final label in [
        'Wylosuj jeszcze raz',
        'Rewanż',
        'Podgląd propozycji',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      await tester.tap(find.text('Rewanż'));
      await tester.pumpAndSettle();
      expect(find.text('Czy chcesz utworzyć rewanż?'), findsOneWidget);
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Akcje meczu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wylosuj jeszcze raz'));
      await tester.pumpAndSettle();
      expect(
        find.text('Czy chcesz jeszcze raz wylosować składy?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Akcje meczu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edytuj składy'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Michał Kowalski'));
      await _drag(
        tester,
        find.text('Michał Kowalski'),
        find.text('Adam Dąbrowski'),
      );
      expect(
        tester.getCenter(find.text('Michał Kowalski')).dx,
        greaterThan(180),
      );
      await tester.tap(find.byTooltip('Zapisz'));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.text('Michał Kowalski')).dx,
        greaterThan(180),
      );
      await tester.tap(find.text('Michał Kowalski'));
      await tester.pumpAndSettle();
      expect(find.text('Fake player destination'), findsOneWidget);
      expect(find.text('p0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'read-only match hides management but preserves player navigation',
    (tester) async {
      await _pump(tester, 'match', role: SquadRole.none);
      expect(find.byTooltip('Akcje meczu'), findsNothing);
      expect(find.byTooltip('Edytuj składy'), findsNothing);
      expect(find.byTooltip('Usuń mecz'), findsNothing);
      expect(find.text('Wprowadź wynik'), findsNothing);
      expect(find.text('Rewanż'), findsNothing);
      await tester.tap(find.text('Michał Kowalski'));
      await tester.pumpAndSettle();
      expect(find.text('Fake player destination'), findsOneWidget);
    },
  );
}

Finder _rows(String page) => page == 'match'
    ? find.byType(MatchViewPlayerPanel)
    : find.byType(DraftDraggablePlayerTile);

Future<void> _pump(
  WidgetTester tester,
  String page, {
  Size size = const Size(360, 640),
  SquadRole role = SquadRole.owner,
  FixtureWrites? writes,
}) async {
  expect(defaultTargetPlatform, TargetPlatform.android);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PlayerListsFixture(page: page, role: role, writes: writes),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void _expectUnclipped(WidgetTester tester) {
  for (final element
      in find
          .descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is PlayerListRow || widget is MatchViewPlayerPanel,
            ),
            matching: find.byType(RichText),
          )
          .evaluate()) {
    expect(
      (element.renderObject! as RenderParagraph).didExceedMaxLines,
      isFalse,
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> _drag(WidgetTester tester, Finder from, Finder to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pumpAndSettle();
}
