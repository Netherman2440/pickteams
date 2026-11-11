import 'package:uuid/uuid.dart';
import 'package:app/features/draft/domain/repositories/draft_acceptance_repository.dart';
import 'package:app/features/draft/domain/entities/draft.dart';

/// One acceptance attempt, retained across retries, including a lost RPC reply.
/// Freeze the proposal on first submission so retries cannot change its meaning.
class AcceptMatchDraftUseCase {
  AcceptMatchDraftUseCase(this._repository);
  final DraftAcceptanceRepository _repository;
  final String _requestId = const Uuid().v4();
  Map<String, dynamic>? _payload;
  String? _squadId;
  String? _matchId;
  Future<String>? _pending;
  String? _acceptedId;
  bool get started => _payload != null;

  Future<String> execute({
    required String squadId,
    String? matchId,
    required List<String> homePlayerIds,
    required List<String> awayPlayerIds,
    required List<Draft> proposals,
    required int selectedIndex,
    required Map<String, Map<String, double>> winRateMatrix,
    int? seed,
  }) {
    if (_acceptedId != null) return Future.value(_acceptedId);
    if (_pending != null) return _pending!;
    _squadId ??= squadId;
    _matchId ??= matchId;
    _payload ??= {
      'home': List<String>.of(homePlayerIds),
      'away': List<String>.of(awayPlayerIds),
      'selected_index': selectedIndex,
      'proposals': [
        if (seed != null)
          {
            '_meta': {'seed': seed},
          },
        for (final proposal in proposals)
          {
            'teams': [
              for (final team in proposal.teams)
                team.players.map((p) => p.playerId).toList(),
            ],
          },
      ],
      'win_rate_matrix': winRateMatrix.map(
        (id, rates) => MapEntry(id, Map<String, double>.of(rates)),
      ),
    };
    final pending = _send();
    _pending = pending;
    return pending;
  }

  Future<String> _send() async {
    try {
      return _acceptedId = await Future<String>.sync(
        () => _repository.accept(
          requestId: _requestId,
          squadId: _squadId!,
          matchId: _matchId,
          payload: _payload!,
        ),
      );
    } finally {
      _pending = null;
    }
  }
}
