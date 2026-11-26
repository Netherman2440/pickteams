import 'package:app/core/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
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
        'six-match window, stored snapshot, gesture and keyboard at $width dark=$dark',
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
          expect(find.text('Mecze 9–14 z 14'), findsOneWidget);
          expect(find.textContaining('74.13 pkt'), findsOneWidget);
          await tester.tap(find.byTooltip('Wcześniejsze mecze'));
          await tester.pumpAndSettle();
          expect(find.text('Mecze 3–8 z 14'), findsOneWidget);
          await tester.tap(find.text('03.01'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Mecz match-3 · 03.01.2026 · 63.13 pkt'),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
          expect(find.text('Mecze 1–6 z 14'), findsOneWidget);
          await tester.fling(
            find.byType(LineChart),
            const Offset(-240, 0),
            1000,
          );
          await tester.pumpAndSettle();
          expect(find.text('Mecze 7–12 z 14'), findsOneWidget);
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
