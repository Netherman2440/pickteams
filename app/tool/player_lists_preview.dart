// Run only as the explicit web entry point; never connects to production.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/player_lists_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final params = Uri.base.queryParameters;
  runApp(
    PlayerListsFixture(
      page: params['page'] ?? 'match',
      match: params['score'] == 'saved'
          ? fixtureMatch(homeScore: 14, awayScore: 5)
          : null,
      textScale: double.tryParse(params['scale'] ?? ''),
      systemPadding: params['insets'] == 'android'
          ? const EdgeInsets.symmetric(vertical: 24)
          : null,
    ),
  );
}
