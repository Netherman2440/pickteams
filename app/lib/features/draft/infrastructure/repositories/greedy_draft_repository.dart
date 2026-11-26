import 'dart:math';

import 'package:app/core/app_config.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_proposal.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/entities/normalized_draft_rule.dart';
import 'package:app/features/draft/domain/repositories/draft_repository.dart';
import 'package:app/features/draft/domain/services/two_team_balance.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:logging/logging.dart';

class GreedyDraftRepository implements DraftRepository {
  const GreedyDraftRepository({
    this.candidatePoolSize = _defaultCandidatePoolSize,
  });

  static const int _minTeamCount = 2;
  static const int _maxTeamCount = 4;
  static const int _defaultCandidatePoolSize = 7;
  static const int _maxIterations = AppConfig.greedyDraftVariantChecks;
  static const int _minIterations = 3000;
  static const int _iterationsPerRequestedDraft = 300;
  static const int _maxNoProgressIterations = 2500;
  static const int _largeDraftPoolDivisor = 2;
  static const Duration _uiYieldBudget = Duration(milliseconds: 12);
  static const double _rulePenalty = 100.0;
  static const double _positionPenalty = 100.0;
  static final Logger _logger = Logger('GreedyDraftRepository');

  final int candidatePoolSize;

  @override
  Future<List<Draft>> createDraft({
    required List<Player> players,
    int teamCount = 2,
    List<DraftRule> rules = const [],
    int limit = 20,
    bool playWithSubstitute = true,
    int? seed,
    Map<String, int> appearances = const {},
  }) async {
    final startedAt = DateTime.now();
    final forceFullIterationBudget =
        players.length >= AppConfig.greedyDraftThresholdPlayers;
    final targetIterations = forceFullIterationBudget
        ? _maxIterations
        : min(
            _maxIterations,
            max(_minIterations, limit * _iterationsPerRequestedDraft),
          );
    _logger.info(
      'createDraft started: startedAt=${startedAt.toIso8601String()} teamCount=$teamCount players=${players.length} limit=$limit seed=${seed ?? 'random'} iterations=$targetIterations',
    );

    if (players.isEmpty || limit <= 0) {
      return const [];
    }

    if (teamCount < _minTeamCount || teamCount > _maxTeamCount) {
      throw ValidationFailure(
        'Draft supports between $_minTeamCount and $_maxTeamCount teams.',
      );
    }

    if (players.length < teamCount) {
      throw const ValidationFailure(
        'Draft requires at least one player per team.',
      );
    }

    if (candidatePoolSize <= 0) {
      throw const ValidationFailure(
        'Greedy draft requires positive candidatePoolSize.',
      );
    }

    final sortedPlayers = [...players]
      ..sort((a, b) => a.playerId.compareTo(b.playerId));
    final playersById = {for (final p in sortedPlayers) p.playerId: p};
    final normalizedRules = _normalizeRules(
      rules: rules,
      playersById: playersById,
    );
    final rulesByPlayer = _groupRulesByPlayer(rules: normalizedRules);

    final targetTeamSizes = _calculateTeamSizes(
      playerCount: sortedPlayers.length,
      teamCount: teamCount,
    );

    final processSeed = seed ?? _randomSeed();
    final generationInput = _GreedyGenerationInput(
      sortedPlayers: sortedPlayers,
      normalizedRules: normalizedRules,
      rulesByPlayer: rulesByPlayer,
      targetTeamSizes: targetTeamSizes,
      candidatePoolSize: candidatePoolSize,
      playWithSubstitute: playWithSubstitute,
      processSeed: processSeed,
      iterations: targetIterations,
      requestedLimit: limit,
      stopWhenStalled: !forceFullIterationBudget,
    );

    final generatedProposals = kIsWeb
        ? await _runGreedyGenerationWithYield(generationInput)
        : await compute(_runGreedyGeneration, generationInput);

    final scoredProposals = _applyEqualWeightScoring(generatedProposals);

    final balance = TwoTeamBalance(players, appearances);
    scoredProposals.sort((a, b) {
      if (teamCount == 2) {
        return balance.compare(a, b, playWithSubstitute: playWithSubstitute);
      }
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) {
        return byScore;
      }

      final byTieBreaker = a.tieBreaker.compareTo(b.tieBreaker);
      if (byTieBreaker != 0) {
        return byTieBreaker;
      }

      return a.signature.compareTo(b.signature);
    });

