import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:app/core/app_config.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/features/draft/application/create_draft_use_case.dart';
import 'package:app/features/draft/application/get_match_draft_use_case.dart';
import 'package:app/features/draft/application/get_player_pair_win_rates_use_case.dart';
import 'package:app/features/draft/application/save_match_draft_use_case.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/entities/head_to_head_win_rate.dart';
import 'package:app/features/draft/domain/entities/stored_draft_payload.dart';
import 'package:app/features/draft/domain/services/draft_algorithm_policy.dart';
import 'package:app/features/draft/presentation/state/draft_session_state.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/players/players_providers.dart';

enum DraftAlgorithm { combinatory, greedy }

class DraftAlgorithmNotifier extends Notifier<DraftAlgorithm> {
  @override
  DraftAlgorithm build() {
    return DraftAlgorithm.combinatory;
  }

  void setAlgorithm(DraftAlgorithm algorithm) {
    Logger(
      'DraftAlgorithmNotifier',
    ).info('Draft algorithm changed to $algorithm');
    state = algorithm;
  }
}

final draftAlgorithmProvider =
    NotifierProvider<DraftAlgorithmNotifier, DraftAlgorithm>(
      DraftAlgorithmNotifier.new,
    );

class DraftSessionNotifier extends Notifier<AsyncValue<DraftSessionState>> {
  static final Logger _logger = Logger('DraftSessionNotifier');
  _DraftLoadRequest? _activeRequest;
  Future<void>? _activeLoadFuture;

  @override
  AsyncValue<DraftSessionState> build() {
    return const AsyncValue.loading();
  }

  Future<void> load({
    required String squadId,
    required List<String> selectedPlayerIds,
    required DraftAlgorithm algorithm,
    List<DraftRule> rules = const [],
    String? matchId,
    bool playWithSubstitute = true,
  }) async {
    final request = _DraftLoadRequest(
      squadId: squadId,
      selectedPlayerIds: selectedPlayerIds,
      algorithm: algorithm,
      rules: rules,
      matchId: matchId,
      playWithSubstitute: playWithSubstitute,
    );

    final inFlight = _activeLoadFuture;
    final isMatchLookupOnly = matchId != null && selectedPlayerIds.isEmpty;
    if (inFlight != null && state.isLoading) {
      final sameRequest = _activeRequest == request;
      final sameMatchLookup =
          isMatchLookupOnly && _activeRequest?.matchId == matchId;
      if (sameRequest || sameMatchLookup) {
        await inFlight;
        return;
      }
    }

    state = const AsyncValue.loading();
    await Future<void>.delayed(Duration.zero);

    final loadFuture = _performLoad(request);
    _activeRequest = request;
    _activeLoadFuture = loadFuture;

    await loadFuture;

    if (identical(_activeLoadFuture, loadFuture)) {
      _activeLoadFuture = null;
    }
  }

