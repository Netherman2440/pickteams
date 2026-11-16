import 'dart:convert';
import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/infrastructure/repositories/supabase_goal_comparison_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> row({String? type, Object? meta = const {}}) => {
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
  test('tournament snapshots reach calculation, including mixed history', () {
    // The creator persists these IDs; the score writer leaves them unchanged.
    const tournamentMeta = {
      'tournament_home_team_id': 'tournament-red',
      'tournament_away_team_id': 'tournament-blue',
    };
    Map<String, dynamic> snapshot(
      int gf,
      int ga,
      bool present, {
      bool tournament = true,
    }) {
      final result = row(meta: tournament ? tournamentMeta : const {})
        ..['home_score'] = gf
        ..['away_score'] = ga;
      (result['teams'] as List)[0]['team_players'] = [
        {'player_id': present ? 'historical-id' : 'absent-replacement'},
      ];
      return result;
    }

    final history = [snapshot(6, 2, true), snapshot(2, 3, false)];
    GoalComparison compare(List<Map<String, dynamic>> rows) =>
        comparePlayerGoals(
          rows.map(decodeGoalComparisonMatch).toList(),
          'historical-id',
        );
    final tournament = compare(history);
    expect(tournament.unavailable, isNull);
    expect(tournament.scored, 4);
    expect(tournament.conceded, -1);

    final mixed = compare([
      ...history,
      snapshot(4, 4, true, tournament: false),
      snapshot(2, 3, false, tournament: false),
      for (final type in ['penalties', 'walkover', 'unknown'])
        snapshot(99, 0, true)..['score_type'] = type,
      for (final meta in [
        {'sets': []},
        {'unknown': true},
      ])
        snapshot(99, 0, true)..['score_meta'] = {...tournamentMeta, ...meta},
    ]);
    expect(mixed.unavailable, isNull);
    expect(mixed.scored, 3);
    expect(mixed.conceded, 0);
  });
  test('only ordinary goals with known non-scoring metadata are eligible', () {
    expect(decodeGoalComparisonMatch(row()).ordinaryGoals, isTrue);
    expect(
      decodeGoalComparisonMatch(row(type: 'regular')).ordinaryGoals,
      isTrue,
    );
    for (final type in ['cancelled', 'penalties', 'walkover', 'unknown']) {
      expect(decodeGoalComparisonMatch(row(type: type)).ordinaryGoals, isFalse);
    }
    for (final meta in [
      null,
      const {},
      {'tournament_home_team_id': 'red', 'tournament_away_team_id': 'blue'},
    ]) {
      expect(decodeGoalComparisonMatch(row(meta: meta)).ordinaryGoals, isTrue);
    }
    for (final meta in [
      'unknown',
      [],
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