    final result = scoredProposals
        .take(limit)
        .map((proposal) => proposal.draft)
        .toList(growable: false);
    final finishedAt = DateTime.now();
    final elapsedMs = finishedAt.difference(startedAt).inMilliseconds;
    _logger.info(
      'createDraft completed: finishedAt=${finishedAt.toIso8601String()} elapsedMs=$elapsedMs teamCount=$teamCount players=${players.length} limit=$limit seed=$processSeed iterations=$targetIterations proposals=${generatedProposals.length} returned=${result.length}',
    );
    return result;
  }
}

List<DraftProposal> _runGreedyGeneration(_GreedyGenerationInput input) {
  final generatedProposals = <DraftProposal>[];
  final seenSignatures = <String>{};
  var noProgressIterations = 0;

  for (var iteration = 0; iteration < input.iterations; iteration++) {
    final iterationCandidatePoolSize = _candidatePoolSizeForIteration(
      input: input,
      iteration: iteration,
    );
    final iterationSeed = _mixSeed(input.processSeed, iteration);
    final proposal = _buildGreedyProposal(
      sortedPlayers: input.sortedPlayers,
      rules: input.normalizedRules,
      ruleIndexesByPlayer: input.rulesByPlayer,
      teamSizes: input.targetTeamSizes,
      candidatePoolSize: iterationCandidatePoolSize,
      iterationSeed: iterationSeed,
      playWithSubstitute: input.playWithSubstitute,
    );

    if (proposal == null) {
      noProgressIterations++;
      if (generatedProposals.length >= input.requestedLimit &&
          input.stopWhenStalled &&
          noProgressIterations >=
              GreedyDraftRepository._maxNoProgressIterations) {
        break;
      }
      continue;
    }

    if (!seenSignatures.add(proposal.signature)) {
      noProgressIterations++;
      if (generatedProposals.length >= input.requestedLimit &&
          input.stopWhenStalled &&
          noProgressIterations >=
              GreedyDraftRepository._maxNoProgressIterations) {
        break;
      }
      continue;
    }

    generatedProposals.add(proposal);
    noProgressIterations = 0;
  }

  return generatedProposals;
}

Future<List<DraftProposal>> _runGreedyGenerationWithYield(
  _GreedyGenerationInput input,
) async {
  final generatedProposals = <DraftProposal>[];
  final seenSignatures = <String>{};
  final yieldStopwatch = Stopwatch()..start();
  var noProgressIterations = 0;

  for (var iteration = 0; iteration < input.iterations; iteration++) {
    final iterationCandidatePoolSize = _candidatePoolSizeForIteration(
      input: input,
      iteration: iteration,
    );
    final iterationSeed = _mixSeed(input.processSeed, iteration);
    final proposal = _buildGreedyProposal(
      sortedPlayers: input.sortedPlayers,
      rules: input.normalizedRules,
      ruleIndexesByPlayer: input.rulesByPlayer,
      teamSizes: input.targetTeamSizes,
      candidatePoolSize: iterationCandidatePoolSize,
      iterationSeed: iterationSeed,
      playWithSubstitute: input.playWithSubstitute,
    );

    if (proposal != null && seenSignatures.add(proposal.signature)) {
      generatedProposals.add(proposal);
      noProgressIterations = 0;
    } else {
      noProgressIterations++;
      if (generatedProposals.length >= input.requestedLimit &&
          input.stopWhenStalled &&
          noProgressIterations >=
              GreedyDraftRepository._maxNoProgressIterations) {
        break;
      }
    }

    if (yieldStopwatch.elapsed >= GreedyDraftRepository._uiYieldBudget) {
      await Future<void>.delayed(Duration.zero);
      yieldStopwatch.reset();
    }
  }

  return generatedProposals;
}

