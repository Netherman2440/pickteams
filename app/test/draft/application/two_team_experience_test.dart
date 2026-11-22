import 'dart:convert';
import 'dart:math';

import 'package:app/core/error/failure.dart';
import 'package:app/core/global_dependencies.dart';
import 'package:app/features/draft/application/create_draft_use_case.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_proposal.dart';
import 'package:app/features/draft/domain/repositories/draft_repository.dart';
import 'package:app/features/draft/domain/services/two_team_balance.dart';
import 'package:app/features/draft/infrastructure/repositories/combinatory_draft_repository.dart';
import 'package:app/features/draft/infrastructure/repositories/greedy_draft_repository.dart';
import 'package:app/features/draft/infrastructure/repositories/supabase_draft_experience_repository.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Player player(String id, [double rank = 50]) => Player(
  playerId: id,
  squadId: 'squad',
  name: id,
  baseRanking: rank.toInt(),
  ranking: rank,
  createdAt: DateTime.utc(2025),
);

Draft draft(List<Player> home, List<Player> away) => Draft.twoTeams(
  homePlayers: home,
  awayPlayers: away,
  homeTotalRanking: home.fold(0, (sum, p) => sum + p.ranking),
  awayTotalRanking: away.fold(0, (sum, p) => sum + p.ranking),
);

String key(Draft d) =>
    (d.teams
            .map(
              (t) =>
                  (t.players.map((p) => p.playerId).toList()..sort()).join(','),
            )
            .toList()
          ..sort())
        .join('|');

DraftProposal proposal(Draft d, String signature) => DraftProposal(
  draft: d,
  score: 0,
  deviationScore: 0,
  penaltyScore: 0,
  rulePenalty: 0,
  tieBreaker: 0,
  signature: signature,
);

Map<String, Object?> membership(
  String id,
  String match, {
  Object? home = 1,
  Object? away = 0,
  String? played = '2025-01-01T00:00:00Z',
  String created = '2025-01-01T00:00:00Z',
}) => {
  'player_id': id,
  'match_id': match,
  'team_id': 't',
  'matches': {
    'home_score': home,
    'away_score': away,
    'played_at': played,
    'created_at': created,
  },
};

