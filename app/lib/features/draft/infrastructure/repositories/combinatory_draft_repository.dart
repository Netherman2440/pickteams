import 'package:app/core/error/failure.dart';
import 'package:app/core/utils/team_ranking.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_proposal.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/entities/normalized_draft_rule.dart';
import 'package:app/features/draft/domain/repositories/draft_repository.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:logging/logging.dart';

class CombinatoryDraftRepository implements DraftRepository {
  const CombinatoryDraftRepository();

  static final Logger _logger = Logger('CombinatoryDraftRepository');
  static const int _minTeamCount = 2;
  static const int _maxTeamCount = 4;
  static const Duration _uiYieldBudget = Duration(milliseconds: 2);
  static const double _rulePenalty = 100.0;
  static const double _positionPenalty = 100.0;

  @override
  Future<List<Draft>> createDraft({
    required List<Player> players,
    int teamCount = 2,
    List<DraftRule> rules = const [],
    int limit = 20,
    bool playWithSubstitute = true,
    int? seed,
  }) async {
    final startedAt = DateTime.now();
    _logger.info(
      'createDraft started: startedAt=${startedAt.toIso8601String()} teamCount=$teamCount players=${players.length} limit=$limit',
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

    final sortedPlayers = [...players]
      ..sort((a, b) => a.playerId.compareTo(b.playerId));

    final normalizedRules = _normalizeRules(
      rules: rules,
      playersById: {for (final p in sortedPlayers) p.playerId: p},
    );

    final teamSizes = _calculateTeamSizes(
      playerCount: sortedPlayers.length,
      teamCount: teamCount,
    );

    final proposals = <DraftProposal>[];
    final allPlayersMask = (1 << sortedPlayers.length) - 1;

    final yieldStopwatch = Stopwatch()..start();
    for (final teamMasks in _generatePartitions(
      remainingMask: allPlayersMask,
      remainingTeamSizes: teamSizes,
      currentTeamMasks: <int>[],
    )) {
      final proposal = _buildProposal(
        sortedPlayers: sortedPlayers,
        teamMasks: teamMasks,
        rules: normalizedRules,
        playWithSubstitute: playWithSubstitute,
      );
      proposals.add(proposal);

      if (yieldStopwatch.elapsed >= _uiYieldBudget) {
        // Yield frequently based on elapsed time to keep UI responsive
        // even on large combinatory datasets.
        await Future<void>.delayed(Duration.zero);
        yieldStopwatch.reset();
      }
    }

    final scoredProposals = _applyEqualWeightScoring(proposals);

    scoredProposals.sort((a, b) {
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
        .map((p) => p.draft)
        .toList(growable: false);
    final finishedAt = DateTime.now();
    final elapsedMs = finishedAt.difference(startedAt).inMilliseconds;
    _logger.info(
      'createDraft completed: finishedAt=${finishedAt.toIso8601String()} elapsedMs=$elapsedMs teamCount=$teamCount players=${players.length} proposals=${proposals.length} returned=${result.length}',
    );
    return result;
  }
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
  );
}

Iterable<List<int>> _generatePartitions({
  required int remainingMask,
  required List<int> remainingTeamSizes,
  required List<int> currentTeamMasks,
}) sync* {
  if (remainingTeamSizes.isEmpty) {
    yield currentTeamMasks;
    return;
  }

  final currentTeamSize = remainingTeamSizes.first;

  if (remainingTeamSizes.length == 1) {
    if (_popcount(remainingMask) == currentTeamSize) {
      yield [...currentTeamMasks, remainingMask];
    }
    return;
  }

  final forcedBit = remainingMask & -remainingMask;
  if (forcedBit == 0) {
    return;
  }

  final candidates = _subsetsWithRequiredBit(
    universeMask: remainingMask,
    subsetSize: currentTeamSize,
    requiredBit: forcedBit,
  );

  final nextTeamSizes = remainingTeamSizes.sublist(1);

  for (final teamMask in candidates) {
    yield* _generatePartitions(
      remainingMask: remainingMask & ~teamMask,
      remainingTeamSizes: nextTeamSizes,
      currentTeamMasks: [...currentTeamMasks, teamMask],
    );
  }
}

Iterable<int> _subsetsWithRequiredBit({
  required int universeMask,
  required int subsetSize,
  required int requiredBit,
}) sync* {
  if ((universeMask & requiredBit) == 0 || subsetSize <= 0) {
    return;
  }

  final poolMask = universeMask & ~requiredBit;
  final poolIndexes = _setBitIndexes(poolMask);
  final chooseCount = subsetSize - 1;

  if (chooseCount == 0) {
    yield requiredBit;
    return;
  }

  if (chooseCount > poolIndexes.length) {
    return;
  }

  for (final localMask in _gosperCombinations(
    bits: poolIndexes.length,
    ones: chooseCount,
  )) {
    var subsetMask = requiredBit;
    for (var i = 0; i < poolIndexes.length; i++) {
      if ((localMask & (1 << i)) != 0) {
        subsetMask |= 1 << poolIndexes[i];
      }
    }
    yield subsetMask;
  }
}

Iterable<int> _gosperCombinations({
  required int bits,
  required int ones,
}) sync* {
  if (ones < 0 || bits < 0 || ones > bits) {
    return;
  }

  if (ones == 0) {
    yield 0;
    return;
  }

  var x = (1 << ones) - 1;
  final limit = 1 << bits;

  while (x < limit) {
    yield x;

    final c = x & -x;
    final r = x + c;
    x = (((r ^ x) >> 2) ~/ c) | r;
  }
}

List<int> _setBitIndexes(int mask) {
  final indexes = <int>[];
  var index = 0;
  var value = mask;

  while (value != 0) {
    if ((value & 1) == 1) {
      indexes.add(index);
    }
    value >>= 1;
    index += 1;
  }

  return indexes;
}

DraftProposal _buildProposal({
  required List<Player> sortedPlayers,
  required List<int> teamMasks,
  required List<NormalizedDraftRule> rules,
  required bool playWithSubstitute,
}) {
  final teams = <DraftTeam>[];
  final playerTeamIndex = <int, int>{};

  for (var teamIndex = 0; teamIndex < teamMasks.length; teamIndex++) {
    final mask = teamMasks[teamIndex];
    final players = <Player>[];
    var totalRanking = 0.0;

    for (var i = 0; i < sortedPlayers.length; i++) {
      if ((mask & (1 << i)) == 0) {
        continue;
      }

      final player = sortedPlayers[i];
      players.add(player);
      playerTeamIndex[i] = teamIndex;
      totalRanking += player.ranking;
    }

    teams.add(
      DraftTeam(index: teamIndex, players: players, totalRanking: totalRanking),
    );
  }

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
    draft: Draft(teams: teams, playWithSubstitute: playWithSubstitute),
    score: 0.0,
    deviationScore: deviationScore,
    penaltyScore: penaltyScore,
    rulePenalty: rulePenalty,
    tieBreaker: tieBreaker,
    signature: signature,
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
      totalWeight += count * CombinatoryDraftRepository._positionPenalty;
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
          penalty += CombinatoryDraftRepository._rulePenalty;
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
          penalty += CombinatoryDraftRepository._rulePenalty;
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
  final teamKeys = teams
      .map(
        (team) =>
            team.players.map((p) => p.playerId).toList(growable: false)..sort(),
      )
      .map((ids) => ids.join(','))
      .toList(growable: false);

  return teamKeys.join('|');
}

int _popcount(int value) {
  var v = value;
  var count = 0;
  while (v != 0) {
    v &= v - 1;
    count += 1;
  }
  return count;
}
