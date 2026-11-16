import 'package:app/features/draft/domain/entities/draft.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/tournaments/domain/entities/tournament_draft.dart';

List<Draft> restoreTournamentDrafts({
  required List<TournamentDraftProposal> proposals,
  required Map<String, Player> playersById,
}) {
  return [
    for (final proposal in proposals)
      Draft(
        playWithSubstitute: proposal.playWithSubstitute,
        teams: [
          for (final (index, ids) in proposal.teams.indexed)
            _restoreTeam(index, ids, playersById, proposal.rankings),
        ],
      ),
  ];
}

DraftTeam _restoreTeam(
  int index,
  List<String> ids,
  Map<String, Player> playersById,
  Map<String, double> rankings,
) {
  final players = <Player>[];
  for (final id in ids) {
    final player = playersById[id];
    final ranking = rankings[id];
    if (player == null || ranking == null || !ranking.isFinite) {
      throw StateError('Missing preserved tournament draft input for $id');
    }
    players.add(player.copyWith(ranking: ranking));
  }
  return DraftTeam(
    index: index,
    players: players,
    totalRanking: players.fold(0.0, (sum, player) => sum + player.ranking),
  );
}