int _candidatePoolSizeForIteration({
  required _GreedyGenerationInput input,
  required int iteration,
}) {
  final playersCount = input.sortedPlayers.length;
  if (playersCount < AppConfig.greedyDraftThresholdPlayers) {
    return input.candidatePoolSize;
  }

  if (iteration == 0) {
    return playersCount;
  }

  final poolSize = playersCount ~/ GreedyDraftRepository._largeDraftPoolDivisor;
  return poolSize > 0 ? poolSize : 1;
}

DraftProposal? _buildGreedyProposal({
  required List<Player> sortedPlayers,
  required List<NormalizedDraftRule> rules,
  required Map<int, List<NormalizedDraftRule>> ruleIndexesByPlayer,
  required List<int> teamSizes,
  required int candidatePoolSize,
  required int iterationSeed,
  required bool playWithSubstitute,
}) {
  final random = Random(iterationSeed);
  final teamCount = teamSizes.length;

  final remainingIndexes = List<int>.generate(sortedPlayers.length, (i) => i)
    ..shuffle(random);
  final teamIndexes = List<List<int>>.generate(teamCount, (_) => <int>[]);
  final teamPositionCounts = List<Map<String, int>>.generate(
    teamCount,
    (_) => <String, int>{},
  );
  final teamTotals = List<double>.filled(teamCount, 0.0);
  final assignedTeamByPlayerIndex = List<int?>.filled(
    sortedPlayers.length,
    null,
  );

  var nextTeamIndex = iterationSeed % teamCount;

  while (remainingIndexes.isNotEmpty) {
    final currentTeamIndex = _findNextTeamWithCapacity(
      startTeamIndex: nextTeamIndex,
      teamIndexes: teamIndexes,
      targetSizes: teamSizes,
    );
    if (currentTeamIndex < 0) {
      break;
    }

    final pick = _pickCandidateForTeam(
      sortedPlayers: sortedPlayers,
      remainingIndexes: remainingIndexes,
      candidatePoolSize: candidatePoolSize,
      targetTeamIndex: currentTeamIndex,
      teamPositionCounts: teamPositionCounts,
      assignedTeamByPlayerIndex: assignedTeamByPlayerIndex,
      ruleIndexesByPlayer: ruleIndexesByPlayer,
      iterationSeed: iterationSeed,
      pickIndex: teamIndexes[currentTeamIndex].length,
    );

    if (pick == null) {
      break;
    }

    final player = sortedPlayers[pick.playerIndex];
    final positionKey = _normalizePosition(player.position);

    remainingIndexes.removeAt(pick.remainingPosition);
    teamIndexes[currentTeamIndex].add(pick.playerIndex);
    teamTotals[currentTeamIndex] += player.ranking;
    assignedTeamByPlayerIndex[pick.playerIndex] = currentTeamIndex;
    final currentPositionCount =
        teamPositionCounts[currentTeamIndex][positionKey] ?? 0;
    teamPositionCounts[currentTeamIndex][positionKey] =
        currentPositionCount + 1;

    nextTeamIndex = (currentTeamIndex + 1) % teamCount;
  }

  final allAssigned = teamIndexes.fold<int>(
    0,
    (sum, team) => sum + team.length,
  );
  if (allAssigned != sortedPlayers.length) {
    return null;
  }

  final teams = _buildCanonicalTeams(
    sortedPlayers: sortedPlayers,
    teamIndexes: teamIndexes,
    teamTotals: teamTotals,
  );
  final playerTeamIndex = _buildPlayerTeamIndex(
    teams: teams,
    sortedPlayers: sortedPlayers,
  );

  final effectiveTeamRankings = teams
      .map(
        (team) => _effectiveTeamRanking(
          team: team,
          allTeams: teams,
          playWithSubstitute: playWithSubstitute,
        ),
      )
      .toList(growable: false);

  final avgTeamRanking =
      effectiveTeamRankings.reduce((a, b) => a + b) /
      effectiveTeamRankings.length;

  var deviationScore = 0.0;
  for (final effectiveRanking in effectiveTeamRankings) {
    deviationScore += (effectiveRanking - avgTeamRanking).abs();
  }

  final positionWeight = _calculatePositionWeight(teams);
  final rulePenalty = _calculateRulePenalty(
    rules: rules,
    playerTeamIndex: playerTeamIndex,
  );
  final penaltyScore = positionWeight + rulePenalty;
  final tieBreaker = _calculateTieBreaker(teams);
  final signature = _buildSignature(teams);

  return DraftProposal(
    draft: Draft(teams: teams),
    score: 0.0,
    deviationScore: deviationScore,
    penaltyScore: penaltyScore,
    rulePenalty: rulePenalty,
    tieBreaker: tieBreaker,
    signature: signature,
  );
}

