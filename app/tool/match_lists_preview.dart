// Explicit offline entry point. Uses only fake providers and bundled fonts.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/match_lists_app.dart';
import 'match_lists_metrics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  installMatchListMetrics();
  final query = Uri.base.queryParameters;
  runApp(
    MatchListsFixture(
      player: query['page'] == 'player',
      textScale: double.tryParse(query['scale'] ?? '') ?? 1,
      androidInsets: query['insets'] == 'android',
    ),
  );
}
