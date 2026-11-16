import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/draft/infrastructure/repositories/combinatory_draft_repository.dart';
import 'package:app/features/matches/application/usecases/create_match_usecase.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/tournaments/application/restore_tournament_drafts.dart';
import 'package:app/features/tournaments/application/usecases/accept_tournament_draft_usecase.dart';
import 'package:app/features/tournaments/application/usecases/create_tournament_match_usecase.dart';
import 'package:app/features/tournaments/infrastructure/repositories/supabase_tournament_draft_repository.dart';
import 'package:app/features/tournaments/infrastructure/repositories/supabase_tournament_repository.dart';
import 'package:app/features/players/players_providers.dart';
import '../../../fixtures/snapshot_backend.dart';

void main() {
  setUp(() {
    final subscription = Logger.root.onRecord.listen((record) {
      if (record.level >= Level.SEVERE) {
        printOnFailure('${record.error}\n${record.stackTrace}');
      }
    });
    addTearDown(subscription.cancel);
  });
  for (final count in [4, 5]) {
    for (final substitutes in [false, true]) {
      test(
        'creation A / generation B / reload C / match: $count players, substitutes=$substitutes',
        () async {
          final backend = SnapshotBackend(count: count);
          final container = ProviderContainer(
            overrides: [supabaseProvider.overrideWithValue(backend.client)],
          );
          addTearDown(() async {
            container.dispose();
            await backend.client.dispose();
          });
          backend.tables['tournaments'] = [
            {
              'tournament_id': 'tournament',
              'squad_id': 'fixture',
              'name': 'Synthetic',
              'status': 'drafting',
              'created_at': SnapshotBackend.date,
              'updated_at': SnapshotBackend.date,
            },
          ];
          backend.tables['tournament_teams'] = [
            for (var i = 0; i < 2; i++)
              {
                'tournament_team_id': 't$i',
                'tournament_id': 'tournament',
                'name': 'Team $i',
                'color': '#FFFFFF',
                'created_at': SnapshotBackend.date,
              },
          ];
          backend.tables['tournament_team_players'] = [
            for (var i = 0; i < count; i++)
              {
                'tournament_team_id': i < 2 ? 't0' : 't1',
                'tournament_id': 'tournament',
                'player_id': 'p$i',
              },
          ];
          backend.tables['tournament_drafts'] = [];
          backend.tables['tournament_draft_payloads'] = [];
          for (final row in backend.tables['ranking_history']!) {
            row['match_id'] = null;
            row['tournament_id'] = 'tournament';
          }
          backend.changeCurrentScores();
          final playerRepository = container.read(playerRepositoryProvider);
          final generationPlayers = await playerRepository.getSquadPlayers(
            squadId: 'fixture',
          );
          final proposals = await CombinatoryDraftRepository().createDraft(
            players: generationPlayers,
            teamCount: 2,
            rules: [],
            playWithSubstitute: substitutes,
          );
          final expected = {
            for (final p in generationPlayers) p.playerId: p.ranking,
          };
          expect(expected['p0'], 90);
          final drafts = SupabaseTournamentDraftRepository(backend.client);
          final tournaments = SupabaseTournamentRepository(backend.client);
          final id = await drafts.createCompletedDraft(
            squadId: 'fixture',
            tournamentId: 'tournament',
            selectedPlayerIds: expected.keys.toList(),
            teamCount: 2,
            rules: [],
            proposals: proposals,
            winRateMatrix: {},
            seed: 42,
          );
          final storedRaw =
              backend.tables['tournament_draft_payloads']!.single['proposals']
                  as List;
          expect(storedRaw[1]['rankings'], expected);
          expect(storedRaw[1]['play_with_substitute'], substitutes);
          for (final row in backend.tables['players']!) {
            row['score'] = 12.0;
          }
          for (final loaded in [
            (await drafts.getTournamentDraft(tournamentDraftId: id))!,
            (await drafts.getLatestTournamentDraft(
              tournamentId: 'tournament',
            ))!,
          ]) {
            expect(loaded.seed, 42);
            expect(loaded.inputs.rankings, expected);
            final current = await playerRepository.getSquadPlayers(
              squadId: 'fixture',
            );
            final restored = restoreTournamentDrafts(
              proposals: loaded.proposals,
              playersById: {for (final p in current) p.playerId: p},
            );
            expect(
              restored.first.toStoredProposal(),
              proposals.first.toStoredProposal(),
            );
          }
          await AcceptTournamentDraftUseCase(tournaments, drafts).execute(
            tournamentId: 'tournament',
            tournamentDraftId: id,
            proposalIndex: 0,
          );
          final acceptedTeams = await tournaments.getTournamentTeams(
            tournamentId: 'tournament',
          );
          expect({
            for (final p in acceptedTeams.expand((t) => t.players))
              p.playerId: p.ranking,
          }, expected);
          final created =
              await CreateTournamentMatchUseCase(
                tournaments,
                container.read(createMatchUseCaseProvider),
                drafts,
              ).execute(
                tournamentId: 'tournament',
                homeTournamentTeamId: 't0',
                awayTournamentTeamId: 't1',
              );
          final match = await container
              .read(getMatchUseCaseProvider)
              .execute(matchId: created.matchId);
          expect(match.playWithSubstitute, substitutes);
          expect({
            for (final p in [
              ...match.homeTeam!.players,
              ...match.awayTeam!.players,
            ])
              p.playerId: p.ranking,
          }, expected);
          final proposal = proposals.first;
          for (final (i, team) in [match.homeTeam!, match.awayTeam!].indexed) {
            final other = i == 0 ? match.awayTeam! : match.homeTeam!;
            final actualTotal = effectiveTeamRanking(
              totalRanking: team.players.fold(0.0, (sum, p) => sum + p.ranking),
              teamSize: team.players.length,
              opponentTeamSize: other.players.length,
              playWithSubstitute: match.playWithSubstitute!,
            );
            final expectedTotal = effectiveTeamRanking(
              totalRanking: proposal.teams[i].totalRanking,
              teamSize: proposal.teams[i].players.length,
              opponentTeamSize: proposal.teams[1 - i].players.length,
              playWithSubstitute: substitutes,
            );
            expect(actualTotal, expectedTotal);
          }
          // Creation history A remains intact. Only match inputs contain B.
          expect(backend.tables['ranking_history']!.first['ranking'], 41.25);
          expect(
            backend.tables['ranking_history']!
                .where((r) => r['match_id'] == created.matchId)
                .length,
            count,
          );
          expect(backend.tables['players']!.first['score'], 12.0);
        },
      );
    }
  }
}