_CandidatePick? _pickCandidateForTeam({
  required List<Player> sortedPlayers,
  required List<int> remainingIndexes,
  required int candidatePoolSize,
  required int targetTeamIndex,
  required List<Map<String, int>> teamPositionCounts,
  required List<int?> assignedTeamByPlayerIndex,
  required Map<int, List<NormalizedDraftRule>> ruleIndexesByPlayer,
  required int iterationSeed,
  required int pickIndex,
}) {
  if (remainingIndexes.isEmpty) {
    return null;
  }

  final poolLength = min(candidatePoolSize, remainingIndexes.length);
  _CandidatePick? best;

  for (
    var remainingPosition = 0;
    remainingPosition < poolLength;
    remainingPosition++
  ) {
    final playerIndex = remainingIndexes[remainingPosition];
    final player = sortedPlayers[playerIndex];
    final weight = _calculateCandidateWeight(
      playerIndex: playerIndex,
      position: player.position,
      targetTeamIndex: targetTeamIndex,
      teamPositionCounts: teamPositionCounts,
      assignedTeamByPlayerIndex: assignedTeamByPlayerIndex,
      rulesByPlayer: ruleIndexesByPlayer,
    );
    final ratio = player.ranking / weight;
    final tieBreaker = _stableHash32(
      input: player.playerId,
      salt: iterationSeed ^ targetTeamIndex ^ pickIndex,
    );

    final candidate = _CandidatePick(
      playerIndex: playerIndex,
      remainingPosition: remainingPosition,
      ratio: ratio,
      weight: weight,
      ranking: player.ranking,
      tieBreaker: tieBreaker,
    );

    if (best == null || _isBetterCandidate(left: candidate, right: best)) {
      best = candidate;
    }
  }

  return best;
}

bool _isBetterCandidate({
  required _CandidatePick left,
  required _CandidatePick right,
}) {
  const eps = 1e-9;

  if (left.ratio > right.ratio + eps) {
    return true;
  }
  if (left.ratio < right.ratio - eps) {
    return false;
  }

  if (left.weight < right.weight - eps) {
    return true;
  }
  if (left.weight > right.weight + eps) {
    return false;
  }

  if (left.ranking > right.ranking + eps) {
    return true;
  }
  if (left.ranking < right.ranking - eps) {
    return false;
  }

  if (left.tieBreaker < right.tieBreaker) {
    return true;
  }
  if (left.tieBreaker > right.tieBreaker) {
    return false;
  }

  return left.playerIndex < right.playerIndex;
}

