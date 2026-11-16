import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:app/features/matches/domain/repositories/match_repository.dart';
import 'package:app/features/matches/domain/exceptions/roster_edit_rejected.dart';
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
  final _pending = <String, _PreservedRosterEdit>{};
  final _rejected = <String, _PreservedRosterEdit>{};
  final _active = <String, ({String key, Future<void> result})>{};

  UpdateMatchTeamsUseCase(
    this._matchRepository,
    this._teamRepository,
    this._rankingRepository,
    this._playerRepository,
  );

  bool hasPendingEdit(String matchId) => _pending.containsKey(matchId);
  bool hasRejectedEdit(String matchId) => _rejected.containsKey(matchId);

  Future<void> retryPending(String matchId) {
    final edit = _pending[matchId];
    if (edit == null) return Future.error(StateError('No pending roster edit'));
    return execute(
      matchId: matchId,
      homePlayerIds: edit.home,
      awayPlayerIds: edit.away,
    );
  }

  /// Capture the rejected operation before an explicit reload/cancel. Unknown
  /// outcomes have no discard token and must retain their exact retry payload.
  String? rejectedRequestId(String matchId) {
    if (_active.containsKey(matchId)) {
      throw StateError('Cannot recover a roster edit while it is in progress');
    }
    return _rejected[matchId]?.requestId;
  }

  void discardRejected(String matchId, {required String requestId}) {
    if (_active.containsKey(matchId)) {
      throw StateError('Cannot discard a roster edit while it is in progress');
    }
    final edit = _rejected[matchId];
    if (edit?.requestId == requestId && identical(_pending[matchId], edit)) {
      _pending.remove(matchId);
      _rejected.remove(matchId);
    }
  }

  Future<void> execute({
    required String matchId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
  }) {
    final home = [...homePlayerIds]..sort();
    final away = [...awayPlayerIds]..sort();
    final key = jsonEncode([home, away]);
    final active = _active[matchId];
    if (active != null) {
      if (active.key == key) return active.result;
      return Future.error(StateError('A roster edit is already in progress'));
    }
    late final Future<void> result;
    result =
        _execute(
          matchId: matchId,
          homePlayerIds: List.unmodifiable(homePlayerIds),
          awayPlayerIds: List.unmodifiable(awayPlayerIds),
        ).whenComplete(() {
          if (identical(_active[matchId]?.result, result)) {
            _active.remove(matchId);
          }
        });
    _active[matchId] = (key: key, result: result);
    return result;
  }

  Future<void> _execute({
    required String matchId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
  }) async {
    // Freeze membership and inputs across a failed response/retry. A replay
    // reaches the server directly, not a strict reader of a possible old state.
    final home = [...homePlayerIds]..sort();
    final away = [...awayPlayerIds]..sort();
    final key = jsonEncode([home, away]);
    final pending = _pending[matchId];
    if (pending != null) {
      if (pending.key != key) {
        throw StateError(
          'Resolve the pending roster edit before starting a different edit',
        );
      }
      await _submitPreserved(matchId, pending);
      return;
    }

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

    final newPlayerIds = {...home, ...away};
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
      final edit = _PreservedRosterEdit(
        key: key,
        requestId: const Uuid().v4(),
        home: List.unmodifiable(home),
        away: List.unmodifiable(away),
        rankings: Map.unmodifiable(rankings),
        expectedVersion:
            (match.scoreMeta['_roster_operation'] as Map?)?['id'] as String?,
      );
      _pending[matchId] = edit;
      await _submitPreserved(matchId, edit);
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

  Future<void> _submitPreserved(
    String matchId,
    _PreservedRosterEdit edit,
  ) async {
    _rejected.remove(matchId);
    try {
      await _teamRepository.updatePreservedMatchRoster(
        matchId: matchId,
        requestId: edit.requestId,
        homePlayerIds: edit.home,
        awayPlayerIds: edit.away,
        rankings: edit.rankings,
        expectedVersion: edit.expectedVersion,
      );
    } on RosterEditRejected {
      if (identical(_pending[matchId], edit)) _rejected[matchId] = edit;
      rethrow;
    }
    if (identical(_pending[matchId], edit)) {
      _pending.remove(matchId);
      _rejected.remove(matchId);
    }
  }
}

class _PreservedRosterEdit {
  final String key;
  final String requestId;
  final List<String> home;
  final List<String> away;
  final Map<String, double> rankings;
  final String? expectedVersion;

  const _PreservedRosterEdit({
    required this.key,
    required this.requestId,
    required this.home,
    required this.away,
    required this.rankings,
    required this.expectedVersion,
  });
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
