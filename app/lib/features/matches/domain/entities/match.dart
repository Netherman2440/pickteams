import 'package:app/features/matches/domain/entities/match_enums.dart';
import 'package:app/features/matches/domain/entities/team.dart';
import 'package:json_annotation/json_annotation.dart';

part 'match.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Match {
  final String matchId;
  final String squadId;
  final String? tournamentId;
  final MatchScoreType? scoreType;
  final int? homeScore;
  final int? awayScore;
  @JsonKey(name: 'home_win_prob')
  final double? homeWinProbability;
  final Map<String, dynamic> scoreMeta;
  final bool? playWithSubstitute;
  final DateTime createdAt;

  // Teams are nullable because when listing matches we might not load teams initially
  // as per the requirement: "nie pobieramy teams (teams są ładowane dopiero w getMatch)"
  // However, the MD says "homeTeam, awayTeam (Team)" in entities section.
  // We can make them nullable or require them.
  // Given the repository spec says getSquadMatches doesn't fetch teams, they should be nullable.
  final Team? homeTeam;
  final Team? awayTeam;

  const Match({
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

  factory Match.fromJson(Map<String, dynamic> json) => _$MatchFromJson(json);
  Map<String, dynamic> toJson() => _$MatchToJson(this);

  Match copyWith({
    String? matchId,
    String? squadId,
    String? tournamentId,
    MatchScoreType? scoreType,
    int? homeScore,
    int? awayScore,
    double? homeWinProbability,
    Map<String, dynamic>? scoreMeta,
    bool? playWithSubstitute,
    DateTime? createdAt,
    Team? homeTeam,
    Team? awayTeam,
  }) {
    return Match(
      matchId: matchId ?? this.matchId,
      squadId: squadId ?? this.squadId,
      tournamentId: tournamentId ?? this.tournamentId,
      scoreType: scoreType ?? this.scoreType,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      homeWinProbability: homeWinProbability ?? this.homeWinProbability,
      scoreMeta: scoreMeta ?? this.scoreMeta,
      playWithSubstitute: playWithSubstitute ?? this.playWithSubstitute,
      createdAt: createdAt ?? this.createdAt,
      homeTeam: homeTeam ?? this.homeTeam,
      awayTeam: awayTeam ?? this.awayTeam,
    );
  }

  double? get awayWinProbability {
    final value = homeWinProbability;
    if (value == null) return null;
    return (1 - value).clamp(0.0, 1.0).toDouble();
  }

  Probability? get probability {
    final value = homeWinProbability;
    if (value == null) return null;
    return Probability(value.clamp(0.0, 1.0).toDouble());
  }
}

class Probability {
  final double homeWinProbability;

  const Probability(this.homeWinProbability);

  double get awayWinProbability =>
      (1 - homeWinProbability).clamp(0.0, 1.0).toDouble();
}
