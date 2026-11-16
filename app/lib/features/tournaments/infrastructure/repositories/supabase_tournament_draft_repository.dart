import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app/core/error/supabase_error_extension.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/matches/infrastructure/repositories/preserved_rankings.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/tournaments/domain/entities/tournament_draft.dart';
import 'package:app/features/tournaments/domain/repositories/tournament_draft_repository.dart';

class SupabaseTournamentDraftRepository implements TournamentDraftRepository {
  final SupabaseClient _supabase;
  final Logger _logger = Logger('SupabaseTournamentDraftRepository');

  SupabaseTournamentDraftRepository(this._supabase);

  @override
  Future<String> createCompletedDraft({
    required String squadId,
    required String tournamentId,
    required List<String> selectedPlayerIds,
    required int teamCount,
    required List<DraftRule> rules,
    required List<Draft> proposals,
    required Map<String, Map<String, double>> winRateMatrix,
    int? seed,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final draftResponse = await _supabase
          .from('tournament_drafts')
          .insert({
            'squad_id': squadId,
            'tournament_id': tournamentId,
            'status': 'completed',
            'team_count': teamCount,
            'proposals_count': proposals.length,
            'error_message': null,
            'updated_at': now,
          })
          .select('tournament_draft_id')
          .single();

      final draftId = (draftResponse as Map)['tournament_draft_id'] as String;

      await _supabase.from('tournament_draft_payloads').upsert({
        'tournament_draft_id': draftId,
        'proposals': _serializeProposals(proposals, seed: seed),
        'win_rate_matrix': _serializeWinRateMatrix(winRateMatrix),
        'rules': _serializeRules(rules),
        'selected_player_ids': selectedPlayerIds,
        'updated_at': now,
      }, onConflict: 'tournament_draft_id');

      return draftId;
    } catch (e, stack) {
      _logger.severe('Failed to save completed tournament draft', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<String> createErrorDraft({
    required String squadId,
    required String tournamentId,
    required int teamCount,
    required String errorMessage,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final draftResponse = await _supabase
          .from('tournament_drafts')
          .insert({
            'squad_id': squadId,
            'tournament_id': tournamentId,
            'status': 'error',
            'team_count': teamCount,
            'proposals_count': 0,
            'error_message': errorMessage,
            'updated_at': now,
          })
          .select('tournament_draft_id')
          .single();

      final draftId = (draftResponse as Map)['tournament_draft_id'] as String;

      await _supabase.from('tournament_draft_payloads').upsert({
        'tournament_draft_id': draftId,
        'proposals': const <Map<String, dynamic>>[],
        'win_rate_matrix': const <String, dynamic>{},
        'rules': const <Map<String, dynamic>>[],
        'selected_player_ids': const <String>[],
        'updated_at': now,
      }, onConflict: 'tournament_draft_id');

      return draftId;
    } catch (e, stack) {
      _logger.severe('Failed to save tournament draft error', e, stack);
      throw e.toFailure();
    }
  }

  @override
  Future<List<TournamentDraft>> getTournamentDrafts({
    required String tournamentId,
  }) async {
    try {
      final response = await _supabase
          .from('tournament_drafts')
          .select(
            'tournament_draft_id, tournament_id, squad_id, status, team_count, proposals_count, error_message, created_at, updated_at',
          )
          .eq('tournament_id', tournamentId)
          .order('created_at', ascending: false);

      final rows = response as List<dynamic>;
      return rows
          .map(
            (row) =>
                _draftFromRows(draftRow: Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);
    } catch (e, stack) {
      _logger.severe(
        'Failed to load tournament drafts for tournament $tournamentId',
        e,
        stack,
      );
      throw e.toFailure();
    }
  }

  @override
  Future<TournamentDraft?> getTournamentDraft({
    required String tournamentDraftId,
  }) async {
    try {
      final draftRow = await _supabase
          .from('tournament_drafts')
          .select(
            'tournament_draft_id, tournament_id, squad_id, status, team_count, proposals_count, error_message, created_at, updated_at',
          )
          .eq('tournament_draft_id', tournamentDraftId)
          .maybeSingle();

      if (draftRow == null) {
        return null;
      }

      final payloadRow = await _supabase
          .from('tournament_draft_payloads')
          .select('proposals, win_rate_matrix, rules, selected_player_ids')
          .eq('tournament_draft_id', tournamentDraftId)
          .maybeSingle();

      return _draftFromRows(
        draftRow: Map<String, dynamic>.from(draftRow as Map),
        preservedRankings: await _loadTournamentRankings(
          draftRow['tournament_id'] as String,
        ),
        payloadRow: payloadRow == null
            ? null
            : Map<String, dynamic>.from(payloadRow as Map),
      );
    } catch (e, stack) {
      _logger.severe(
        'Failed to load tournament draft $tournamentDraftId',
        e,
        stack,
      );
      throw e.toFailure();
    }
  }

  @override
  Future<TournamentDraft?> getLatestTournamentDraft({
    required String tournamentId,
  }) async {
    try {
      final draftRow = await _supabase
          .from('tournament_drafts')
          .select(
            'tournament_draft_id, tournament_id, squad_id, status, team_count, proposals_count, error_message, created_at, updated_at',
          )
          .eq('tournament_id', tournamentId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (draftRow == null) {
        return null;
      }

      final draftMap = Map<String, dynamic>.from(draftRow as Map);
      final draftId = draftMap['tournament_draft_id'] as String;

      final payloadRow = await _supabase
          .from('tournament_draft_payloads')
          .select('proposals, win_rate_matrix, rules, selected_player_ids')
          .eq('tournament_draft_id', draftId)
          .maybeSingle();

      return _draftFromRows(
        draftRow: draftMap,
        preservedRankings: await _loadTournamentRankings(tournamentId),
        payloadRow: payloadRow == null
            ? null
            : Map<String, dynamic>.from(payloadRow as Map),
      );
    } catch (e, stack) {
      _logger.severe(
        'Failed to load latest tournament draft for tournament $tournamentId',
        e,
        stack,
      );
      throw e.toFailure();
    }
  }

  Future<Map<String, double>> _loadTournamentRankings(
    String tournamentId,
  ) async {
    final rows = await _supabase
        .from('ranking_history')
        .select('player_id, ranking')
        .eq('tournament_id', tournamentId)
        .isFilter('match_id', null);
    return {
      for (final row in rows)
        row['player_id'] as String: (row['ranking'] as num).toDouble(),
    };
  }
}

TournamentDraft _draftFromRows({
  required Map<String, dynamic> draftRow,
  Map<String, dynamic>? payloadRow,
  Map<String, double> preservedRankings = const {},
}) {
  final parsedProposals = _parseStoredProposals(
    payloadRow?['proposals'],
    preservedRankings,
  );

  return TournamentDraft(
    tournamentDraftId: draftRow['tournament_draft_id'] as String,
    tournamentId: draftRow['tournament_id'] as String,
    squadId: draftRow['squad_id'] as String,
    status: (draftRow['status'] as String?) ?? 'completed',
    teamCount: (draftRow['team_count'] as num?)?.toInt() ?? 2,
    proposalsCount: (draftRow['proposals_count'] as num?)?.toInt() ?? 0,
    errorMessage: draftRow['error_message'] as String?,
    createdAt: DateTime.parse(draftRow['created_at'] as String),
    updatedAt: DateTime.parse(draftRow['updated_at'] as String),
    seed: parsedProposals.seed,
    selectedPlayerIds: _parseSelectedPlayerIds(
      payloadRow?['selected_player_ids'],
    ),
    draftRules: _parseRules(payloadRow?['rules']),
    proposals: parsedProposals.proposals,
    winRateMatrix: _parseWinRateMatrix(payloadRow?['win_rate_matrix']),
  );
}

const String _proposalMetadataKey = '_meta';
const String _proposalSeedKey = 'seed';

List<Map<String, dynamic>> _serializeProposals(
  List<Draft> proposals, {
  int? seed,
}) {
  final serialized = <Map<String, dynamic>>[];
  if (seed != null) {
    serialized.add({
      _proposalMetadataKey: {_proposalSeedKey: seed},
    });
  }

  serialized.addAll(proposals.map((draft) => draft.toStoredProposal()));

  return serialized;
}

Map<String, dynamic> _serializeWinRateMatrix(
  Map<String, Map<String, double>> matrix,
) {
  return matrix.map(
    (playerId, opponents) => MapEntry(
      playerId,
      opponents.map((oppId, rate) => MapEntry(oppId, rate)),
    ),
  );
}

List<Map<String, dynamic>> _serializeRules(List<DraftRule> rules) {
  return [
    for (final rule in rules)
      {'type': rule.type.name, 'player_ids': rule.playerIds},
  ];
}

_ParsedStoredProposals _parseStoredProposals(
  dynamic raw,
  Map<String, double> preservedRankings,
) {
  if (raw is! List) {
    return const _ParsedStoredProposals(proposals: [], seed: null);
  }

  final proposals = <TournamentDraftProposal>[];
  int? seed;

  for (final proposalRaw in raw) {
    if (proposalRaw is! Map) {
      continue;
    }

    final proposalMap = Map<String, dynamic>.from(proposalRaw);
    final metadataRaw = proposalMap[_proposalMetadataKey];
    if (metadataRaw is Map) {
      final metadata = Map<String, dynamic>.from(metadataRaw);
      final parsedSeed = metadata[_proposalSeedKey];
      if (parsedSeed is num) {
        seed = parsedSeed.toInt();
      }
      continue;
    }

    final teamsRaw = proposalMap['teams'];
    if (teamsRaw is! List) {
      continue;
    }

    final teams = <List<String>>[];
    for (final teamRaw in teamsRaw) {
      if (teamRaw is! List) {
        continue;
      }
      teams.add(
        teamRaw.whereType<String>().where((id) => id.isNotEmpty).toList(),
      );
    }

    if (teams.isNotEmpty) {
      proposals.add(
        TournamentDraftProposal(
          teams: teams,
          rankings: resolveProposalRankings(
            proposal: proposalMap,
            playerIds: teams.expand((team) => team),
            preservedRankings: preservedRankings,
          ),
          playWithSubstitute: resolveProposalSubstitutes(proposalMap),
        ),
      );
    }
  }

  return _ParsedStoredProposals(
    proposals: proposals.toList(growable: false),
    seed: seed,
  );
}

List<String> _parseSelectedPlayerIds(dynamic raw) {
  if (raw is! List) {
    return const [];
  }

  return raw
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
}

List<DraftRule> _parseRules(dynamic raw) {
  if (raw is! List) {
    return const [];
  }

  final rules = <DraftRule>[];
  for (final row in raw) {
    if (row is! Map) {
      continue;
    }

    final map = Map<String, dynamic>.from(row);
    final typeRaw = map['type'];
    final playerIdsRaw = map['player_ids'];
    if (typeRaw is! String || playerIdsRaw is! List) {
      continue;
    }

    final type = switch (typeRaw) {
      'together' => DraftRuleType.together,
      'against' => DraftRuleType.against,
      _ => null,
    };

    if (type == null) {
      continue;
    }

    final playerIds = playerIdsRaw
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (playerIds.length < 2) {
      continue;
    }

    rules.add(DraftRule(type: type, playerIds: playerIds));
  }

  return rules;
}

Map<String, Map<String, double>> _parseWinRateMatrix(dynamic raw) {
  if (raw is! Map) {
    return const {};
  }

  final matrix = <String, Map<String, double>>{};

  for (final entry in raw.entries) {
    final playerId = entry.key;
    final value = entry.value;
    if (playerId is! String || value is! Map) {
      continue;
    }

    final opponents = <String, double>{};
    for (final oppEntry in value.entries) {
      final oppId = oppEntry.key;
      final rate = oppEntry.value;
      if (oppId is! String || rate is! num) {
        continue;
      }
      opponents[oppId] = rate.toDouble();
    }

    matrix[playerId] = opponents;
  }

  return matrix;
}

class _ParsedStoredProposals {
  final List<TournamentDraftProposal> proposals;
  final int? seed;

  const _ParsedStoredProposals({required this.proposals, required this.seed});
}
