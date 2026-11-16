import 'dart:convert';
import 'package:app/features/players/infrastructure/repositories/supabase_goal_comparison_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> row({
  String? type,
  Map<String, dynamic> meta = const {},
}) => {
  'match_id': 'm',
  'home_score': 2,
  'away_score': 1,
  'score_type': type,
  'score_meta': meta,
  'teams': [
    {
      'side': 'home',
      'color': '#ff0000',
      'team_players': [
        {'player_id': 'historical-id'},
      ],
    },
    {
      'side': 'away',
      'color': '#0000ff',
      'team_players': [
        {'player_id': 'other'},
      ],
    },
  ],
};

void main() {
  test(
    'uses squad filter, stable paging and persisted IDs, not player history',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://fixture.invalid',
        'fixture-key',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode(
              requests.length == 1 ? List.generate(200, (_) => row()) : [row()],
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final matches = await SupabaseGoalComparisonRepository(
        client,
      ).getSquadHistory('squad');
      expect(matches.length, 201);
      expect(matches.first.home!.playerIds, ['historical-id']);
      expect(requests.length, 2);
      expect(requests.first.queryParameters['squad_id'], 'eq.squad');
      expect(requests.first.queryParameters['order'], 'match_id.asc.nullslast');
      expect(requests.first.queryParameters['offset'], '0');
      expect(requests.last.queryParameters['offset'], '200');
      expect(
        requests.first.queryParameters['select'],
        contains('team_players!team_players_team_fk(player_id)'),
      );
    },
  );
  test(
    'repository propagates read failure, never returns an empty baseline',
    () async {
      final client = SupabaseClient(
        'https://fixture.invalid',
        'fixture-key',
        httpClient: MockClient(
          (request) async =>
              http.Response('{"message":"denied"}', 403, request: request),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseGoalComparisonRepository(client).getSquadHistory('squad'),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
  test('only ordinary goals with empty metadata are eligible', () {
    expect(decodeGoalComparisonMatch(row()).ordinaryGoals, isTrue);
    expect(
      decodeGoalComparisonMatch(row(type: 'regular')).ordinaryGoals,
      isTrue,
    );
    for (final type in ['cancelled', 'penalties', 'walkover', 'unknown']) {
      expect(decodeGoalComparisonMatch(row(type: type)).ordinaryGoals, isFalse);
    }
    for (final meta in [
      {'cancelled': true},
      {
        'penalties': [4, 3],
      },
      {'sets': []},
      {'unknown': true},
    ]) {
      expect(decodeGoalComparisonMatch(row(meta: meta)).ordinaryGoals, isFalse);
    }
  });
  test(
    'missing or duplicate sides stay missing, not synthetic empty teams',
    () {
      final missing = row()..['teams'] = [];
      expect(decodeGoalComparisonMatch(missing).home, isNull);
      final duplicate = row();
      (duplicate['teams'] as List)[1]['side'] = 'home';
      expect(decodeGoalComparisonMatch(duplicate).home, isNull);
    },
  );
}