SupabaseClient clientFor(Future<http.Response> Function(http.Request) respond) {
  final client = SupabaseClient(
    'https://fixture.invalid',
    'fixture-key',
    httpClient: MockClient((request) async {
      final response = await respond(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );
  addTearDown(client.dispose);
  return client;
}

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  final players = [
    for (final id in ['a', 'b', 'c', 'd']) player(id),
  ];
  final counts = {'a': 40, 'b': 39, 'c': 1, 'd': 0};
  final balanced = draft([players[0], players[2]], [players[1], players[3]]);
  final unbalanced = draft([players[0], players[1]], [players[2], players[3]]);

  test(
    'independent descending pairs, exact weights, rank 0 and fixed scales',
    () {
      final a = player('a', 100), b = player('b', 0);
      final c = player('c', 80), d = player('d', 20);
      final omitted = player('omitted');
      final balance = TwoTeamBalance(
        [a, b, c, d, omitted],
        {'a': 0, 'b': 40, 'c': 39, 'd': 1, 'omitted': 80},
      );
      final split = draft([a, b], [c, d]);
      expect(balance.rankingPairs(split), 20 / 99);
      // Experience order is b,a versus c,d, not ranking order a,b versus c,d.
      expect(balance.experiencePairs(split), 1 / 80);
      expect(balance.secondary(split), 0.5 * 20 / 99 + 0.5 / 80);
      final extremes = draft([a], [b]);
      expect(balance.rankingPairs(extremes), 100 / 99);
      expect(balance.rankingPairs(extremes), greaterThan(1));
    },
  );

  test('40/39/1/0, zero/equal experience, unmatched and empty pairs', () {
    final balance = TwoTeamBalance(players, counts);
    expect(balance.rankingPairs(balanced), 0);
    expect(balance.experiencePairs(balanced), 1 / 40);
    expect(balance.experiencePairs(unbalanced), 39 / 40);
    expect(
      balance.secondary(balanced),
      lessThan(balance.secondary(unbalanced)),
    );
    for (final value in [0, 7]) {
      final equal = TwoTeamBalance(players, {
        for (final p in players) p.playerId: value,
      });
      expect(equal.experiencePairs(balanced), 0);
      expect(equal.secondary(balanced), 0);
    }
    final odd = draft([players[0], players[2]], [players[1]]);
    expect(balance.experiencePairs(odd), 1 / 40); // c has no pair, no phantom.
    expect(
      balance.rankingPairs(
        draft([player('x', 100), player('y', 0)], [player('z', 100)]),
      ),
      0,
    );
    expect(balance.secondary(draft([], [players[0]])), 0);
  });

  test('a true stored hundredth difference is not a tie', () {
    final balance = TwoTeamBalance(players, counts);
    final nearly = draft([player('x', 50.01)], [player('y', 50)]);
    final exact = draft([player('a', 50)], [player('d', 50)]);
    expect(
      balance.compare(
        proposal(exact, 'z'),
        proposal(nearly, 'a'),
        playWithSubstitute: true,
      ),
      lessThan(0),
    );
    expect(
      balance.compare(
        proposal(balanced, 'a'),
        proposal(balanced, 'z'),
        playWithSubstitute: true,
      ),
      lessThan(0),
    );
  });

  final decimalExperience = {
    'a': 40,
    'b': 39,
    'c': 23,
    'd': 21,
    'e': 2,
    'f': 0,
  };
  List<Player> decimalPool({required bool control}) => [
    player('a', 45.90),
    player('b', control ? 46.41 : 46.40),
    player('c', control ? 46.71 : 46.70),
    player('d', 45.50),
    player('e', 46.70),
    player('f', 45.00),
  ];

  test('cent-level ties use experience, but a true cent gap wins first', () {
    for (final control in [false, true]) {
      final [a, b, c, d, e, f] = decimalPool(control: control);
      final acd = draft([a, c, d], [b, e, f]);
      final ade = draft([a, d, e], [b, c, f]);
      final balance = TwoTeamBalance([a, b, c, d, e, f], decimalExperience);
      expect(balance.secondary(ade), lessThan(balance.secondary(acd)));
      expect(
        balance.compare(
          proposal(ade, 'ade'),
          proposal(acd, 'acd'),
          playWithSubstitute: false,
        ),
        control ? greaterThan(0) : lessThan(0),
      );
    }
  });

  test('substitute adjustment preserves a third of a hundredth', () {
    final a = player('a', 1.00);
    final b = player('b', 1.00);
    final c = player('c', 1.00);
    final d = player('d', 1.00);
    final e = player('e', 1.00);
    final f = player('f', 1.01);
    final g = player('g', 1.01);
    final h = player('h', 1.01);
    final balance = TwoTeamBalance(
      [a, b, c, d, e, f, g, h],
      {'a': 40, 'b': 40, 'c': 40, 'h': 40},
    );
    // 3.00 * 2/3 == 2.00, while 3.02 * 2/3 - 2.01 is 1/300.
    final exact = draft([a, b, c], [d, e]);
    final fractional = draft([a, f, g], [d, h]);
    expect(balance.secondary(fractional), lessThan(balance.secondary(exact)));
    expect(
      balance.compare(
        proposal(exact, 'z'),
        proposal(fractional, 'a'),
        playWithSubstitute: true,
      ),
      lessThan(0),
    );
  });

  final generators = <String, DraftRepository>{
    'combinatory': const CombinatoryDraftRepository(),
    // A pool of one exposes all partitions in these small deterministic fixtures.
    'greedy': const GreedyDraftRepository(candidatePoolSize: 1),
  };
  for (final entry in generators.entries) {
    final name = entry.key, generator = entry.value;
    test('$name: decimal rankings preserve real ties and gaps', () async {
      for (final control in [false, true]) {
        final proposals = await generator.createDraft(
          players: decimalPool(control: control),
          appearances: decimalExperience,
          seed: 42,
        );
        final keys = proposals.map(key);
        expect(keys, containsAll(['a,c,d|b,e,f', 'a,d,e|b,c,f']));
        expect(keys.first, control ? 'a,c,d|b,e,f' : 'a,d,e|b,c,f');
      }
    });

    test('$name: 90:90 precedes 100:80 despite worse secondary', () async {
      final pool = [
        player('a', 80),
        player('b', 10),
        player('c', 20),
        player('d', 70),
      ];
      final experience = {'a': 40, 'b': 39, 'c': 0, 'd': 1};
      final proposals = await generator.createDraft(
        players: pool,
        appearances: experience,
        seed: 42,
      );
      final best = draft([pool[0], pool[1]], [pool[2], pool[3]]);
      final worse = draft([pool[0], pool[2]], [pool[1], pool[3]]);
      final balance = TwoTeamBalance(pool, experience);
      expect(balance.secondary(best), greaterThan(balance.secondary(worse)));
      expect(proposals.map(key), containsAll([key(best), key(worse)]));
      expect(
        proposals.indexWhere((p) => key(p) == key(best)),
        lessThan(proposals.indexWhere((p) => key(p) == key(worse))),
      );
      expect(
        proposals.first.teams.map((t) => t.totalRanking),
        everyElement(90),
      );
    });

    test(
      '$name: actual paginated history flows through provider to generation',
      () async {
        final rows = <Map<String, Object?>>[
          for (var i = 0; i < 40; i++) membership('a', 'a$i'),
          for (var i = 0; i < 39; i++) membership('b', 'b$i'),
          membership('c', 'zero-zero', home: 0, away: 0, played: null),
          membership('d', 'accepted', home: null, away: null),
          membership('d', 'partial', away: null),
          membership('d', 'current'),
          membership('d', 'later-than-current', played: '2025-08-01T00:00:00Z'),
          membership('d', 'future', played: '2027-01-01T00:00:00Z'),
          membership('d', 'same-time', played: '2025-06-01T00:00:00Z'),
          // Duplicate memberships must not inflate counts, including across pages.
          for (var i = 0; i < 200; i++) membership('a', 'a0'),
        ];
        final requests = <Uri>[];
        final client = clientFor((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/matches')) {
            expect(request.url.queryParameters['match_id'], 'eq.current');
            return jsonResponse({
              'played_at': '2025-06-01T00:00:00Z',
              'created_at': '2025-01-01T00:00:00Z',
            });
          }
          final query = request.url.queryParameters;
          final offset = int.parse(query['offset']!);
          final limit = int.parse(query['limit']!);
          return jsonResponse(
            rows.sublist(offset, min(offset + limit, rows.length)),
          );
        });
        final historyGenerator = name == 'greedy'
            ? const GreedyDraftRepository()
            : generator;
        final container = ProviderContainer(
          overrides: [
            supabaseProvider.overrideWithValue(client),
            combinatoryDraftRepositoryProvider.overrideWithValue(
              historyGenerator,
            ),
            greedyDraftRepositoryProvider.overrideWithValue(historyGenerator),
          ],
        );
        addTearDown(container.dispose);
        // Exercise the real repository from the provider, not a supplied counter.
        final history = container.read(draftExperienceRepositoryProvider);
        expect(
          await history.getAppearances(
            playerIds: ['a', 'b', 'c', 'd'],
            currentMatchId: 'current',
          ),
          counts,
        );
        final query = requests.last.queryParameters;
        expect(
          query['select'],
          contains('matches!team_players_match_fk!inner'),
        );
        expect(query['player_id'], contains('a'));
        expect(query['matches.home_score'], 'not.is.null');
        expect(query['matches.away_score'], 'not.is.null');
        expect(
          query['order'],
          'match_id.asc.nullslast,team_id.asc.nullslast,player_id.asc.nullslast',
        );
        final useCase = container.read(
          name == 'greedy'
              ? greedyCreateDraftUseCaseProvider
              : combinatoryCreateDraftUseCaseProvider,
        );
        final proposals = await useCase.execute(
          players: players,
          currentMatchId: 'current',
          seed: 42,
        );
        expect(
          requests.where((u) => u.path.endsWith('/team_players')).length,
          4,
        );
        final balance = TwoTeamBalance(players, counts);
        expect(
          proposals.map(key),
          containsAll([key(balanced), key(unbalanced)]),
        );
        expect(balance.experiencePairs(proposals.first), 1 / 40);
        expect(
          proposals.indexWhere((p) => key(p) == key(balanced)),
          lessThan(proposals.indexWhere((p) => key(p) == key(unbalanced))),
        );
        expect(
          proposals.every((p) => p.teams.every((t) => t.totalRanking == 100)),
          isTrue,
        );
      },
    );

    for (final substitutes in [false, true]) {
      test(
        '$name: odd players, substitutes=$substitutes, sorted real effective gaps',
        () async {
          final pool = [
            player('a', 100),
            player('b', 90),
            player('c', 80),
            player('d', 70),
            player('e', 60),
          ];
          final drafts = await generator.createDraft(
            players: pool,
            appearances: counts,
            playWithSubstitute: substitutes,
            seed: 7,
          );
          expect(drafts, isNotEmpty);
          // The five players total 400 ranking points. If the two-player
          // side sums to s, the other side sums to 400 - s. With substitutes,
          // measure the gap in thirds: 3 * |(400 - s) * 2/3 - s|.
          // This fixture oracle keeps ties exact without calling app scoring.
          final gaps = <int>[];
          for (final d in drafts) {
            expect(d.teams.map((t) => t.players.length).toList()..sort(), [
              2,
              3,
            ]);
            expect(
              d.teams.expand((t) => t.players).map((p) => p.playerId).toSet(),
              pool.map((p) => p.playerId).toSet(),
            );
            final smaller = d.teams.singleWhere((t) => t.players.length == 2);
            final s = smaller.players.fold(
              0,
              (sum, p) => sum + p.ranking.toInt(),
            );
            gaps.add(substitutes ? (800 - 5 * s).abs() : (400 - 2 * s).abs());
          }
          expect(gaps, orderedEquals([...gaps]..sort()));
        },
      );
    }

    test(
      '$name: equal fallback stable; experience ignored for three/four teams',
      () async {
        final first = await generator.createDraft(players: players, seed: 42);
        final second = await generator.createDraft(
          players: players.reversed.toList(),
          seed: 42,
          appearances: {for (final p in players) p.playerId: 7},
        );
        expect(second.map(key), orderedEquals(first.map(key)));
        expect(
          first.first.teams
              .map((t) => t.players.map((p) => p.playerId).join(','))
              .join('|'),
          'a,b|c,d',
        );
        for (final teams in [3, 4]) {
          final pool = [
            for (var i = 0; i < 8; i++) player('p$i', 40 + i.toDouble()),
          ];
          final before = await generator.createDraft(
            players: pool,
            teamCount: teams,
            seed: 42,
          );
          final after = await generator.createDraft(
            players: pool,
            teamCount: teams,
            seed: 42,
            appearances: {'p0': 1000},
          );
          expect(after.map(key), orderedEquals(before.map(key)));
        }
      },
    );
  }

  for (final useCaseProvider in [
    createDraftUseCaseProvider,
    combinatoryCreateDraftUseCaseProvider,
    greedyCreateDraftUseCaseProvider,
  ]) {
    test(
      '$useCaseProvider: history failures reach application, not zero counts',
      () async {
        final client = clientFor(
          (request) async => jsonResponse({
            'message': 'history unavailable',
            'code': '42501',
          }, 403),
        );
        final container = ProviderContainer(
          overrides: [supabaseProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);
        await expectLater(
          container.read(useCaseProvider).execute(players: players),
          throwsA(isA<Failure>()),
        );
        await expectLater(
          container
              .read(draftExperienceRepositoryProvider)
              .getAppearances(playerIds: ['a'], currentMatchId: 'current'),
          throwsA(isA<Failure>()),
        );
        // Existing multi-team path does not acquire history.
        expect(
          await container
              .read(useCaseProvider)
              .execute(players: players, teamCount: 3, seed: 42),
          isNotEmpty,
        );
      },
    );
  }

  test(
    'new draft chronology excludes future and includes created_at fallback',
    () async {
      final client = clientFor(
        (r) async => jsonResponse([
          membership('a', 'past', played: null),
          membership(
            'a',
            'future',
            played: null,
            created: '2027-01-01T00:00:00Z',
          ),
        ]),
      );
      final history = SupabaseDraftExperienceRepository(
        client,
        now: () => DateTime.utc(2026),
      );
      expect(await history.getAppearances(playerIds: ['a', 'd']), {
        'a': 1,
        'd': 0,
      });
      expect(await history.getAppearances(playerIds: []), isEmpty);
    },
  );
}
