import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/matches/domain/repositories/match_repository.dart';
import 'package:app/features/matches/domain/repositories/team_repository.dart';
import 'package:app/features/matches/matches_providers.dart';
import 'package:app/features/players/domain/repositories/player_repository.dart';
import 'package:app/features/players/domain/repositories/ranking_repository.dart';
import 'package:app/features/players/players_providers.dart';

class UpdateMatchTeamsUseCase {
  final MatchRepository _matchRepository;
  final TeamRepository _teamRepository;
  final RankingRepository _rankingRepository;
  final PlayerRepository _playerRepository;

  UpdateMatchTeamsUseCase(
    this._matchRepository,
    this._teamRepository,
    this._rankingRepository,
    this._playerRepository,
  );

  Future<void> execute({
    required String matchId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
  }) async {
    // 1. Get current match
    final match = await _matchRepository.getMatch(matchId: matchId);

    // Check if match has score
    if (match.homeScore != null || match.awayScore != null) {
      throw Exception('Cannot update teams for a match with score');
    }

    // 2. Fetch current players (before update) to diff ranking history entries
    final currentTeams = await _teamRepository.getMatchTeams(matchId);
    final currentPlayers = [for (final team in currentTeams) ...team.players];
    final currentPlayerIds = currentPlayers.map((p) => p.playerId).toSet();

    final newPlayerIds = {...homePlayerIds, ...awayPlayerIds};
    if (match.scoreMeta.containsKey('draft_rankings')) {
      // New tournament matches store inputs without ranking-history events.
      // Transfers retain inputs. A removed/re-added player gets an addition
      // input, just like the regular match history path below.
      final rankings = <String, double>{
        for (final player in currentPlayers)
          if (newPlayerIds.contains(player.playerId))
            player.playerId: player.ranking,
      };
      final addedPlayers = await Future.wait(
        newPlayerIds
            .difference(currentPlayerIds)
            .map((id) => _playerRepository.getPlayer(playerId: id)),
      );
      for (final player in addedPlayers) {
        rankings[player.playerId] = player.ranking;
      }
      await _teamRepository.updateMatchTeams(
        matchId: matchId,
        homePlayerIds: homePlayerIds,
        awayPlayerIds: awayPlayerIds,
      );
      await _matchRepository.updateMatchScore(
        matchId: matchId,
        scoreMeta: {...match.scoreMeta, 'draft_rankings': rankings},
      );
      await _matchRepository.refreshMatchWinProbability(matchId: matchId);
      return;
    }

    // 3. Update teams
    await _teamRepository.updateMatchTeams(
      matchId: matchId,
      homePlayerIds: homePlayerIds,
      awayPlayerIds: awayPlayerIds,
    );

    await _matchRepository.refreshMatchWinProbability(matchId: matchId);

    // Identify Added Players
    final addedIds = newPlayerIds.difference(currentPlayerIds);
    if (addedIds.isNotEmpty) {
      final existingEntries = await Future.wait(
        addedIds.map(
          (id) async => MapEntry(
            id,
            await _rankingRepository.getRankingHistoryEntryByMatch(
              matchId: matchId,
              playerId: id,
            ),
          ),
        ),
      );
      final missingEntryIds = {
        for (final entry in existingEntries)
          if (entry.value == null) entry.key,
      };

      if (missingEntryIds.isNotEmpty) {
        final addedPlayersFutures = missingEntryIds.map(
          (id) => _playerRepository.getPlayer(playerId: id),
        );
        final addedPlayers = await Future.wait(addedPlayersFutures);

        final createEntryFutures = addedPlayers.map((player) {
          return _rankingRepository.createMatchRankingEntry(
            playerId: player.playerId,
            matchId: matchId,
            currentRanking: player.ranking,
          );
        });
        await Future.wait(createEntryFutures);
      }
    }

    // Identify Removed Players
    final removedIds = currentPlayerIds.difference(newPlayerIds);
    if (removedIds.isNotEmpty) {
      final removeEntryFutures = removedIds.map((id) {
        return _rankingRepository.deleteMatchRankingEntry(
          playerId: id,
          matchId: matchId,
        );
      });
      await Future.wait(removeEntryFutures);
    }
  }
}

final updateMatchTeamsUseCaseProvider = Provider<UpdateMatchTeamsUseCase>((
  ref,
) {
  return UpdateMatchTeamsUseCase(
    ref.read(matchRepositoryProvider),
    ref.read(teamRepositoryProvider),
    ref.read(rankingRepositoryProvider),
    ref.read(playerRepositoryProvider),
  );
});
