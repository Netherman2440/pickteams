import 'package:app/features/players/domain/services/player_goal_comparison.dart';
import 'package:app/features/players/infrastructure/repositories/supabase_goal_comparison_repository.dart';

const red = '#FF0000';
const blue = '#0000ff';
const green = '#00ff00';

GoalComparisonMatch goalMatch({
  String? homeColor = red,
  String? awayColor = blue,
  List<String> homePlayers = const ['player'],
  List<String> awayPlayers = const ['other'],
  int? homeScore = 6,
  int? awayScore = 2,
  bool ordinaryGoals = true,
}) => GoalComparisonMatch(
  home: GoalComparisonTeam(color: homeColor, playerIds: homePlayers),
  away: GoalComparisonTeam(color: awayColor, playerIds: awayPlayers),
  homeScore: homeScore,
  awayScore: awayScore,
  ordinaryGoals: ordinaryGoals,
);

List<GoalComparisonMatch> comparisonFixture(String scenario) {
  final played = [
    goalMatch(),
    goalMatch(),
    goalMatch(homeScore: 4, awayScore: 0),
    goalMatch(homeColor: blue, awayColor: red, homeScore: 2, awayScore: 4),
  ];
  final absences = [
    for (var i = 0; i < 2; i++)
      goalMatch(homePlayers: ['absent'], homeScore: 1, awayScore: 3),
    for (var i = 0; i < 5; i++)
      goalMatch(
        homeColor: blue,
        awayColor: green,
        homePlayers: ['absent'],
        homeScore: 3,
        awayScore: 1,
      ),
  ];
  return switch (scenario) {
    // Persisted shape from CreateTournamentMatchUseCase and the score writer.
    'tournament' => [
      for (final present in [true, false])
        decodeGoalComparisonMatch({
          'home_score': present ? 6 : 2,
          'away_score': present ? 2 : 3,
          'score_type': null,
          'score_meta': {
            'tournament_home_team_id': 'tournament-red',
            'tournament_away_team_id': 'tournament-blue',
          },
          'teams': [
            {
              'side': 'home',
              'color': red,
              'team_players': [
                {'player_id': present ? 'player' : 'absent'},
              ],
            },
            {
              'side': 'away',
              'color': blue,
              'team_players': [
                {'player_id': 'other'},
              ],
            },
          ],
        }),
    ],
    'empty' => [],
    'no-absences' => played,
    'missing-color' => [
      ...played,
      goalMatch(awayColor: green, homePlayers: ['absent']),
    ],
    'zero' => [
      goalMatch(),
      goalMatch(homePlayers: ['absent']),
    ],
    'rounded-zero' => [
      for (var i = 0; i < 250; i++)
        goalMatch(homeScore: i == 0 ? 7 : 6, awayScore: i == 0 ? 1 : 2),
      goalMatch(homePlayers: ['absent']),
    ],
    'negative' => [
      goalMatch(homeScore: 1, awayScore: 4),
      goalMatch(homePlayers: ['absent'], homeScore: 3, awayScore: 1),
    ],
    _ => [...played, ...absences],
  };
}