  Future<void> _performLoad(_DraftLoadRequest request) async {
    state = await AsyncValue.guard(() async {
      try {
        final allPlayers = await ref
            .read(getSquadPlayersUseCaseProvider)
            .execute(squadId: request.squadId);

        if (request.selectedPlayerIds.isEmpty && request.matchId != null) {
          final storedDraft = await ref
              .read(getMatchDraftUseCaseProvider)
              .execute(matchId: request.matchId!);

          if (storedDraft == null) {
            final rankingEntries = await ref
                .read(rankingRepositoryProvider)
                .getMatchRankingHistory(request.matchId!);
            var selectedPlayerIds = <String>{
              for (final entry in rankingEntries) entry.playerId,
            }.toList(growable: false);

            if (selectedPlayerIds.length < 2) {
              final match = await ref
                  .read(getMatchUseCaseProvider)
                  .execute(matchId: request.matchId!);
              selectedPlayerIds = <String>{
                for (final player in match.homeTeam?.players ?? const [])
                  player.playerId,
                for (final player in match.awayTeam?.players ?? const [])
                  player.playerId,
              }.toList(growable: false);
            }

            if (selectedPlayerIds.length < 2) {
              throw const ValidationFailure(
                'Nie znaleziono propozycji dla tego meczu. Wybierz graczy i spróbuj ponownie.',
              );
            }

            return await _generateAndPersistDraftState(
              request: request,
              allPlayers: allPlayers,
              selectedPlayerIds: selectedPlayerIds,
            );
          }

          if (storedDraft.status == 'error') {
            throw ValidationFailure(
              storedDraft.errorMessage ??
                  'Propozycja dla tego meczu zakończyła się wcześniej błędem. Spróbuj ponownie.',
            );
          }

          final playersById = {
            for (final player in allPlayers) player.playerId: player,
          };
          final proposals = _restoreDraftsFromPayload(
            proposals: storedDraft.proposals,
            playersById: playersById,
          );
          final winRateMatrix = storedDraft.winRateMatrix;

          return _buildDraftState(
            proposals: proposals,
            winRateMatrix: winRateMatrix,
            seed: storedDraft.seed,
          );
        }

        if (request.selectedPlayerIds.length < 2) {
          throw const ValidationFailure(
            'Propozycja wymaga co najmniej 2 graczy.',
          );
        }
        final requestedAlgorithm = _resolveAlgorithmForPlayerCount(
          preferred: request.algorithm,
          playerCount: request.selectedPlayerIds.length,
        );
        if (requestedAlgorithm == DraftAlgorithm.combinatory &&
            request.selectedPlayerIds.length > AppConfig.maxPlayersPerMatch) {
          throw ValidationFailure(
            'Propozycja obsługuje maksymalnie ${AppConfig.maxPlayersPerMatch} graczy na mecz.',
          );
        }

        final selectedCount = _filterByIds(
          players: allPlayers,
          ids: request.selectedPlayerIds,
        ).length;
        if (requestedAlgorithm == DraftAlgorithm.combinatory &&
            selectedCount > AppConfig.maxPlayersPerMatch) {
          throw ValidationFailure(
            'Propozycja obsługuje maksymalnie ${AppConfig.maxPlayersPerMatch} graczy na mecz.',
          );
        }

        return await _generateAndPersistDraftState(
          request: request,
          allPlayers: allPlayers,
          selectedPlayerIds: request.selectedPlayerIds,
        );
      } catch (error, stack) {
        if (request.matchId != null && request.selectedPlayerIds.isNotEmpty) {
          try {
            await ref
                .read(saveMatchDraftUseCaseProvider)
                .executeError(
                  squadId: request.squadId,
                  matchId: request.matchId!,
                  teamCount: 2,
                  errorMessage: '$error',
                );
          } catch (persistError, persistStack) {
            _logger.warning(
              'Failed to persist draft error state for ${request.matchId}',
              persistError,
              persistStack,
            );
          }
        }
        Error.throwWithStackTrace(error, stack);
      }
    });
  }

  Future<DraftSessionState> _generateAndPersistDraftState({
    required _DraftLoadRequest request,
    required List<Player> allPlayers,
    required List<String> selectedPlayerIds,
  }) async {
    final selected = _filterByIds(players: allPlayers, ids: selectedPlayerIds);
    if (selected.length < 2) {
      throw const ValidationFailure('Propozycja wymaga co najmniej 2 graczy.');
    }
    final algorithm = _resolveAlgorithmForPlayerCount(
      preferred: request.algorithm,
      playerCount: selected.length,
    );
    if (algorithm == DraftAlgorithm.combinatory &&
        selected.length > AppConfig.maxPlayersPerMatch) {
      throw ValidationFailure(
        'Propozycja obsługuje maksymalnie ${AppConfig.maxPlayersPerMatch} graczy na mecz.',
      );
    }

    final useCase = switch (algorithm) {
      DraftAlgorithm.combinatory => ref.read(
        combinatoryCreateDraftUseCaseProvider,
      ),
      DraftAlgorithm.greedy => ref.read(greedyCreateDraftUseCaseProvider),
    };
    final seed = algorithm == DraftAlgorithm.greedy ? _randomSeed() : null;

    final proposals = await useCase.execute(
      players: selected,
      rules: request.rules,
      playWithSubstitute: request.playWithSubstitute,
      seed: seed,
    );

    final winRates = await ref
        .read(getPlayerPairWinRatesUseCaseProvider)
        .execute(playerIds: selectedPlayerIds);

    final draftState = _buildDraftState(
      proposals: proposals,
      winRateMatrix: _buildWinRateMatrix(winRates),
      seed: seed,
    );

    if (request.matchId != null) {
      try {
        await ref
            .read(saveMatchDraftUseCaseProvider)
            .executeCompleted(
              squadId: request.squadId,
              matchId: request.matchId!,
              proposals: draftState.proposals,
              winRateMatrix: draftState.winRateMatrix,
              teamCount: draftState.proposals.isEmpty
                  ? 2
                  : draftState.proposals.first.teams.length,
              seed: draftState.seed,
            );
      } catch (persistError, persistStack) {
        _logger.warning(
          'Draft generated but failed to persist payload for ${request.matchId}',
          persistError,
          persistStack,
        );
      }
    }

    return draftState;
  }

