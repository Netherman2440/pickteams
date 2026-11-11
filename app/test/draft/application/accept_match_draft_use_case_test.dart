import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/draft/application/accept_match_draft_use_case.dart';
import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/draft/domain/repositories/draft_acceptance_repository.dart';

void main() {
  test('double submit shares one RPC and completed submit is cached', () async {
    final repository = _Repository();
    final useCase = AcceptMatchDraftUseCase(repository);
    final first = _accept(useCase);
    final second = _accept(useCase);
    expect(identical(first, second), isTrue);
    expect(repository.calls, 1);
    repository.reply.complete('accepted-match');
    expect(await first, 'accepted-match');
    expect(await second, 'accepted-match');
    expect(await _accept(useCase), 'accepted-match');
    expect(repository.calls, 1);
  });

  test(
    'failure retries the same request and frozen payload, without fallback',
    () async {
      final repository = _Repository();
      final useCase = AcceptMatchDraftUseCase(repository);
      final first = _accept(useCase);
      final failure = expectLater(first, throwsStateError);
      final request = repository.requestId;
      final payload = repository.payload;
      repository.reply.completeError(StateError('lost response'));
      await failure;
      repository.reply = Completer<String>();
      final retry = _accept(useCase, home: ['changed']);
      expect(repository.calls, 2);
      expect(repository.requestId, request);
      expect(repository.payload, payload);
      expect(repository.payload!['home'], ['home']);
      repository.reply.complete('accepted-match');
      expect(await retry, 'accepted-match');
    },
  );
}

Future<String> _accept(
  AcceptMatchDraftUseCase useCase, {
  List<String> home = const ['home'],
}) => useCase.execute(
  squadId: 'squad',
  homePlayerIds: home,
  awayPlayerIds: ['away'],
  proposals: const <Draft>[],
  selectedIndex: 0,
  winRateMatrix: {},
  seed: 123,
);

class _Repository implements DraftAcceptanceRepository {
  int calls = 0;
  String? requestId;
  Map<String, dynamic>? payload;
  Completer<String> reply = Completer<String>();
  @override
  Future<String> accept({
    required String requestId,
    required String squadId,
    String? matchId,
    required Map<String, dynamic> payload,
  }) {
    calls++;
    this.requestId = requestId;
    this.payload = payload;
    return reply.future;
  }
}
