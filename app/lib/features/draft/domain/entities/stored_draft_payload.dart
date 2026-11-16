class StoredDraftProposal {
  final List<List<String>> teams;
  final Map<String, double> rankings;
  final bool playWithSubstitute;

  const StoredDraftProposal({
    required this.teams,
    this.rankings = const {},
    this.playWithSubstitute = true,
  });
}

class StoredDraftPayload {
  final String draftId;
  final String matchId;
  final int teamCount;
  final int proposalsCount;
  final int? seed;
  final String status;
  final String? errorMessage;
  final List<StoredDraftProposal> proposals;
  final Map<String, Map<String, double>> winRateMatrix;

  const StoredDraftPayload({
    required this.draftId,
    required this.matchId,
    required this.teamCount,
    required this.proposalsCount,
    required this.seed,
    required this.status,
    required this.errorMessage,
    required this.proposals,
    required this.winRateMatrix,
  });
}
