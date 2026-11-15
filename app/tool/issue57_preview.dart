// Local browser evidence only. No credentials, network repositories or writes.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/lineup_app.dart';
import '../test/fixtures/player_lists_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Expose the real Flutter controls to browser automation, without test hooks
  // in production widgets. Keep the handle for this process's lifetime.
  semantics = SemanticsBinding.instance.ensureSemantics();
  GoogleFonts.config.allowRuntimeFetching = false;
  final query = Uri.base.queryParameters;
  final roster = lineupPlayers(
    8,
    longNames: query['long'] == '1',
  ).take(int.tryParse(query['count'] ?? '') ?? 15).toList();
  runApp(
    PlayerListsFixture(
      page: query['page'] ?? 'match',
      textScale: double.tryParse(query['scale'] ?? '') ?? 1,
      brightness: query['theme'] == 'light'
          ? Brightness.light
          : Brightness.dark,
      players: roster,
      writes: FixtureWrites(),
      match: fixtureMatch(
        players: roster,
        homeIds: roster
            .take(query['empty'] == '1' ? roster.length : 7)
            .map((p) => p.playerId)
            .toList(),
        awayIds: query['empty'] == '1'
            ? []
            : roster.skip(7).map((p) => p.playerId).toList(),
        homeColor: '#FFFFFF',
        awayColor: '#000000',
      ),
    ),
  );
}

late final SemanticsHandle semantics;
