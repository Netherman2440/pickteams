/// One database transaction. A repeated request ID returns the same match.
abstract interface class DraftAcceptanceRepository {
  Future<String> accept({
    required String requestId,
    required String squadId,
    String? matchId,
    required Map<String, dynamic> payload,
  });
}
