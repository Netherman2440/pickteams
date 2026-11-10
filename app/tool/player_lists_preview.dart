// Run only as the explicit web entry point; never connects to production.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/player_lists_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(PlayerListsFixture(page: Uri.base.queryParameters['page'] ?? 'match'));
}