double _calculateCandidateWeight({
  required int playerIndex,
  required String? position,
  required int targetTeamIndex,
  required List<Map<String, int>> teamPositionCounts,
  required List<int?> assignedTeamByPlayerIndex,
  required Map<int, List<NormalizedDraftRule>> rulesByPlayer,
}) {
  final positionKey = _normalizePosition(position);
  final samePositionCount =
      teamPositionCounts[targetTeamIndex][positionKey] ?? 0;
  var weight = 1.0 + samePositionCount * GreedyDraftRepository._positionPenalty;

  final playerRules = rulesByPlayer[playerIndex];
  if (playerRules == null || playerRules.isEmpty) {
    return weight;
  }

  for (final rule in playerRules) {
    final assignedOtherTeams = <int>{};
    for (final memberIndex in rule.playerIndexes) {
      if (memberIndex == playerIndex) {
        continue;
      }
      final memberTeam = assignedTeamByPlayerIndex[memberIndex];
      if (memberTeam != null) {
        assignedOtherTeams.add(memberTeam);
      }
    }

    if (assignedOtherTeams.isEmpty) {
      continue;
    }

    switch (rule.type) {
      case DraftRuleType.together:
        final keepsTogether = assignedOtherTeams.every(
          (teamIndex) => teamIndex == targetTeamIndex,
        );
        if (!keepsTogether) {
          weight += GreedyDraftRepository._rulePenalty;
        }
        break;
      case DraftRuleType.against:
        final collides = assignedOtherTeams.any(
          (teamIndex) => teamIndex == targetTeamIndex,
        );
        if (collides) {
          weight += GreedyDraftRepository._rulePenalty;
        }
        break;
    }
  }

  return weight;
}

List<DraftTeam> _buildCanonicalTeams({
  required List<Player> sortedPlayers,
  required List<List<int>> teamIndexes,
  required List<double> teamTotals,
}) {
  final rawTeams = <_TeamWithKey>[];

  for (var i = 0; i < teamIndexes.length; i++) {
    final indexes = teamIndexes[i];
    final players = indexes.map((index) => sortedPlayers[index]).toList()
      ..sort((a, b) => a.playerId.compareTo(b.playerId));
    final key = players.map((player) => player.playerId).join(',');
    rawTeams.add(
      _TeamWithKey(key: key, players: players, totalRanking: teamTotals[i]),
    );
  }

  rawTeams.sort((a, b) => a.key.compareTo(b.key));

  return List<DraftTeam>.generate(
    rawTeams.length,
    (index) => DraftTeam(
      index: index,
      players: rawTeams[index].players,
      totalRanking: rawTeams[index].totalRanking,
    ),
    growable: false,
  );
}

Map<int, int> _buildPlayerTeamIndex({
  required List<DraftTeam> teams,
  required List<Player> sortedPlayers,
}) {
  final idToIndex = <String, int>{
    for (var i = 0; i < sortedPlayers.length; i++) sortedPlayers[i].playerId: i,
  };
  final playerTeamIndex = <int, int>{};

  for (final team in teams) {
    for (final player in team.players) {
      final index = idToIndex[player.playerId];
      if (index != null) {
        playerTeamIndex[index] = team.index;
      }
    }
  }

  return playerTeamIndex;
}

int _findNextTeamWithCapacity({
  required int startTeamIndex,
  required List<List<int>> teamIndexes,
  required List<int> targetSizes,
}) {
  for (var offset = 0; offset < teamIndexes.length; offset++) {
    final teamIndex = (startTeamIndex + offset) % teamIndexes.length;
    if (teamIndexes[teamIndex].length < targetSizes[teamIndex]) {
      return teamIndex;
    }
  }
  return -1;
}

Map<int, List<NormalizedDraftRule>> _groupRulesByPlayer({
  required List<NormalizedDraftRule> rules,
}) {
  final grouped = <int, List<NormalizedDraftRule>>{};

  for (final rule in rules) {
    for (final playerIndex in rule.playerIndexes) {
      grouped.putIfAbsent(playerIndex, () => <NormalizedDraftRule>[]).add(rule);
    }
  }

  return grouped;
}

