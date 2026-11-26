import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../fixtures/shared_rows_app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/players/domain/entities/player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });

  testWidgets(
    '100 players share one scroll below fixed search; toggles never duplicate',
    (tester) async {
      await _pumpPage(
        tester,
        initialSelectedIds: List.generate(16, (i) => 'p${i + 1}'),
        phone: true,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        lessThan(tester.getTopLeft(find.textContaining('Wybrani gracze')).dy),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final scroll = find.byKey(const ValueKey('selection-scroll'));
      expect(
        find.descendant(of: scroll, matching: find.byType(Scrollable)),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(_sectionCard('Wybrani gracze')).dy,
        lessThan(tester.getTopLeft(_sectionCard('Dostępni gracze')).dy),
      );
      final searchPosition = tester.getTopLeft(find.byType(TextField));
      await tester.scrollUntilVisible(
        find.text('Gracz 100'),
        400,
        scrollable: find.descendant(
          of: scroll,
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Gracz 100').hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.byType(TextField)), searchPosition);
      await tester.tap(find.text('Gracz 100'));
      await tester.pumpAndSettle();
      expect(find.text('Gracz 100'), findsOneWidget);
      expect(_findInSection('Wybrani gracze', 'Gracz 100'), findsOneWidget);
      await tester.ensureVisible(find.text('Gracz 100'));
      await tester.tap(find.text('Gracz 100'));
      await tester.pumpAndSettle();
      expect(find.text('Gracz 100'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Gracz 100'), findsOneWidget);
      await _enterSearchQuery(tester, 'Gracz 100');
      expect(find.text('Wybrani gracze (16)'), findsOneWidget);
      await tester.ensureVisible(find.text('Wyczyść'));
      await tester.tap(find.text('Wyczyść'));
      await tester.pumpAndSettle();
      expect(find.text('Wybrani gracze (0)'), findsOneWidget);
      final generate = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Wygeneruj'),
      );
      expect(generate.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('draft search opens the input connection on entry', (
    tester,
  ) async {
    await _pumpPage(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('draft search filters both selected and available sections', (
    tester,
  ) async {
    await _pumpPage(tester, initialSelectedIds: const ['p2']);

    // Bartek is already selected; typing his name must show him in the
    // "Wybrani" section and no match in "Dostępni".
    await _enterSearchQuery(tester, 'bart');

    expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
    expect(_findInSection('Dostępni gracze', 'Anna'), findsNothing);
    expect(_findInSection('Dostępni gracze', 'Cezary'), findsNothing);
    expect(
      _findInSectionContaining('Dostępni gracze', 'Brak dostępnych graczy'),
      findsOneWidget,
    );

    // A name that matches only an available player.
    await _enterSearchQuery(tester, 'ann');
    expect(_findInSection('Dostępni gracze', 'Anna'), findsOneWidget);
    expect(
      _findInSectionContaining('Wybrani gracze', 'Brak wybranych graczy'),
      findsOneWidget,
    );
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);

    // A name that matches nobody: both sections must report no results.
    await _enterSearchQuery(tester, 'zenek');
    expect(
      _findInSectionContaining('Dostępni gracze', 'Brak dostępnych graczy'),
      findsOneWidget,
    );
    expect(
      _findInSectionContaining('Wybrani gracze', 'Brak wybranych graczy'),
      findsOneWidget,
    );
    expect(find.text('Anna'), findsNothing);
    expect(find.text('Bartek'), findsNothing);
    expect(find.text('Cezary'), findsNothing);

    // Clearing the query restores the unfiltered lists.
    await _enterSearchQuery(tester, '');
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
    expect(_findInSection('Dostępni gracze', 'Anna'), findsOneWidget);
    expect(_findInSection('Dostępni gracze', 'Cezary'), findsOneWidget);
  });

  testWidgets(
    'draft search enter adds auto-highlighted first match and selects phrase',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Anna was added...
      expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Anna'), findsNothing);
      // ...regardless of there being multiple results.
      expect(_findInSection('Dostępni gracze', 'Bartek'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Cezary'), findsOneWidget);

      // Focus stays on the search field with the whole phrase selected.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      final controller = field.controller!;
      expect(controller.text, 'a');
      final selection = controller.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.baseOffset, 0);
      expect(selection.extentOffset, controller.text.length);
    },
  );

  testWidgets(
    'draft search software keyboard done action adds highlighted player',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      // Software keyboards (mobile browsers, on-screen keyboards) submit
      // through the editing-complete action, not hardware key events.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Anna'), findsNothing);

      // Focus stays on the search field with the whole phrase selected.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      final controller = field.controller!;
      expect(controller.text, 'a');
      final selection = controller.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.baseOffset, 0);
      expect(selection.extentOffset, controller.text.length);

      // A repeated submit must not add the next matching player.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
      expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);
      expect(_findInSection('Wybrani gracze', 'Cezary'), findsNothing);
    },
  );

  testWidgets(
    'player tap selects phrase; repeated simulated resumes preserve query and roster',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      // Tap Bartek directly instead of picking with the keyboard.
      // Other matches stay in "Dostępni" afterwards — the exact case
      // where the focus used to stay lost on the tapped tile.
      await tester.tap(_findInSection('Dostępni gracze', 'Bartek'));
      await tester.pumpAndSettle();

      expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Anna'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Cezary'), findsOneWidget);

      // The focus is hard-set back on the search field with the whole
      // phrase selected, no matter how the player was added.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      final controller = field.controller!;
      expect(controller.text, 'a');
      final selection = controller.selection;
      expect(selection.isCollapsed, isFalse);
      expect(selection.baseOffset, 0);
      expect(selection.extentOffset, controller.text.length);

      for (var i = 0; i < 3; i++) {
        _setKeyboardInset(tester, 300);
        await tester.pump();
        await _background(tester);
        expect(field.focusNode!.hasFocus, isFalse);
        await _resume(tester);
        expect(field.focusNode!.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(controller.text, 'a');
        expect(controller.selection, selection);
        expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
        expect(_findInSection('Dostępni gracze', 'Anna'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'pending keyboard intent survives rapid departures until visible acknowledgement',
    (tester) async {
      await _pumpPage(tester, initialSelectedIds: const ['p2']);
      await _enterSearchQuery(tester, 'Anna');
      final field = tester.widget<TextField>(find.byType(TextField));
      const selection = TextSelection(baseOffset: 1, extentOffset: 3);
      field.controller!.selection = selection;
      _setKeyboardInset(tester, 300);
      await tester.pump();
      await _background(tester);

      for (var i = 0; i < 3; i++) {
        _resumeWithoutFrame(tester);
        await _background(tester);
        expect(field.focusNode!.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
      }
      await _resume(tester);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(field.controller!.text, 'Anna');
      expect(field.controller!.selection, selection);
      expect(find.text('Wybrani gracze (1)'), findsOneWidget);

      // Focus is not visibility acknowledgement. Zero metrics can still be
      // from the old background connection before the IME reports visible.
      _setKeyboardInset(tester, 0);
      await tester.pump();
      await _background(tester);
      await _resume(tester);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(field.controller!.text, 'Anna');
      expect(field.controller!.selection, selection);
      expect(find.text('Wybrani gracze (1)'), findsOneWidget);

      expect(_findInSection('Dostępni gracze', 'Anna'), findsOneWidget);
      await _enterSearchQuery(tester, 'Bart');
      expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);

      // Once visible, a settled explicit dismissal cancels the intent.
      _setKeyboardInset(tester, 300);
      await tester.pump();
      tester.testTextInput.hide();
      _setKeyboardInset(tester, 0);
      await tester.pump();
      await _background(tester);
      await _resume(tester);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );

  testWidgets(
    'simulated Back inset collapse stays hidden across resumes; tap reopens',
    (tester) async {
      await _pumpPage(tester, initialSelectedIds: const ['p2']);
      await _enterSearchQuery(tester, 'a');
      final field = tester.widget<TextField>(find.byType(TextField));
      _setKeyboardInset(tester, 300);
      await tester.pump();
      // Simulate the observable Flutter signals, not an Android Back event.
      tester.testTextInput.hide();
      _setKeyboardInset(tester, 0);
      await tester.pump();
      expect(field.focusNode!.hasFocus, isTrue);
      for (var i = 0; i < 3; i++) {
        await _background(tester);
        await _resume(tester);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(field.controller!.text, 'a');
        expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
      }
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );

  testWidgets(
    'settled foreground connection close cancels unacknowledged restore',
    (tester) async {
      await _pumpPage(tester, initialSelectedIds: const ['p2']);
      await _enterSearchQuery(tester, 'Anna');
      _setKeyboardInset(tester, 300);
      await tester.pump();
      await _background(tester);
      await _resume(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      // The request has focus but no positive-inset acknowledgement yet.
      // A settled foreground connection close is cancellation, not a new
      // background transition. This does not model quick native Back ordering.
      tester.testTextInput.closeConnection();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isFalse);
      await _background(tester);
      await _resume(tester);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(field.controller!.text, 'Anna');
      expect(find.text('Wybrani gracze (1)'), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );

  for (final queued in [true, false]) {
    for (final action in ['cover', 'replace', 'dispose']) {
      testWidgets('restore queued=$queued is cancelled by $action', (
        tester,
      ) async {
        await _pumpPage(tester);
        _setKeyboardInset(tester, 300);
        await tester.pump();
        final navigator = Navigator.of(tester.element(find.byType(TextField)));
        await _background(tester);
        _resumeWithoutFrame(tester);
        await _background(tester);
        _resumeWithoutFrame(tester);
        if (!queued) {
          // Focus request issued, but visible insets have not acknowledged it.
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
        }
        final route = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other route')),
        );
        if (action == 'cover') {
          navigator.push<void>(route);
        } else if (action == 'replace') {
          navigator.pushReplacement<void, void>(route);
        } else {
          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        }
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        await _background(tester);
        await _resume(tester);
        expect(tester.testTextInput.isVisible, isFalse);
        if (action == 'cover') {
          navigator.pop();
          await tester.pumpAndSettle();
          await _background(tester);
          await _resume(tester);
          expect(tester.testTextInput.isVisible, isFalse);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
    testWidgets('$platform does not use Android restoration', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpPage(tester);
        _setKeyboardInset(tester, 300);
        await tester.pump();
        final field = tester.widget<TextField>(find.byType(TextField));
        await _background(tester);
        expect(field.focusNode!.hasFocus, isTrue);
        await _resume(tester);
        expect(tester.testTextInput.isVisible, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets(
    'draft search arrow keys navigate results and enter adds highlighted player',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Bartek');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Cezary');

      // Clamped at the last result.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Cezary');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_highlightedPlayerName(tester), 'Bartek');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_findInSection('Wybrani gracze', 'Bartek'), findsOneWidget);
      expect(_findInSection('Dostępni gracze', 'Bartek'), findsNothing);
    },
  );

  testWidgets(
    'draft search picked tile looks like a normal tile (no color override)',
    (tester) async {
      await _pumpPage(tester);

      await _enterSearchQuery(tester, 'a');
      expect(_highlightedPlayerName(tester), 'Anna');

      // Keyboard selection does not change the row background.
      final material = tester.widget<Material>(
        find
            .descendant(
              of: _pickedTileFinder(),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, Colors.transparent);
    },
  );

  testWidgets('draft search enter without highlighted player adds nothing', (
    tester,
  ) async {
    await _pumpPage(tester);

    // Empty query: Enter must not add anyone.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Nie wybrano jeszcze graczy.'), findsOneWidget);

    // After a successful add the highlight resets: pressing Enter again
    // must not add the next matching player.
    await _enterSearchQuery(tester, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_findInSection('Wybrani gracze', 'Anna'), findsOneWidget);
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);
    expect(_findInSection('Wybrani gracze', 'Cezary'), findsNothing);
  });

  testWidgets('draft search query change resets highlight to first match', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _enterSearchQuery(tester, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_highlightedPlayerName(tester), 'Bartek');

    await _enterSearchQuery(tester, 'c');
    expect(_highlightedPlayerName(tester), 'Cezary');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_findInSection('Wybrani gracze', 'Cezary'), findsOneWidget);
    expect(_findInSection('Wybrani gracze', 'Bartek'), findsNothing);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  List<String> initialSelectedIds = const [],
  bool phone = false,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() {
    tester.view.resetViewInsets();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  await tester.binding.setSurfaceSize(
    phone ? const Size(360, 640) : const Size(1800, 1000),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final players = phone
      ? List.generate(
          100,
          (i) => _player('p${i + 1}', 'Gracz ${i + 1}', 40 + i),
        )
      : [
          _player('p1', 'Anna', 40),
          _player('p2', 'Bartek', 41),
          _player('p3', 'Cezary', 42),
        ];

  await tester.pumpWidget(
    SharedRowsFixture(players: players, initialSelectedIds: initialSelectedIds),
  );
  await tester.pumpAndSettle();
}

void _setKeyboardInset(WidgetTester tester, double bottom) {
  tester.view.viewInsets = FakeViewPadding(bottom: bottom);
}

Future<void> _background(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.testTextInput.hide();
  _setKeyboardInset(tester, 0);
  await tester.pump();
}

void _resumeWithoutFrame(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<void> _resume(WidgetTester tester) async {
  _resumeWithoutFrame(tester);
  await tester.pumpAndSettle();
}

Future<void> _enterSearchQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

Finder _sectionCard(String header) {
  return find.byKey(
    ValueKey(
      header == 'Wybrani gracze' ? 'selected-players' : 'available-players',
    ),
  );
}

Finder _findInSection(String header, String text) {
  return find.descendant(of: _sectionCard(header), matching: find.text(text));
}

Finder _findInSectionContaining(String header, String text) {
  return find.descendant(
    of: _sectionCard(header),
    matching: find.textContaining(text),
  );
}

/// Finder for the tile currently picked by keyboard navigation. The
/// picked tile does not change its look, so the auto-scroll GlobalKey
/// is the only remaining marker of the picked position.
Finder _pickedTileFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DraftDraggablePlayerTile && widget.key is LabeledGlobalKey,
  );
}

String? _highlightedPlayerName(WidgetTester tester) {
  final finder = _pickedTileFinder();
  expect(finder, findsOneWidget);
  final tile = tester.widget<DraftDraggablePlayerTile>(finder);
  return tile.player.name;
}

Player _player(String id, String name, int ranking) {
  return Player(
    playerId: id,
    squadId: 'squad-1',
    name: name,
    baseRanking: ranking,
    ranking: ranking.toDouble(),
    createdAt: DateTime(2026, 1, 1),
  );
}
