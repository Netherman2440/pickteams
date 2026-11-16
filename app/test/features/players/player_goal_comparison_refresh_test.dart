import 'package:app/features/matches/application/dto/match_details_dto.dart';
import 'package:app/features/matches/application/dto/player_dto.dart';
import 'package:app/features/matches/application/dto/team_dto.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_score_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_teams_usecase.dart';
import 'package:app/features/matches/application/usecases/update_match_team_usecase.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/presentation/controllers/match_details_notifier.dart';
import 'package:app/features/matches/presentation/pages/match_details_page.dart';
import 'package:app/features/matches/presentation/widgets/match_tile.dart';
import 'package:app/features/players/presentation/pages/player_details_page.dart';
import 'package:app/features/players/presentation/pages/player_matches_page.dart';
import 'package:app/features/players/presentation/state/player_matches_provider.dart';
import 'package:app/features/players/presentation/state/player_name_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/goal_comparison_data.dart';
import '../../fixtures/player_details_app.dart';

class ReadMatch extends Mock implements GetMatchUseCase {}

class SaveScore extends Mock implements UpdateMatchScoreUseCase {}

class SaveTeams extends Mock implements UpdateMatchTeamsUseCase {}

class SaveColor extends Mock implements UpdateMatchTeamUseCase {}

MatchDetailsDto details(ProfileFixtureData data) {
  final match = data.goalHistory!.first;
  TeamDto team(bool home) {
    final side = (home ? match.home : match.away)!;
    return TeamDto(
      teamId: home ? 'home' : 'away',
      matchId: 'match',
      color: side.color,
      players: [
        for (final id in side.playerIds)
          PlayerDto(playerId: id, name: id, ranking: 50),
      ],
    );
  }

  return MatchDetailsDto(
    matchId: 'match',
    squadId: 'fixture',
    createdAt: DateTime(2026),
    homeScore: match.homeScore,
    awayScore: match.awayScore,
    homeTeam: team(true),
    awayTeam: team(false),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final edit in ['scores', 'teams', 'colors']) {
    for (final success in [true, false]) {
      testWidgets('profile → real Matches/details → $edit → back; save=$success', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final data = ProfileFixtureData()
          ..goalHistory = [
            goalMatch(),
            goalMatch(homePlayers: ['absent'], homeScore: 2, awayScore: 3),
          ];
        final read = ReadMatch();
        final score = SaveScore();
        final teams = SaveTeams();
        final color = SaveColor();
        void persist() {
          if (!success) throw StateError('Synthetic save rejected');
          data.goalHistory = [
            switch (edit) {
              'scores' => goalMatch(homeScore: 4, awayScore: 4),
              'teams' => goalMatch(
                homePlayers: ['other'],
                awayPlayers: ['player'],
              ),
              _ => goalMatch(homeColor: blue, awayColor: red),
            },
            data.goalHistory!.last,
          ];
        }

        when(
          () => read.execute(matchId: 'match'),
        ).thenAnswer((_) async => details(data));
        when(
          () => score.execute(
            matchId: 'match',
            squadId: 'fixture',
            homeScore: 4,
            awayScore: 4,
          ),
        ).thenAnswer((_) async {
          persist();
          return details(data);
        });
        when(
          () => teams.execute(
            matchId: 'match',
            homePlayerIds: ['other'],
            awayPlayerIds: ['player'],
          ),
        ).thenAnswer((_) async {
          persist();
        });
        when(
          () => color.execute(matchId: 'match', teamId: 'home', color: blue),
        ).thenAnswer((_) async {
          persist();
          return const Team(
            teamId: 'home',
            matchId: 'match',
            side: Side.home,
            color: blue,
          );
        });
        when(
          () => color.execute(matchId: 'match', teamId: 'away', color: red),
        ).thenAnswer(
          (_) async => const Team(
            teamId: 'away',
            matchId: 'match',
            side: Side.away,
            color: red,
          ),
        );
        await tester.pumpWidget(
          PlayerDetailsFixture(
            data: data,
            providerOverrides: [
              getMatchUseCaseProvider.overrideWithValue(read),
              updateMatchScoreUseCaseProvider.overrideWithValue(score),
              updateMatchTeamsUseCaseProvider.overrideWithValue(teams),
              updateMatchTeamUseCaseProvider.overrideWithValue(color),
              playerNameProvider.overrideWith((ref, id) async => 'Jan Testowy'),
              playerMatchesProvider.overrideWith(
                (ref, id) async => [
                  Match(
                    matchId: 'match',
                    squadId: 'fixture',
                    createdAt: DateTime(2026),
                    homeScore: 6,
                    awayScore: 2,
                  ),
                ],
              ),
            ],
            matchesBuilder: (_) =>
                const PlayerMatchesPage(squadId: 'fixture', playerId: 'player'),
            matchRoutes: [
              GoRoute(
                path: '/squads/:squadId/matches/:matchId',
                name: 'matchDetails',
                builder: (_, _) => const MatchDetailsPage(
                  squadId: 'fixture',
                  matchId: 'match',
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final heading = find.text('Drużyna z tym zawodnikiem');
        expect(
          tester.getTopLeft(heading).dy,
          lessThan(
            tester
                .getTopLeft(
                  find.descendant(
                    of: find.byType(PlayerDetailsPage),
                    matching: find.text('Mecze'),
                  ),
                )
                .dy,
          ),
        );
        expect(find.text('+4,00'), findsOneWidget);
        expect(find.text('−1,00'), findsOneWidget);
        expect(data.goalHistoryReads, 1);
        final matchesButton = find.descendant(
          of: find.byType(PlayerDetailsPage),
          matching: find.byIcon(Icons.sports_soccer),
        );
        await tester.ensureVisible(matchesButton);
        await tester.tap(matchesButton);
        await tester.pumpAndSettle();
        expect(find.text('Jan Testowy > Mecze'), findsOneWidget);
        await tester.tap(find.byType(MatchTile));
        await tester.pumpAndSettle();
        expect(find.byType(MatchDetailsPage), findsOneWidget);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MatchDetailsPage)),
        );
        final notifier = container.read(matchDetailsProvider('match').notifier);
        // Exercise the real match controller. Only use-case persistence is fake;
        // this test does not claim to exercise the score/team editor controls.
        switch (edit) {
          case 'scores':
            await notifier.updateScore('fixture', 4, 4);
          case 'teams':
            await notifier.updateTeams(['other'], ['player']);
          case 'colors':
            await notifier.updateTeamsMeta(
              homeTeamId: 'home',
              awayTeamId: 'away',
              homeColor: blue,
              awayColor: red,
            );
        }
        await tester.pumpAndSettle();
        expect(
          container.read(matchDetailsProvider('match')).hasError,
          !success,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        final (scored, conceded) = !success
            ? ('+4,00', '−1,00')
            : switch (edit) {
                'scores' => ('+2,00', '+1,00'),
                'teams' => ('−1,00', '+4,00'),
                _ => ('+3,00', '0,00'),
              };
        expect(find.text(scored), findsOneWidget);
        expect(find.text(conceded), findsOneWidget);
        expect(data.goalHistoryReads, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
