// Credential-free browser entry point. Never uses production configuration.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:google_fonts/google_fonts.dart';

import '../test/fixtures/player_lists_app.dart';
import '../test/fixtures/shared_rows_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  // Keep browser accessibility enabled so proof can use real page controls.
  SemanticsBinding.instance.ensureSemantics();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('F014_FLUTTER_ERROR: ${details.exceptionAsString()}');
  };
  final params = Uri.base.queryParameters;
  final page = params['page'] ?? 'selection';
  final scale = double.tryParse(params['scale'] ?? '') ?? 1;
  runApp(
    page == 'selection' || page == 'players'
        ? SharedRowsFixture(page: page, textScale: scale)
        : PlayerListsFixture(page: page, textScale: scale),
  );
}
