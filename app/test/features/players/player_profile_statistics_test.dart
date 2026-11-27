import 'package:app/core/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:app/features/players/presentation/widgets/ranking_history_viewport.dart';
import 'package:app/features/players/domain/entities/player_head_to_head_stat.dart';
import 'package:app/features/players/domain/entities/ranking_history_entry.dart';
import 'package:app/features/players/presentation/widgets/player_head_to_head_table.dart';
import 'package:app/features/players/presentation/widgets/ranking_history_graph_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../fixtures/player_profile_app.dart';
import 'package:app/features/players/presentation/pages/player_matches_page.dart';
import 'package:app/features/players/presentation/pages/player_stats_page.dart';
import 'package:app/features/players/presentation/pages/player_tournaments_page.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> size(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final dark in [true, false]) {
      testWidgets(
        'continuous window, precise ID-free readout and live pan at $width dark=$dark',
        (tester) async {
          await size(tester, width);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              home: Scaffold(
                body: RankingHistoryGraphWidget(
                  baseRanking: 1,
                  history: [
                    for (var i = 1; i <= 14; i++)
                      RankingHistoryEntry(
                        rankingHistoryId: '$i',
                        playerId: 'p',
                        matchId: 'match-$i',
                        ranking: 60 + i.toDouble(),
                        change: .125,
                        createdAt: DateTime(2026, 1, i),
                      ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Mecze 3–14 z 14'), findsOneWidget);
          expect(find.text('14.01.2026 · 74.13 pkt'), findsOneWidget);
          final plot = find.byKey(const ValueKey('ranking-plot'));
          final gesture = await tester.startGesture(tester.getCenter(plot));
          await gesture.moveBy(const Offset(25, 0));
          await tester.pump();
          await gesture.moveBy(Offset(width / 4, 0));
          await tester.pump();
          // The held finger must change the viewport before pointer-up.
          expect(find.text('Mecze 3–14 z 14'), findsNothing);
          await gesture.up();
          await tester.sendKeyEvent(LogicalKeyboardKey.home);
          await tester.pump();
          expect(find.text('Mecze 1–12 z 14'), findsOneWidget);
          await tester.tap(find.byTooltip('Poprzedni punkt'));
          await tester.pump();
          expect(find.text('11.01.2026 · 71.13 pkt'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.end);
          await tester.pump();
          expect(find.text('Mecze 3–14 z 14'), findsOneWidget);
          expect(find.textContaining('match-'), findsNothing);
          final semantics = tester.ensureSemantics();
          expect(
            find.bySemanticsLabel(RegExp('match-|Mecz [0-9]')),
            findsNothing,
          );
          semantics.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('empty and one-match history do not invent a base point', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RankingHistoryGraphWidget(history: [], baseRanking: 54),
      ),
    );
    expect(find.text('Brak zmian rankingu'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RankingHistoryGraphWidget(
            history: [
              RankingHistoryEntry(
                rankingHistoryId: 'h',
                playerId: 'p',
                ranking: 54.123,
                change: 0,
                createdAt: DateTime(2026),
              ),
            ],
            baseRanking: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mecze 1–1 z 1'), findsOneWidget);
    expect(find.textContaining('54.12 pkt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'viewport bounds, anchored zoom and latest preserve scale for all sizes',
    () {
      for (final count in [0, 1, 2, 3, 4, 14, 1000]) {
        final view = RankingHistoryViewport(count);
        view.pan(-100000);
        expect(view.start, 0);
        view.pan(100000);
        expect(view.end, view.last);
        view.reset();
        const fraction = .3;
        final anchor = view.start + fraction * view.span;
        view.zoom(.8, fraction);
        expect(view.start + fraction * view.span, closeTo(anchor, .000001));
        view.zoom(.000001, fraction);
        expect(view.span, view.minSpan);
        view.latest();
        expect(view.end, view.last);
        expect(view.span, view.minSpan);
        view.zoom(100000, fraction);
        expect(view.span, view.last);
        expect(view.start, 0);
      }
    },
  );

  testWidgets(
    'pinch in/out, anchored wheel, trackpad, resize and high text with irregular reversed dates',
    (tester) async {
      await size(tester, 390);
      final history = [
        for (var i = 0; i < 64; i++)
          RankingHistoryEntry(
            rankingHistoryId: 'history-secret-$i',
            playerId: 'p',
            matchId: 'uuid-secret-$i',
            ranking: 50 + i / 10,
            change: .001,
            createdAt: DateTime(2026, 1, 1).add(Duration(days: i * i)),
          ),
      ].reversed.toList();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: RankingHistoryGraphWidget(
                  history: history,
                  baseRanking: 999,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final plot = find.byKey(const ValueKey('ranking-plot'));
      String range() => tester
          .widgetList<Text>(find.byType(Text))
          .map((e) => e.data ?? '')
          .firstWhere((e) => e.startsWith('Mecze '));
      expect(range(), 'Mecze 53–64 z 64');
      final center = tester.getCenter(plot);
      final a = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final b = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await a.moveBy(const Offset(-20, 0));
      await b.moveBy(const Offset(20, 0));
      await tester.pump();
      await a.moveBy(const Offset(-20, 0));
      await b.moveBy(const Offset(20, 0));
      await tester.pump();
      final zoomed = range();
      expect(zoomed, isNot('Mecze 53–64 z 64'));
      await a.moveBy(const Offset(30, 0));
      await b.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(range(), isNot(zoomed));
      await a.up();
      await b.up();
      final beforeWheel = range();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      expect(range(), isNot(beforeWheel));
      final beforeTrackpad = range();
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(center);
      await trackpad.panZoomUpdate(center, pan: const Offset(25, 0));
      await tester.pump();
      await trackpad.panZoomUpdate(center, pan: const Offset(100, 0));
      await tester.pump();
      await trackpad.panZoomUpdate(center, pan: const Offset(180, 0));
      await tester.pump();
      expect(range(), isNot(beforeTrackpad));
      await trackpad.panZoomEnd();
      tester.view.physicalSize = const Size(900, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('secret|uuid|history-')),
        findsNothing,
      );
      expect(find.textContaining('secret'), findsNothing);
      await tester.tap(find.byTooltip('Następny punkt'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final count in [0, 1, 14]) {
      testWidgets(
        'real pages, cards, back, all metrics and empty states $width/$count',
        (tester) async {
          await size(tester, width);
          await tester.pumpWidget(
            PlayerProfileFixture(count: count, longName: true),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final statsCard = find.bySemanticsLabel(
            'Otwórz pełne statystyki zawodnika',
          );
          await tester.ensureVisible(statsCard);
          await tester.tap(statsCard);
          await tester.pumpAndSettle();
          expect(find.byType(PlayerStatsPage), findsOneWidget);
          for (final label in [
            'Ranking bazowy',
            'Aktualny ranking',
            'Liczba meczów',
            'Liczba zwycięstw',
            'Liczba remisów',
            'Liczba porażek',
            'Aktualna seria zwycięstw',
            'Aktualna seria porażek',
            'Najdłuższa seria zwycięstw',
            'Najdłuższa seria porażek',
            'Strzelone gole',
            'Stracone gole',
            'Średnio strzelonych goli na mecz',
            'Średni wynik (strzelone : stracone)',
            'Bezpośrednie pojedynki',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.ensureVisible(find.text('Bezpośrednie pojedynki'));
          await tester.pumpAndSettle();
          if (count == 0) {
            expect(
              find.text('Brak statystyk bezpośrednich pojedynków.'),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
          final matchesCard = find.bySemanticsLabel(
            'Otwórz wszystkie mecze zawodnika',
          );
          await tester.ensureVisible(matchesCard);
          await tester.tap(matchesCard);
          await tester.pumpAndSettle();
          expect(find.byType(PlayerMatchesPage), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Turnieje'));
          await tester.tap(find.text('Turnieje'));
          await tester.pumpAndSettle();
          expect(find.byType(PlayerTournamentsPage), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.brightness_6));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'both modes retain all measures, sorting and pinned row labels at $width',
      (tester) async {
        await size(tester, width);
        var column = HeadToHeadColumn.togetherMatches;
        var ascending = false;
        final rows = [
          for (var i = 1; i <= 3; i++)
            PlayerHeadToHeadStat.fromMap({
              'other_player_id': '$i',
              'other_name': [
                'Anna',
                'Borys',
                'Celina o bardzo długim nazwisku',
              ][i - 1],
              for (final mode in ['together', 'vs']) ...{
                '${mode}_matches': i * 10,
                '${mode}_wins': i * (i + 1),
                '${mode}_draws': i,
                '${mode}_losses': i * 10 - i * (i + 1) - i,
                '${mode}_goals_for': i * 25,
                '${mode}_goals_against': i * 15,
              },
            }),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => PlayerHeadToHeadTable(
                  stats: rows,
                  sortColumn: column,
                  sortAscending: ascending,
                  onSort: (c, a) => setState(() {
                    column = c;
                    ascending = a;
                  }),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        double y(String name) => tester.getTopLeft(find.text(name)).dy;
        void order(bool asc) => expect(
          y('Anna'),
          asc ? lessThan(y('Borys')) : greaterThan(y('Borys')),
        );
        order(false);
        for (final against in [false, true]) {
          if (against) {
            await tester.tap(find.text('Przeciwko'));
            await tester.pumpAndSettle();
            expect(column, HeadToHeadColumn.vsMatches);
            expect(ascending, false);
          }
          final columns = HeadToHeadColumn.values.where(
            (c) =>
                c == HeadToHeadColumn.player ||
                (against
                    ? c.index >= HeadToHeadColumn.vsMatches.index
                    : c.index <= HeadToHeadColumn.togetherGoalsAgainst.index),
          );
          for (final c in columns) {
            final label = c == HeadToHeadColumn.player
                ? 'Gracz'
                : '${against ? 'Przeciwko' : 'Razem'} ${['mecze', 'wygrane', 'remisy', 'porażki', '% zwycięstw', '% porażek', 'gole strzelone', 'gole stracone'][(c.index - (against ? 9 : 1))]}';
            final header = find.text(
              label.replaceFirst(RegExp(r'^(Razem|Przeciwko) '), ''),
            );
            await tester.ensureVisible(header);
            await tester.pumpAndSettle();
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(column, c);
            final firstDirection = ascending;
            final reverseValues =
                c == HeadToHeadColumn.togetherLossRate ||
                c == HeadToHeadColumn.vsLossRate;
            order(reverseValues ? !ascending : ascending);
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(ascending, !firstDirection);
            order(reverseValues ? !ascending : ascending);
          }
          final nameLeft = tester.getTopLeft(find.text('Anna')).dx;
          expect(nameLeft, greaterThanOrEqualTo(0));
          expect(nameLeft, lessThan(width));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
