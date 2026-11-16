// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Match _$MatchFromJson(Map<String, dynamic> json) => Match(
  matchId: json['match_id'] as String,
  squadId: json['squad_id'] as String,
  tournamentId: json['tournament_id'] as String?,
  scoreType: $enumDecodeNullable(_$MatchScoreTypeEnumMap, json['score_type']),
  homeScore: (json['home_score'] as num?)?.toInt(),
  awayScore: (json['away_score'] as num?)?.toInt(),
  homeWinProbability: (json['home_win_prob'] as num?)?.toDouble(),
  scoreMeta: json['score_meta'] as Map<String, dynamic>? ?? const {},
  playWithSubstitute: json['play_with_substitute'] as bool?,
  createdAt: DateTime.parse(json['created_at'] as String),
  homeTeam: json['home_team'] == null
      ? null
      : Team.fromJson(json['home_team'] as Map<String, dynamic>),
  awayTeam: json['away_team'] == null
      ? null
      : Team.fromJson(json['away_team'] as Map<String, dynamic>),
);

Map<String, dynamic> _$MatchToJson(Match instance) => <String, dynamic>{
  'match_id': instance.matchId,
  'squad_id': instance.squadId,
  'tournament_id': instance.tournamentId,
  'score_type': _$MatchScoreTypeEnumMap[instance.scoreType],
  'home_score': instance.homeScore,
  'away_score': instance.awayScore,
  'home_win_prob': instance.homeWinProbability,
  'score_meta': instance.scoreMeta,
  'play_with_substitute': instance.playWithSubstitute,
  'created_at': instance.createdAt.toIso8601String(),
  'home_team': instance.homeTeam,
  'away_team': instance.awayTeam,
};

const _$MatchScoreTypeEnumMap = {
  MatchScoreType.regular: 'regular',
  MatchScoreType.penalties: 'penalties',
  MatchScoreType.walkover: 'walkover',
  MatchScoreType.cancelled: 'cancelled',
};
