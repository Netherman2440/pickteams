// Isolated synthetic PostgREST transport. Production repositories parse all rows.
import 'dart:convert';

import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/repositories/match_repository.dart';
import 'package:app/features/matches/application/usecases/get_match_usecase.dart';
import 'package:app/features/matches/infrastructure/repositories/supabase_team_repository.dart';
import 'package:app/features/players/infrastructure/repositories/supabase_ranking_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricalMatchData {
  HistoricalMatchData({this.unequal = false}) {
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-key',
      httpClient: MockClient(_respond),
    );
  }

  final bool unequal;
  late final SupabaseClient client;
  final requests = <Uri>[];
  final snapshots = <String, double>{
    'p0': 40,
    'p1': 60,
    'p2': 50,
    'p3': 70,
    'p4': 30,
  };
  final scores = <String, double>{
    'p0': 40,
    'p1': 60,
    'p2': 50,
    'p3': 70,
    'p4': 30,
  };
  final deltas = <String, double?>{};
  final missing = <String>{};
  String? tournamentId;
  final tournamentRanks = <String, double>{};
  int stage = 0;

  List<String> ids(String side) =>
      side == 'home' ? ['p0', 'p1', if (unequal) 'p4'] : ['p2', 'p3'];

  GetMatchUseCase get reader =>
      GetMatchUseCase(_MatchRead(this), SupabaseTeamRepository(client));

  // Exercise the existing writer as result/correction/manual scores change.
  Future<void> advance() async {
    final writer = SupabaseRankingRepository(client);
    stage++;
    for (final id in snapshots.keys) {
      await writer.updatePlayerRanking(
        playerId: id,
        matchId: stage < 3 ? 'match' : null,
        newRanking: stage == 1
            ? (id == 'p0' ? 95 : 10)
            : stage == 2
            ? (id == 'p0' ? 15 : 85)
            : (id == 'p0' ? 150 : 5),
      );
    }
  }

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request.url);
    final table = request.url.pathSegments.last;
    final q = request.url.queryParameters;
    final playerId = q['player_id']?.replaceFirst('eq.', '');
    Object? result;
    if (request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (table == 'players') {
        scores[playerId!] = (body['score'] as num).toDouble();
      }
      if (table == 'ranking_history') {
        final id = q['ranking_history_id']!.replaceFirst('eq.history-', '');
        deltas[id] = (body['change'] as num).toDouble();
      }
      return http.Response('', 204, request: request);
    }
    if (request.method == 'POST') {
      return http.Response('', 201, request: request);
    }
    switch (table) {
      case 'matches':
        result = {'tournament_id': tournamentId};
      case 'teams':
        result = [
          for (final side in ['home', 'away'])
            {
              'team_id': side,
              'match_id': 'match',
              'side': side,
              'color': side == 'home' ? '#E53935' : '#1E88E5',
              'created_at': '2026-01-01T00:00:00Z',
            },
        ];
      case 'team_players':
        result = [
          for (final id in ids(q['team_id']!.replaceFirst('eq.', '')))
            {'player_id': id},
        ];
      case 'players':
        final selected = q['player_id'] ?? '';
        result = [
          for (final id in scores.keys)
            if (selected.contains(id))
              {
                'player_id': id,
                'squad_id': 'fixture',
                'name': 'Player $id',
                'base_score': 50,
                'score': scores[id],
                'created_at': '2026-01-01T00:00:00Z',
              },
        ];
        if (playerId != null && !playerId.startsWith('in.')) {
          result = (result as List).first;
        }
      case 'ranking_history':
        if (q.containsKey('created_at')) {
          result = [];
        } else if (q.containsKey('tournament_id')) {
          result = [
            for (final e in tournamentRanks.entries)
              if (q['player_id']!.contains(e.key))
                {'player_id': e.key, 'ranking': e.value},
          ];
        } else {
          result = [
            for (final id in snapshots.keys)
              if (!missing.contains(id) && q['player_id']!.contains(id))
                {
                  'ranking_history_id': 'history-$id',
                  'player_id': id,
                  'match_id': 'match',
                  'ranking': snapshots[id],
                  'change': deltas[id],
                  'created_at': '2026-01-01T00:00:00Z',
                },
          ];
          if (q['player_id']!.startsWith('eq.')) {
            result = (result as List).first;
          }
        }
      default:
        throw StateError('Unexpected synthetic request: ${request.url}');
    }
    return http.Response(
      jsonEncode(result),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

class _MatchRead implements MatchRepository {
  _MatchRead(this.data);
  final HistoricalMatchData data;
  @override
  Future<Match> getMatch({required String matchId}) async => Match(
    matchId: matchId,
    squadId: 'fixture',
    createdAt: DateTime(2026),
    homeScore: data.stage == 0
        ? null
        : data.stage == 1
        ? 3
        : 1,
    awayScore: data.stage == 0
        ? null
        : data.stage == 1
        ? 1
        : 4,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