List<NormalizedDraftRule> _normalizeRules({
  required List<DraftRule> rules,
  required Map<String, Player> playersById,
}) {
  final byId = playersById.keys.toList(growable: false);
  final idToIndex = <String, int>{
    for (var i = 0; i < byId.length; i++) byId[i]: i,
  };
  final normalized = <NormalizedDraftRule>[];

  for (final rule in rules) {
    final uniquePlayerIds = <String>{};
    final indexes = <int>[];

    for (final playerId in rule.playerIds) {
      if (!playersById.containsKey(playerId)) {
        continue;
      }
      if (!uniquePlayerIds.add(playerId)) {
        continue;
      }
      final idx = idToIndex[playerId];
      if (idx != null) {
        indexes.add(idx);
      }
    }

    if (indexes.length < 2) {
      continue;
    }

    indexes.sort();
    normalized.add(
      NormalizedDraftRule(type: rule.type, playerIndexes: indexes),
    );
  }

  return normalized;
}

List<int> _calculateTeamSizes({
  required int playerCount,
  required int teamCount,
}) {
  final base = playerCount ~/ teamCount;
  final remainder = playerCount % teamCount;

  return List<int>.generate(
    teamCount,
    (index) => base + (index < remainder ? 1 : 0),
    growable: false,
  );
}

List<DraftProposal> _applyEqualWeightScoring(List<DraftProposal> proposals) {
  if (proposals.isEmpty) {
    return const <DraftProposal>[];
  }

  var minDeviation = proposals.first.deviationScore;
  var maxDeviation = proposals.first.deviationScore;
  var minPenalty = proposals.first.penaltyScore;
  var maxPenalty = proposals.first.penaltyScore;

  for (final proposal in proposals.skip(1)) {
    if (proposal.deviationScore < minDeviation) {
      minDeviation = proposal.deviationScore;
    }
    if (proposal.deviationScore > maxDeviation) {
      maxDeviation = proposal.deviationScore;
    }
    if (proposal.penaltyScore < minPenalty) {
      minPenalty = proposal.penaltyScore;
    }
    if (proposal.penaltyScore > maxPenalty) {
      maxPenalty = proposal.penaltyScore;
    }
  }

  final deviationRange = maxDeviation - minDeviation;
  final penaltyRange = maxPenalty - minPenalty;

  return proposals
      .map((proposal) {
        final normalizedDeviation = deviationRange == 0
            ? 0.0
            : (proposal.deviationScore - minDeviation) / deviationRange;
        final normalizedPenalty = penaltyRange == 0
            ? 0.0
            : (proposal.penaltyScore - minPenalty) / penaltyRange;

        final score = normalizedDeviation + normalizedPenalty;
        return proposal.copyWith(score: score);
      })
      .toList(growable: false);
}

double _effectiveTeamRanking({
  required DraftTeam team,
  required List<DraftTeam> allTeams,
  required bool playWithSubstitute,
}) {
  final minSize = allTeams
      .map((t) => t.players.length)
      .reduce((value, element) => value < element ? value : element);

  return effectiveTeamRanking(
    totalRanking: team.totalRanking,
    teamSize: team.players.length,
    opponentTeamSize: minSize,
    playWithSubstitute: playWithSubstitute,
  );
}

double _calculatePositionWeight(List<DraftTeam> teams) {
  var totalWeight = 0.0;

  for (final team in teams) {
    final counts = <String, int>{};

    for (final player in team.players) {
      final key = _normalizePosition(player.position);
      final count = (counts[key] ?? 0) + 1;
      counts[key] = count;
      totalWeight += count * GreedyDraftRepository._positionPenalty;
    }
  }

  return totalWeight;
}

String _normalizePosition(String? position) {
  final normalized = position?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return 'none';
  }
  return normalized;
}

double _calculateRulePenalty({
  required List<NormalizedDraftRule> rules,
  required Map<int, int> playerTeamIndex,
}) {
  var penalty = 0.0;

  for (final rule in rules) {
    switch (rule.type) {
      case DraftRuleType.together:
        final firstTeam = playerTeamIndex[rule.playerIndexes.first];
        if (firstTeam == null) {
          break;
        }

        final satisfied = rule.playerIndexes
            .skip(1)
            .every((playerIndex) => playerTeamIndex[playerIndex] == firstTeam);

        if (!satisfied) {
          penalty += GreedyDraftRepository._rulePenalty;
        }
        break;
      case DraftRuleType.against:
        final teamIndexes = <int>{};
        var satisfied = true;

        for (final playerIndex in rule.playerIndexes) {
          final teamIndex = playerTeamIndex[playerIndex];
          if (teamIndex == null) {
            continue;
          }

          if (!teamIndexes.add(teamIndex)) {
            satisfied = false;
            break;
          }
        }

        if (!satisfied) {
          penalty += GreedyDraftRepository._rulePenalty;
        }
        break;
    }
  }

  return penalty;
}

