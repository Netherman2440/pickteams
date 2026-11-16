import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/error/failure.dart';
import 'package:app/features/matches/application/usecases/create_match_usecase.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/tournaments/domain/entities/tournament_status.dart';
import 'package:app/features/tournaments/domain/repositories/tournament_repository.dart';
import 'package:app/features/tournaments/domain/repositories/tournament_draft_repository.dart';
import 'package:app/features/tournaments/tournaments_providers.dart';

class CreateTournamentMatchUseCase {
  final TournamentRepository _tournamentRepository;
  final CreateMatchUseCase _createMatchUseCase;
  final TournamentDraftRepository _draftRepository;

  const CreateTournamentMatchUseCase(
    this._tournamentRepository,
    this._createMatchUseCase,
    this._draftRepository,
  );

  Future<Match> execute({
    required String tournamentId,
    required String homeTournamentTeamId,
    required String awayTournamentTeamId,
  }) async {
    if (homeTournamentTeamId == awayTournamentTeamId) {
      throw const ValidationFailure('Select two different tournament teams.');
    }

    final tournament = await _tournamentRepository.getTournament(
      tournamentId: tournamentId,
    );

    if (tournament.status != TournamentStatus.active) {
      throw const ValidationFailure(
        'Tournament must be active before adding matches.',
      );
    }

    final teams = await _tournamentRepository.getTournamentTeams(
      tournamentId: tournamentId,
    );

    final teamsById = {for (final team in teams) team.tournamentTeamId: team};
    final homeTeam = teamsById[homeTournamentTeamId];
    final awayTeam = teamsById[awayTournamentTeamId];

    if (homeTeam == null || awayTeam == null) {
      throw const NotFoundFailure('Tournament team not found.');
    }

    if (homeTeam.players.isEmpty || awayTeam.players.isEmpty) {
      throw const ValidationFailure(
        'Tournament teams must have players assigned.',
      );
    }

    final acceptedId = tournament.acceptedTournamentDraftId;
    final draft = acceptedId == null
        ? null
        : await _draftRepository.getTournamentDraft(
            tournamentDraftId: acceptedId,
          );
    if (acceptedId != null &&
        (draft == null || draft.tournamentId != tournamentId)) {
      throw StateError('Missing preserved tournament draft');
    }
    final inputs = draft?.inputs;
    final rankings =
        inputs?.rankings ??
        {
          for (final player in [...homeTeam.players, ...awayTeam.players])
            player.playerId: player.ranking,
        };

    return _createMatchUseCase.execute(
      squadId: tournament.squadId,
      tournamentId: tournamentId,
      homePlayerIds: homeTeam.players.map((player) => player.playerId).toList(),
      awayPlayerIds: awayTeam.players.map((player) => player.playerId).toList(),
      homeTeamName: homeTeam.name,
      awayTeamName: awayTeam.name,
      homeTeamColor: homeTeam.color,
      awayTeamColor: awayTeam.color,
      scoreMeta: {
        'tournament_home_team_id': homeTournamentTeamId,
        'tournament_away_team_id': awayTournamentTeamId,
      },
      preservedRankings: rankings,
      playWithSubstitute: inputs?.playWithSubstitute,
      createRankingEntries: true,
    );
  }
}

final createTournamentMatchUseCaseProvider =
    Provider<CreateTournamentMatchUseCase>((ref) {
      return CreateTournamentMatchUseCase(
        ref.read(tournamentRepositoryProvider),
        ref.read(createMatchUseCaseProvider),
        ref.read(tournamentDraftRepositoryProvider),
      );
    });
