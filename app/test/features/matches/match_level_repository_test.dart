import 'dart:convert';
import 'package:app/features/matches/infrastructure/repositories/supabase_match_level_repository.dart';
import 'package:app/features/matches/domain/match_level.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient fixture(
  Object? Function(http.Request) respond, {
  int status = 200,
  String Function(String)? transform,
}) {
  final client = SupabaseClient(
    'https://fixture.invalid',
    'fixture-key',
    httpClient: MockClient(
      (r) async => http.Response(
        transform?.call(jsonEncode(respond(r))) ?? jsonEncode(respond(r)),
        status,
        headers: {'content-type': 'application/json'},
        request: r,
      ),
    ),
  );
  addTearDown(client.dispose);
  return client;
}

List<Map<String, Object?>> matches(int n, {int score = 0}) => [
  for (var i = 0; i < n; i++)
    {'match_id': 'm$i', 'home_score': 0, 'away_score': score},
];

void main() {
  for (final completed in [25, 26]) {
    test(
      '$completed completed: excludes null scores, counts 0-0, historical mean stable',
      () async {
        var stage = 0;
        final requests = <Uri>[];
        final client = fixture((r) {
          requests.add(r.url);
          return switch (r.url.pathSegments.last) {
            'matches' => [
              ...matches(completed, score: stage),
              {'match_id': 'no-result', 'home_score': null, 'away_score': null},
              {'match_id': 'partial', 'home_score': 3, 'away_score': null},
            ],
            'team_players' => [
              for (final id in ['a', 'b', 'c'])
                {'match_id': 'm0', 'player_id': id},
            ],
            'ranking_history' => [
              for (final id in ['a', 'b', 'c'])
                {
                  'match_id': 'm0',
                  'player_id': id,
                  'ranking': id == 'c' ? 100 : 10,
                  'change': stage * 100,
                },
            ],
            _ => throw StateError('Unexpected fallback'),
          };
        });
        final repo = SupabaseMatchLevelRepository(client);
        for (stage = 0; stage < 4; stage++) {
          final data = await repo.loadHistory('s');
          expect(data.completedMatches, completed);
          if (completed == 25) {
            expect(data.means, isEmpty);
          } else {
            expect(data.means['m0'], 40);
            expect(data.means['no-result'], isNull);
            expect(
              requests
                  .where((r) => r.path.endsWith('ranking_history'))
                  .last
                  .queryParameters['select'],
              'match_id,player_id,ranking',
            );
          }
        }
        expect(requests.first.queryParameters['squad_id'], 'eq.s');
        expect(requests.any((r) => r.path.endsWith('/players')), isFalse);
      },
    );
  }
  for (final corrupt in ['missing', 'duplicate', 'null']) {
    test(
      '$corrupt match history hides rather than uses display fallback',
      () async {
        final client = fixture(
          (r) => switch (r.url.pathSegments.last) {
            'matches' => matches(26),
            'team_players' => [
              {'match_id': 'm0', 'player_id': 'p'},
            ],
            'ranking_history' => [
              if (corrupt != 'missing')
                {
                  'match_id': 'm0',
                  'player_id': 'p',
                  'ranking': corrupt == 'null' ? null : 50,
                },
              if (corrupt == 'duplicate')
                {'match_id': 'm0', 'player_id': 'p', 'ranking': 90},
            ],
            _ => throw StateError('Unexpected fallback'),
          },
        );
        expect(
          (await SupabaseMatchLevelRepository(
            client,
          ).loadHistory('s')).means['m0'],
          isNull,
        );
      },
    );
  }
  test(
    'settings persist independently; null remains the baseline marker, not a database default',
    () async {
      final settings = <String, Object?>{};
      final client = fixture((r) {
        final id = r.url.queryParameters['squad_id']!;
        if (r.method == 'PATCH') {
          settings[id] = jsonDecode(r.body)['star_thresholds'];
          return {'squad_id': id};
        }
        return {'star_thresholds': settings[id]};
      });
      final repo = SupabaseMatchLevelRepository(client);
      expect(await repo.loadThresholds('a'), isNull);
      await repo.saveThresholds(
        'a',
        MatchLevelThresholds([10, 30, 70, 90, 150]),
      );
      expect((await repo.loadThresholds('a'))!.full, [10, 30, 70, 90, 150]);
      expect(await repo.loadThresholds('b'), isNull);
    },
  );
  test(
    'read and save failures propagate; zero-row update is not success',
    () async {
      for (final status in [403, 406]) {
        final repo = SupabaseMatchLevelRepository(
          fixture((_) => {'message': 'denied'}, status: status),
        );
        await expectLater(
          repo.loadThresholds('a'),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          repo.loadHistory('a'),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          repo.saveThresholds('a', MatchLevelThresholds([1, 2, 3, 4, 5])),
          throwsA(isA<PostgrestException>()),
        );
      }
    },
  );
  for (final invalid in <Object?>[
    'NaN',
    'Infinity',
    '-Infinity',
    'invalid',
    true,
    {'bad': 50},
    null,
    'overflow',
  ]) {
    test(
      'HTTP-decoded invalid history hides only its match: $invalid',
      () async {
        final client = fixture(
          (r) => switch (r.url.pathSegments.last) {
            'matches' => matches(26),
            'team_players' => [
              for (final id in ['m0', 'm1']) {'match_id': id, 'player_id': 'p'},
            ],
            'ranking_history' => [
              {'match_id': 'm0', 'player_id': 'p', 'ranking': invalid},
              {'match_id': 'm1', 'player_id': 'p', 'ranking': 60},
            ],
            _ => throw StateError('Unexpected history fallback'),
          },
          transform: (body) => body.replaceAll('"overflow"', '1e999'),
        );
        final data = await SupabaseMatchLevelRepository(
          client,
        ).loadHistory('s');
        expect(data.means['m0'], isNull);
        expect(data.means['m1'], 60);
      },
    );
  }
  test(
    '501 matches, child pages over 500, disjoint 100-ID chunks and unrelated history',
    () async {
      final all = [
        for (var i = 0; i < 501; i++) 'm${i.toString().padLeft(3, '0')}',
      ];
      final requests = <Uri>[];
      final client = fixture((r) {
        requests.add(r.url);
        final q = r.url.queryParameters;
        final table = r.url.pathSegments.last;
        final offset = int.parse(q['offset']!);
        if (table == 'matches') {
          expect(q['squad_id'], 'eq.target-squad');
          return all
              .skip(offset)
              .take(500)
              .map((id) => {'match_id': id, 'home_score': 0, 'away_score': 0})
              .toList();
        }
        final selected = q['match_id']!
            .substring(4, q['match_id']!.length - 1)
            .split(',')
            .map((id) => id.replaceAll('"', ''))
            .toList();
        expect(selected.length, lessThanOrEqualTo(100));
        expect(selected.every(all.contains), isTrue);
        final rows = [
          for (final id in selected) ...[
            for (var p = 0; p < 7; p++)
              {
                'match_id': id,
                'player_id': '$id-p$p',
                if (table == 'ranking_history')
                  'ranking': int.parse(id.substring(1)) + p,
              },
            if (table == 'ranking_history')
              {'match_id': id, 'player_id': 'not-in-roster', 'ranking': 999999},
          ],
        ];
        return rows.skip(offset).take(500).toList();
      });
      final data = await SupabaseMatchLevelRepository(
        client,
      ).loadHistory('target-squad');
      expect(data.completedMatches, 501);
      expect(data.means.length, 501);
      for (var i = 0; i < 501; i++) {
        expect(data.means[all[i]], closeTo(i + 3, 1e-10));
      }
      expect(
        requests
            .where((r) => r.pathSegments.last == 'matches')
            .map((r) => r.queryParameters['offset']),
        ['0', '500'],
      );
      for (final table in ['team_players', 'ranking_history']) {
        final calls = requests.where((r) => r.pathSegments.last == table);
        expect(
          calls.where((r) => r.queryParameters['offset'] == '500').length,
          5,
        );
        expect(
          calls.where((r) => r.queryParameters['offset'] == '0').length,
          6,
        );
      }
    },
  );
}