double _calculateTieBreaker(List<DraftTeam> teams) {
  if (teams.length < 2) {
    return 0.0;
  }

  final sortedRankingsByTeam = teams
      .map(
        (team) =>
            team.players.map((p) => p.ranking).toList(growable: false)
              ..sort((a, b) => b.compareTo(a)),
      )
      .toList(growable: false);

  final maxLength = sortedRankingsByTeam
      .map((r) => r.length)
      .reduce((value, element) => value > element ? value : element);

  var sumSquares = 0.0;

  for (var rankIndex = 0; rankIndex < maxLength; rankIndex++) {
    final values = <double>[];

    for (final teamRankings in sortedRankingsByTeam) {
      if (rankIndex < teamRankings.length) {
        values.add(teamRankings[rankIndex]);
      }
    }

    for (var i = 0; i < values.length; i++) {
      for (var j = i + 1; j < values.length; j++) {
        final diff = values[i] - values[j];
        sumSquares += diff * diff;
      }
    }
  }

  return sumSquares;
}

String _buildSignature(List<DraftTeam> teams) {
  final teamKeys =
      teams
          .map(
            (team) =>
                team.players.map((p) => p.playerId).toList(growable: false)
                  ..sort(),
          )
          .map((ids) => ids.join(','))
          .toList(growable: false)
        ..sort();

  return teamKeys.join('|');
}

int _mixSeed(int seed, int iteration) {
  var hash = 0x811C9DC5;
  hash = _fnv1a32Int(hash, seed);
  hash = _fnv1a32Int(hash, iteration);
  return hash & 0x7FFFFFFF;
}

int _randomSeed() => Random().nextInt(0x7FFFFFFF);

int _stableHash32({required String input, required int salt}) {
  var hash = 0x811C9DC5;
  hash = _fnv1a32Int(hash, salt);
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

int _fnv1a32Int(int hash, int input) {
  var h = hash;
  var value = input;

  for (var i = 0; i < 4; i++) {
    h ^= (value & 0xFF);
    h = (h * 0x01000193) & 0xFFFFFFFF;
    value >>= 8;
  }

  return h;
}

class _CandidatePick {
  final int playerIndex;
  final int remainingPosition;
  final double ratio;
  final double weight;
  final double ranking;
  final int tieBreaker;

  const _CandidatePick({
    required this.playerIndex,
    required this.remainingPosition,
    required this.ratio,
    required this.weight,
    required this.ranking,
    required this.tieBreaker,
  });
}

class _TeamWithKey {
  final String key;
  final List<Player> players;
  final double totalRanking;

  const _TeamWithKey({
    required this.key,
    required this.players,
    required this.totalRanking,
  });
}

class _GreedyGenerationInput {
  final List<Player> sortedPlayers;
  final List<NormalizedDraftRule> normalizedRules;
  final Map<int, List<NormalizedDraftRule>> rulesByPlayer;
  final List<int> targetTeamSizes;
  final int candidatePoolSize;
  final bool playWithSubstitute;
  final int processSeed;
  final int iterations;
  final int requestedLimit;
  final bool stopWhenStalled;

  const _GreedyGenerationInput({
    required this.sortedPlayers,
    required this.normalizedRules,
    required this.rulesByPlayer,
    required this.targetTeamSizes,
    required this.candidatePoolSize,
    required this.playWithSubstitute,
    required this.processSeed,
    required this.iterations,
    required this.requestedLimit,
    required this.stopWhenStalled,
  });
}
