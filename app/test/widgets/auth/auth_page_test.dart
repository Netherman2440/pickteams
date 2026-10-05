import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/auth/presentation/pages/auth_page.dart';
import 'package:app/core/app_theme.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';

void main() {
  test('simple test to verify flutter test works', () {
    expect(1 + 1, 2);
  });

  group('AuthPage Widget Tests', () {
    testWidgets(
      'shows "Podaj e-mail" when email is empty and login is pressed',
      (WidgetTester tester) async {
        // Build the AuthPage widget with theme
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(() => MockAuthNotifier()),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: const AuthPage(),
            ),
          ),
        );

        // Wait for the widget to fully build
        await tester.pumpAndSettle();

        // Find the login button
        final loginButton = find.text('Zaloguj się');
        expect(loginButton, findsOneWidget);

        // Tap the login button without entering any email
        await tester.ensureVisible(loginButton);
        await tester.pumpAndSettle();
        await tester.tap(loginButton);
        await tester.pump();

        // Check if the validation message appears
        expect(find.text('Podaj e-mail'), findsOneWidget);
      },
    );

    testWidgets(
      'shows "Podaj hasło" when password is empty and login is pressed',
      (WidgetTester tester) async {
        // Build the AuthPage widget with theme
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(() => MockAuthNotifier()),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: const AuthPage(),
            ),
          ),
        );

        // Wait for the widget to fully build
        await tester.pumpAndSettle();

        // Enter a valid email to pass email validation
        final emailField = find.byType(TextFormField).first;
        await tester.enterText(emailField, 'test@example.com');
        await tester.pump();

        // Find the login button
        final loginButton = find.text('Zaloguj się');
        expect(loginButton, findsOneWidget);

        // Tap the login button without entering password
        await tester.ensureVisible(loginButton);
        await tester.pumpAndSettle();
        await tester.tap(loginButton);
        await tester.pump();

        // Check if the validation message appears
        expect(find.text('Podaj hasło'), findsOneWidget);
      },
    );

    testWidgets('Create Account button exists and is tappable', (
      WidgetTester tester,
    ) async {
      // Build the AuthPage widget with theme
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authStateProvider.overrideWith(() => MockAuthNotifier())],
          child: MaterialApp(theme: AppTheme.darkTheme, home: const AuthPage()),
        ),
      );

      // Wait for the widget to fully build
      await tester.pumpAndSettle();

      // Find the Create Account button
      final createAccountButton = find.text('Utwórz konto');
      expect(createAccountButton, findsOneWidget);

      // Verify the button is enabled (not disabled due to loading)
      final buttonWidget = tester.widget<TextButton>(
        find.ancestor(
          of: createAccountButton,
          matching: find.byType(TextButton),
        ),
      );
      expect(buttonWidget.onPressed, isNotNull);
    });
  });
}

// Mock AuthNotifier for testing
class MockAuthNotifier extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() {
    return AsyncValue.data(null);
  }
}

// Mock Navigator Observer for testing navigation
class MockNavigatorObserver extends NavigatorObserver {
  String? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route.settings.name;
  }
}
