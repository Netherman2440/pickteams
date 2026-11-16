import 'package:app/features/matches/application/dto/team_dto.dart';
import 'package:app/features/matches/domain/entities/match.dart';
import 'package:app/features/matches/domain/entities/match_enums.dart';

class MatchDetailsDto {
  final String matchId;
  final String squadId;
  final String? tournamentId;
  final MatchScoreType? scoreType;
  final int? homeScore;
  final int? awayScore;
  final double? homeWinProbability;
  final Map<String, dynamic> scoreMeta;
  final bool? playWithSubstitute;
  final DateTime createdAt;
  final TeamDto? homeTeam;
  final TeamDto? awayTeam;

  const MatchDetailsDto({
    required this.matchId,
    required this.squadId,
    this.tournamentId,
    this.scoreType,
    this.homeScore,
    this.awayScore,
    this.homeWinProbability,
    this.scoreMeta = const {},
    this.playWithSubstitute,
    required this.createdAt,
    this.homeTeam,
    this.awayTeam,
  });

  factory MatchDetailsDto.fromDomain({
    required Match match,
    required TeamDto homeTeam,
    required TeamDto awayTeam,
  }) {
    return MatchDetailsDto(
      matchId: match.matchId,
      squadId: match.squadId,
      tournamentId: match.tournamentId,
      scoreType: match.scoreType,
      homeScore: match.homeScore,
      awayScore: match.awayScore,
      homeWinProbability: match.homeWinProbability,
      scoreMeta: match.scoreMeta,
      playWithSubstitute: match.playWithSubstitute,
      createdAt: match.createdAt,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
    );
  }

  double? get awayWinProbability {
    final value = homeWinProbability;
    if (value == null) return null;
    return (1 - value).clamp(0.0, 1.0).toDouble();
  }
}
