// Credential-free entry point. Both routes use the same marked synthetic data.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../test/fixtures/role_goal_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(
    RoleGoalFixtureApp(squad: Uri.base.queryParameters['page'] == 'squad'),
  );
}
