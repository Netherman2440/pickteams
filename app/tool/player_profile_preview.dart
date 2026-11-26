// Lab entry point. No environment, credentials, login, or backend access.
import 'package:flutter/material.dart';
import '../test/fixtures/player_profile_app.dart';

void main() => runApp(
  PlayerProfileFixture(
    initialSection: const String.fromEnvironment('SECTION'),
    count: const int.fromEnvironment('MATCHES', defaultValue: 14),
    longName: const bool.fromEnvironment('LONG_NAME'),
  ),
);
