import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/draft/domain/repositories/draft_experience_repository.dart';

import 'package:app/core/app_config.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/features/draft/application/create_draft_use_case.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/entities/draft_rule.dart';
import 'package:app/features/draft/domain/repositories/draft_repository.dart';
import 'package:app/features/players/domain/entities/player.dart';

void main() {
  test('rejects player lists larger than configured max per match', () async {
    final repository = _FakeDraftRepository();
    final useCase = CreateDraftUseCase(
      repository,
      experienceRepository: _Experience(),
    );
    final players = List<Player>.generate(
      AppConfig.maxPlayersPerMatch + 1,
      (index) => _player('p$index'),
    );

    await expectLater(
      () => useCase.execute(players: players),
      throwsA(isA<ValidationFailure>()),
    );
    expect(repository.wasCalled, isFalse);
  });

  test('allows player lists up to configured max per match', () async {
    final repository = _FakeDraftRepository(
      result: [
        Draft.twoTeams(
          homePlayers: [],
          awayPlayers: [],
          homeTotalRanking: 0,
          awayTotalRanking: 0,
        ),
      ],
    );
    final useCase = CreateDraftUseCase(
      repository,
      experienceRepository: _Experience(),
    );
    final players = List<Player>.generate(
      AppConfig.maxPlayersPerMatch,
      (index) => _player('p$index'),
    );

    final result = await useCase.execute(players: players);

    expect(repository.wasCalled, isTrue);
    expect(result.length, 1);
  });

  test('forwards optional seed to repository', () async {
    final repository = _FakeDraftRepository();
    final useCase = CreateDraftUseCase(
      repository,
      experienceRepository: _Experience(),
    );
    final players = [_player('p1'), _player('p2')];

    await useCase.execute(players: players, seed: 123456);

    expect(repository.lastSeed, 123456);
  });

  test('allows lists larger than max when max check is disabled', () async {
    final repository = _FakeDraftRepository();
    final useCase = CreateDraftUseCase(
      repository,
      experienceRepository: _Experience(),
      enforceMaxPlayers: false,
    );
    final players = List<Player>.generate(
      AppConfig.maxPlayersPerMatch + 1,
      (index) => _player('p$index'),
    );

    await useCase.execute(players: players);

    expect(repository.wasCalled, isTrue);
  });
}

class _Experience implements DraftExperienceRepository {
  @override
  Future<Map<String, int>> getAppearances({
    required List<String> playerIds,
    String? currentMatchId,
  }) async => {for (final id in playerIds) id: 0};
}

class _FakeDraftRepository implements DraftRepository {
  _FakeDraftRepository({this.result = const []});

  final List<Draft> result;
  bool wasCalled = false;
  int? lastSeed;

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
    wasCalled = true;
    lastSeed = seed;
    return result;
  }
}

Player _player(String id) {
  return Player(
    playerId: id,
    squadId: 'squad-1',
    name: id,
    baseRanking: 100,
    ranking: 100,
    createdAt: DateTime(2025, 1, 1),
  );
}