  void selectProposal(int index) {
    final current = state.value;
    if (current == null) {
      return;
    }

    if (index < 0 || index >= current.proposals.length) {
      return;
    }

    final proposal = current.proposals[index];
    final homeWinProbability = _calculateHomeWinProbability(
      home: proposal.homePlayers,
      away: proposal.awayPlayers,
      winRateMatrix: current.winRateMatrix,
    );

    state = AsyncValue.data(
      current.copyWith(
        selectedIndex: index,
        home: proposal.homePlayers,
        away: proposal.awayPlayers,
        homeWinProbability: homeWinProbability,
      ),
    );
  }

  void movePlayer({required String playerId, required bool toHome}) {
    final current = state.value;
    if (current == null) {
      return;
    }

    final home = [...current.home];
    final away = [...current.away];

    Player? player;

    for (final p in home) {
      if (p.playerId == playerId) {
        player = p;
        break;
      }
    }
    if (player == null) {
      for (final p in away) {
        if (p.playerId == playerId) {
          player = p;
          break;
        }
      }
    }

    if (player == null) {
      return;
    }

    home.removeWhere((p) => p.playerId == playerId);
    away.removeWhere((p) => p.playerId == playerId);

    if (toHome) {
      home.add(player);
    } else {
      away.add(player);
    }

    final homeWinProbability = _calculateHomeWinProbability(
      home: home,
      away: away,
      winRateMatrix: current.winRateMatrix,
    );

    state = AsyncValue.data(
      current.copyWith(
        home: home,
        away: away,
        homeWinProbability: homeWinProbability,
      ),
    );
  }
}

class _DraftLoadRequest {
  final String squadId;
  final List<String> selectedPlayerIds;
  final DraftAlgorithm algorithm;
  final List<DraftRule> rules;
  final String? matchId;
  final bool playWithSubstitute;

