// Synthetic PostgREST transport for repository tests and browser evidence.
// This is not a database or an RLS proof. Unexpected requests fail closed.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SnapshotBackend extends http.BaseClient {
  static const date = '2026-11-16T12:00:00.000Z';
  final tables = <String, List<Map<String, dynamic>>>{};
  final requests = <String>[];
  void Function()? onWrite;
  late final client = SupabaseClient(
    'http://snapshot-fixture.invalid',
    'fixture-not-a-credential',
    httpClient: this,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  SnapshotBackend({bool substitutes = false, int count = 5}) {
    tables['players'] = [
      for (final (i, score) in [
        41.25,
        63.75,
        38.5,
        72.25,
        56.5,
      ].take(count).indexed)
        {
          'player_id': 'p$i',
          'squad_id': 'fixture',
          'name': ['Adam', 'Bartek', 'Cezary', 'Dawid', 'Emil'][i],
          'base_score': 50,
          'score': score,
          'created_at': date,
        },
    ];
    tables['matches'] = [
      {
        'match_id': 'match',
        'squad_id': 'fixture',
        'created_at': date,
        'play_with_substitute': substitutes,
        'tournament_id': null,
        'home_score': null,
        'away_score': null,
        'home_win_prob': 0.5,
      },
    ];
    tables['teams'] = [
      for (final side in ['home', 'away'])
        {
          'team_id': side,
          'match_id': 'match',
          'side': side,
          'color': side == 'home' ? '#FFFFFF' : '#000000',
          'created_at': date,
        },
    ];
    tables['team_players'] = [
      for (var i = 0; i < count; i++)
        {
          'match_id': 'match',
          'team_id': i < 2 ? 'home' : 'away',
          'player_id': 'p$i',
        },
    ];
    tables['ranking_history'] = [
      for (final player in tables['players']!)
        {
          'ranking_history_id': 'r-${player['player_id']}',
          'match_id': 'match',
          'player_id': player['player_id'],
          'ranking': player['score'],
          'change': null,
          'created_at': date,
        },
    ];
    tables['squads'] = [
      {
        'squad_id': 'fixture',
        'owner_id': 'owner',
        'name': 'Fixture — issue #60',
        'visibility': 'private',
        'sport_type': 'football',
        'created_at': date,
        'ranking_update': true,
        'ranking_multiplier': 5,
        'use_experience_factor': false,
      },
    ];
    tables['user_squads'] = [];
    tables['drafts'] = [];
    tables['draft_payloads'] = [];
  }

  void changeCurrentScores() {
    for (final (i, player) in tables['players']!.indexed) {
      player['score'] = [90.0, 20.0, 40.0, 30.0, 50.0][i];
    }
  }

  bool _matches(Map<String, dynamic> row, Map<String, String> query) {
    for (final entry in query.entries) {
      if (['select', 'order', 'limit', 'on_conflict'].contains(entry.key)) {
        continue;
      }
      final value = row[entry.key];
      final filter = entry.value;
      if (filter.startsWith('eq.')) {
        if (value.toString() != filter.substring(3)) return false;
      } else if (filter.startsWith('in.(')) {
        if (!filter
            .substring(4, filter.length - 1)
            .replaceAll('"', '')
            .split(',')
            .contains(value.toString())) {
          return false;
        }
      } else {
        throw StateError('Unsupported fixture filter ${entry.key}=$filter');
      }
    }
    return true;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add('${request.method} ${request.url.path}');
    final body = await request.finalize().bytesToString();
    final name = request.url.pathSegments.last;
    final rows = tables[name];
    if (request.url.path.contains('/rpc/')) {
      if (name != 'refresh_match_win_probability') {
        throw StateError('Unexpected RPC $name');
      }
      return _response(null, request);
    }
    if (rows == null) throw StateError('Unexpected table $name');
    final query = request.url.queryParameters;
    final found = rows.where((row) => _matches(row, query)).toList();
    switch (request.method) {
      case 'GET':
        return _response(
          request.headers['Accept']?.contains('vnd.pgrst.object') == true
              ? found.single
              : found,
          request,
        );
      case 'PATCH':
        for (final row in found) {
          row.addAll(Map<String, dynamic>.from(jsonDecode(body) as Map));
        }
        onWrite?.call();
        return _response(found, request);
      case 'DELETE':
        rows.removeWhere((row) => found.contains(row));
        return _response(null, request);
      case 'POST':
        final decoded = jsonDecode(body);
        final incoming = decoded is List ? decoded : [decoded];
        final result = <Map<String, dynamic>>[];
        for (final raw in incoming) {
          final row = Map<String, dynamic>.from(raw as Map);
          final key = query['on_conflict'];
          final prior = key == null
              ? <Map<String, dynamic>>[]
              : rows.where((r) => r[key] == row[key]).toList();
          if (prior.isNotEmpty) {
            prior.single.addAll(row);
            result.add(prior.single);
          } else {
            if (name == 'drafts') row['draft_id'] = 'draft';
            if (name == 'ranking_history') {
              row['ranking_history_id'] = 'r-${row['player_id']}';
              row['created_at'] = date;
            }
            rows.add(row);
            result.add(row);
          }
        }
        return _response(
          request.headers['Accept']?.contains('vnd.pgrst.object') == true
              ? result.single
              : result,
          request,
        );
      default:
        throw StateError('Unexpected fixture method ${request.method}');
    }
  }

  http.StreamedResponse _response(Object? value, http.BaseRequest request) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(value))),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: request,
      );
}
