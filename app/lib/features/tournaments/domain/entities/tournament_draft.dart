import 'package:app/features/draft/domain/entities/draft_rule.dart';

class TournamentDraftProposal {
  final List<List<String>> teams;

  final Map<String, double> rankings;
  final bool playWithSubstitute;

  const TournamentDraftProposal({
    required this.teams,
    this.rankings = const {},
    this.playWithSubstitute = true,
  });
}

class TournamentDraft {
  final String tournamentDraftId;
  final String tournamentId;
  final String squadId;
  final String status;
  final int teamCount;
  final int proposalsCount;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? seed;
  final List<String> selectedPlayerIds;
  final List<DraftRule> draftRules;
  final List<TournamentDraftProposal> proposals;
  final Map<String, Map<String, double>> winRateMatrix;

  /// Every proposal from one generation uses the same input vector and option.
  TournamentDraftProposal get inputs {
    if (proposals.isEmpty) {
      throw StateError('Missing preserved tournament draft inputs');
    }
    final first = proposals.first;
    for (final proposal in proposals) {
      if (proposal.playWithSubstitute != first.playWithSubstitute ||
          proposal.rankings.length != first.rankings.length ||
          proposal.rankings.entries.any(
            (e) => first.rankings[e.key] != e.value,
          )) {
        throw StateError('Inconsistent tournament draft inputs');
      }
    }
    return first;
  }

  const TournamentDraft({
    required this.tournamentDraftId,
    required this.tournamentId,
    required this.squadId,
    required this.status,
    required this.teamCount,
    required this.proposalsCount,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.seed,
    required this.selectedPlayerIds,
    required this.draftRules,
    required this.proposals,
    required this.winRateMatrix,
  });
}