  _DraftLoadRequest({
    required this.squadId,
    required List<String> selectedPlayerIds,
    required this.algorithm,
    required List<DraftRule> rules,
    required this.matchId,
    required this.playWithSubstitute,
  }) : selectedPlayerIds = List<String>.unmodifiable(
         [...selectedPlayerIds]..sort(),
       ),
       rules = List<DraftRule>.unmodifiable([
         for (final rule in rules)
           DraftRule(
             type: rule.type,
             playerIds: List<String>.unmodifiable([...rule.playerIds]),
           ),
       ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _DraftLoadRequest &&
        other.squadId == squadId &&
        other.algorithm == algorithm &&
        other.matchId == matchId &&
        other.playWithSubstitute == playWithSubstitute &&
        _rulesEqual(other.rules, rules) &&
        _listEquals(other.selectedPlayerIds, selectedPlayerIds);
  }

  @override
  int get hashCode {
    return Object.hash(
      squadId,
      algorithm,
      matchId,
      playWithSubstitute,
      _rulesHash(rules),
      _listHash(selectedPlayerIds),
    );
  }
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

int _listHash(List<String> values) {
  var hash = 17;
  for (final value in values) {
    hash = 37 * hash + value.hashCode;
  }
  return hash;
}

bool _rulesEqual(List<DraftRule> left, List<DraftRule> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    final leftRule = left[i];
    final rightRule = right[i];
    if (leftRule.type != rightRule.type) {
      return false;
    }
    if (!_listEquals(leftRule.playerIds, rightRule.playerIds)) {
      return false;
    }
  }
  return true;
}

int _rulesHash(List<DraftRule> rules) {
  var hash = 19;
  for (final rule in rules) {
    hash = 41 * hash + rule.type.hashCode;
    hash = 41 * hash + _listHash(rule.playerIds);
  }
  return hash;
}

final draftSessionNotifierProvider =
    NotifierProvider<DraftSessionNotifier, AsyncValue<DraftSessionState>>(
      DraftSessionNotifier.new,
    );

List<Player> _filterByIds({
  required List<Player> players,
  required List<String> ids,
}) {
  final byId = {for (final p in players) p.playerId: p};

  return ids.map(byId.remove).whereType<Player>().toList(growable: false);
}

Map<String, Map<String, double>> _buildWinRateMatrix(
  List<HeadToHeadWinRate> winRates,
) {
  final matrix = <String, Map<String, double>>{};
  for (final rate in winRates) {
    final oppMap = matrix.putIfAbsent(rate.playerId, () => <String, double>{});
    oppMap[rate.oppPlayerId] = rate.winRate;
  }
  return matrix;
}

DraftSessionState _buildDraftState({
  required List<Draft> proposals,
  required Map<String, Map<String, double>> winRateMatrix,
  required int? seed,
}) {
  if (proposals.isEmpty) {
    return DraftSessionState(
      proposals: const [],
      selectedIndex: 0,
      seed: seed,
      home: const [],
      away: const [],
      winRateMatrix: winRateMatrix,
      homeWinProbability: 0.5,
    );
  }

  final first = proposals.first;
  final homeWinProbability = _calculateHomeWinProbability(
    home: first.homePlayers,
    away: first.awayPlayers,
    winRateMatrix: winRateMatrix,
  );

  return DraftSessionState(
    proposals: proposals,
    selectedIndex: 0,
    seed: seed,
    home: first.homePlayers,
    away: first.awayPlayers,
    winRateMatrix: winRateMatrix,
    homeWinProbability: homeWinProbability,
  );
}

DraftAlgorithm _resolveAlgorithmForPlayerCount({
  required DraftAlgorithm preferred,
  required int playerCount,
}) {
  final policySelection = DraftAlgorithmPolicy.resolve(
    teamCount: 2,
    playerCount: playerCount,
  );
  if (policySelection == DraftAlgorithmSelection.greedy) {
    return DraftAlgorithm.greedy;
  }
  if (playerCount > AppConfig.maxPlayersPerMatch) {
    return DraftAlgorithm.greedy;
  }
  return preferred;
}

int _randomSeed() => Random().nextInt(0x7FFFFFFF);

double _calculateHomeWinProbability({
  required List<Player> home,
  required List<Player> away,
  required Map<String, Map<String, double>> winRateMatrix,
}) {
  if (home.isEmpty || away.isEmpty) {
    return 0.5;
  }

  var total = 0.0;
  var count = 0;

  for (final homePlayer in home) {
    final oppRates = winRateMatrix[homePlayer.playerId];
    for (final awayPlayer in away) {
      final rate = oppRates?[awayPlayer.playerId] ?? 0.5;
      total += rate;
      count += 1;
    }
  }

  if (count == 0) {
    return 0.5;
  }

  final average = total / count;
  return average.clamp(0.0, 1.0);
}

List<Draft> _restoreDraftsFromPayload({
  required List<StoredDraftProposal> proposals,
  required Map<String, Player> playersById,
}) {
  final drafts = <Draft>[];

  for (final proposal in proposals) {
    final teams = <DraftTeam>[];
    final usedPlayerIds = <String>{};

    for (var teamIndex = 0; teamIndex < proposal.teams.length; teamIndex++) {
      final teamPlayerIds = proposal.teams[teamIndex];
      final players = <Player>[];
      var totalRanking = 0.0;

      for (final playerId in teamPlayerIds) {
        if (!usedPlayerIds.add(playerId)) {
          continue;
        }

        final player = playersById[playerId];
        if (player == null) {
          continue;
        }

        players.add(player);
        totalRanking += player.ranking;
      }

      teams.add(
        DraftTeam(
          index: teamIndex,
          players: players,
          totalRanking: totalRanking,
        ),
      );
    }

    if (teams.isNotEmpty) {
      drafts.add(Draft(teams: teams));
    }
  }

  return drafts;
}
