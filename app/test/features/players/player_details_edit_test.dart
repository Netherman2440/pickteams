import 'package:app/features/players/presentation/widgets/edit_player_name_dialog.dart';
import 'package:app/features/players/presentation/widgets/edit_player_position_dialog.dart';
import 'package:app/features/players/presentation/widgets/edit_player_ranking_dialog.dart';
import 'package:app/features/players/presentation/widgets/ranking_history_graph_widget.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../fixtures/player_details_app.dart';

const fields = ['Edytuj nazwę', 'Edytuj ranking', 'Edytuj pozycję'];
Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Future<ProfileFixtureData> mount(
  WidgetTester tester, {
  SquadRole role = SquadRole.owner,
  double width = 1440,
  double scale = 1,
  bool longName = false,
}) async {
  await tester.binding.setSurfaceSize(Size(width, width == 360 ? 640 : 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final data = ProfileFixtureData(longName: longName);
  await tester.pumpWidget(
    PlayerDetailsFixture(data: data, role: role, textScale: scale),
  );
  await tester.pumpAndSettle();
  return data;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> change(WidgetTester tester, int index) async {
  if (index == 2) {
    await tap(tester, find.text('Brak pozycji').last);
    await tap(tester, find.text('Bramkarz').last);
  } else {
    await tester.enterText(
      find.byType(TextField),
      index == 0 ? 'Nowa nazwa' : '62.75',
    );
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final role in [SquadRole.owner, SquadRole.admin]) {
    testWidgets('$role sees one pencil; Done removes edit targets', (
      tester,
    ) async {
      await mount(tester, role: role);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byTooltip('Usuń gracza'), findsOneWidget);
      expect(find.text('Ranking: 59.36'), findsOneWidget);
      expect(find.text('5.36'), findsOneWidget);
      final graph = tester.widget<RankingHistoryGraphWidget>(
        find.byType(RankingHistoryGraphWidget),
      );
      expect(graph.history.every((entry) => entry.change != null), isTrue);
      expect(
        graph.history.fold(
          graph.baseRanking,
          (sum, entry) => sum + entry.change!,
        ),
        closeTo(59.36, 0.000001),
      );
      expect(find.text('Brak zmian rankingu'), findsNothing);
      for (final label in fields) {
        expect(field(label), findsNothing);
      }
      await tap(tester, find.text('Jan Testowy'));
      expect(find.byType(AlertDialog), findsNothing);
      await tap(tester, find.text('Edytuj gracza'));
      expect(find.byIcon(Icons.edit), findsNothing);
      for (final label in fields) {
        expect(field(label), findsOneWidget);
      }
      await tap(tester, find.text('Gotowe'));
      expect(find.byIcon(Icons.edit), findsOneWidget);
      for (final label in fields) {
        expect(field(label), findsNothing);
      }
    });
  }
  for (final role in SquadRole.values.where(
    (r) => r != SquadRole.owner && r != SquadRole.admin,
  )) {
    testWidgets('$role cannot edit or delete', (tester) async {
      await mount(tester, role: role);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byTooltip('Usuń gracza'), findsNothing);
      for (final label in fields) {
        expect(field(label), findsNothing);
      }
      for (final text in [
        'Jan Testowy',
        'Ranking: 59.36',
        'Pozycja: Brak pozycji',
      ]) {
        await tap(tester, find.text(text));
        expect(find.byType(AlertDialog), findsNothing);
      }
    });
  }
  for (var i = 0; i < fields.length; i++) {
    testWidgets('${fields[i]}: whole field, cancel, failed save, retry', (
      tester,
    ) async {
      final data = await mount(tester);
      final original = data.player;
      await tap(tester, find.text('Edytuj gracza'));
      // Tap blank space at the far edge, not only the text.
      final bounds = tester.getRect(field(fields[i]));
      await tester.tapAt(bounds.centerRight - const Offset(12, 0));
      await tester.pumpAndSettle();
      expect(
        find.byType(
          [
            EditPlayerNameDialog,
            EditPlayerRankingDialog,
            EditPlayerPositionDialog,
          ][i],
        ),
        findsOneWidget,
      );
      await change(tester, i);
      await tap(tester, find.text('Anuluj'));
      expect(data.writes, isEmpty);
      expect(data.player, same(original));
      expect(data.reads, 1);
      await tap(tester, field(fields[i]));
      await change(tester, i);
      data.fail = true;
      await tap(tester, find.text('Zapisz'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('Fixture save failed', findRichText: true),
        findsOneWidget,
      );
      expect(data.player, same(original));
      expect(data.reads, 1);
      data.fail = false;
      await tap(tester, find.text('Zapisz'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(data.writes, [
        ['name', 'ranking', 'position'][i],
      ]);
      expect(data.reads, 2);
      expect(find.text('Gotowe'), findsOneWidget);
      expect(
        find.text(['Nowa nazwa', 'Ranking: 62.75', 'Pozycja: Bramkarz'][i]),
        findsOneWidget,
      );
    });
    testWidgets('${fields[i]} supports Tab and keyboard activation', (
      tester,
    ) async {
      await mount(tester);
      final semantics = tester.ensureSemantics();
      await tap(tester, find.text('Edytuj gracza'));
      // Reach the target by actual traversal, without programmatic focus.
      bool focused = false;
      for (var n = 0; n < 25; n++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext != null) {
          focusContext.visitAncestorElements((element) {
            if (element.widget is Semantics &&
                (element.widget as Semantics).properties.label == fields[i]) {
              focused = true;
            }
            return !focused;
          });
        }
        if (focused) break;
      }
      expect(focused, isTrue);
      expect(
        tester.getSemantics(field(fields[i])),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          isFocused: true,
          label:
              '${fields[i]}\n${['Jan Testowy', 'Ranking: 59.36\n5.36', 'Pozycja: Brak pozycji'][i]}',
        ),
      );
      await tester.sendKeyEvent(
        i.isEven ? LogicalKeyboardKey.enter : LogicalKeyboardKey.space,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      semantics.dispose();
    });
  }
  testWidgets('name and ranking still validate before saving', (tester) async {
    final data = await mount(tester);
    await tap(tester, find.text('Edytuj gracza'));
    for (final label in fields.take(2)) {
      await tap(tester, field(label));
      await tester.enterText(find.byType(TextField), '');
      await tap(tester, find.text('Zapisz'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(data.writes, isEmpty);
      await tap(tester, find.text('Anuluj'));
    }
  });
  testWidgets('delete still requires confirmation; cancel keeps profile', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.byTooltip('Usuń gracza'));
    expect(find.text('Usunąć gracza?'), findsOneWidget);
    await tap(tester, find.text('Anuluj'));
    expect(find.text('Jan Testowy'), findsOneWidget);
  });
  for (final (label, destination) in [
    ('Mecze', 'Matches'),
    ('Turnieje', 'Tournaments'),
    ('Statystyki', 'Stats'),
  ]) {
    testWidgets('$label preserves player route parameters', (tester) async {
      await mount(tester);
      final button = find
          .ancestor(of: find.text(label), matching: find.byType(Column))
          .first;
      await tap(
        tester,
        find.descendant(of: button, matching: find.byType(IconButton)),
      );
      expect(find.text('$destination fixture player'), findsOneWidget);
    });
  }
  for (final width in [360.0, 1440.0]) {
    testWidgets('$width long name at 1.6x fits in view and edit mode', (
      tester,
    ) async {
      await mount(tester, width: width, scale: 1.6, longName: true);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Edytuj gracza'));
      for (final label in fields) {
        final rect = tester.getRect(field(label));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        await tap(tester, field(label));
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Anuluj'));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
