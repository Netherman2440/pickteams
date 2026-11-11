import 'package:app/core/app_theme.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/pages/auth_page.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class IdleAuth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => const AsyncData(null);
}

void main() {
  for (final hasEmail in [false, true]) {
    testWidgets('login validates ${hasEmail ? 'password' : 'email'}', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authStateProvider.overrideWith(IdleAuth.new)],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const AuthPage()),
        ),
      );
      await tester.pumpAndSettle();
      if (hasEmail) {
        await tester.enterText(
          find.byType(TextFormField).first,
          'test@example.com',
        );
      }
      final button = find.text('Zaloguj się');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(
        find.text(hasEmail ? 'Podaj hasło' : 'Podaj e-mail'),
        findsOneWidget,
      );
    });
  }
}
