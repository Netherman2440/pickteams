import 'package:app/features/auth/application/request_password_reset_use_case.dart';
import 'package:app/features/auth/application/update_password_use_case.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/domain/entities/auth_provider.dart';
import 'package:app/features/auth/presentation/pages/auth_callback_page.dart';
import 'package:app/features/auth/presentation/pages/auth_page.dart';
import 'package:app/features/auth/presentation/pages/register_page.dart';
import 'package:app/features/auth/presentation/pages/reset_password_page.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/squads/application/join_squad_from_invite_use_case.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockJoin extends Mock implements JoinSquadFromInviteUseCase {}

class MockReset extends Mock implements RequestPasswordResetUseCase {}

class MockUpdate extends Mock implements UpdatePasswordUseCase {}

AuthEntity entity({String token = 'access'}) => AuthEntity(
  accessToken: token,
  refreshToken: 'refresh',
  userId: 'user',
  isAnonymous: false,
  email: 'test@example.com',
);

class FormAuth extends AuthNotifier {
  String? redirect;
  List<String>? credentials;
  int logouts = 0;
  String registrationToken = '';
  @override
  AsyncValue<AuthEntity?> build() => const AsyncData(null);
  void succeed() => state = AsyncData(entity());
  void fail() =>
      state = AsyncError(Exception('failed callback'), StackTrace.current);
  @override
  Future<void> signInWithProvider({
    required AuthProvider provider,
    String? redirectTo,
  }) async {
    expect(provider, AuthProvider.google);
    redirect = redirectTo;
  }

  @override
  Future<void> login({required String email, required String password}) async {
    credentials = [email, password];
    succeed();
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    credentials = [email, password, fullName];
    state = AsyncData(entity(token: registrationToken));
  }

  @override
  Future<void> logout() async {
    logouts++;
    state = const AsyncData(null);
  }
}

void main() {
  late FormAuth auth;
  late MockReset reset;
  late MockUpdate update;
  late MockJoin join;
  late GoRouter router;

  setUp(() {
    auth = FormAuth();
    reset = MockReset();
    update = MockUpdate();
    join = MockJoin();
    when(() => join.execute()).thenAnswer((_) async => null);
  });
  tearDown(() => router.dispose());

  Future<void> pumpApp(WidgetTester tester, String initial) async {
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
        GoRoute(
          path: '/auth/register',
          builder: (_, _) => const RegisterPage(),
        ),
        GoRoute(
          path: '/auth/callback',
          builder: (_, _) => const AuthCallbackPage(),
        ),
        GoRoute(
          path: '/auth/reset',
          builder: (_, _) => const ResetPasswordPage(),
        ),
        GoRoute(
          path: '/auth/confirm',
          builder: (_, state) =>
              Text('CONFIRM ${state.uri.queryParameters['email']}'),
        ),
        GoRoute(path: '/me', builder: (_, _) => const Text('SIGNED IN')),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(() => auth),
          requestPasswordResetUseCaseProvider.overrideWithValue(reset),
          updatePasswordUseCaseProvider.overrideWithValue(update),
          joinSquadFromInviteUseCaseProvider.overrideWithValue(join),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final register in [false, true]) {
    testWidgets('Google form uses platform redirect (register=$register)', (
      tester,
    ) async {
      await pumpApp(tester, register ? '/auth/register' : '/auth');
      await tap(
        tester,
        register ? 'Zarejestruj się przez Google' : 'Kontynuuj z Google',
      );
      expect(
        auth.redirect,
        kIsWeb
            ? '${Uri.base.origin}/#/auth/callback'
            : 'pl.pickteams://auth/callback',
      );
      auth.succeed();
      await tester.pumpAndSettle();
      expect(find.text('SIGNED IN'), findsOneWidget);
      expect(auth.logouts, 0);
    });
  }

  testWidgets('login and registration links navigate to usable forms', (
    tester,
  ) async {
    await pumpApp(tester, '/auth');
    await tap(tester, 'Utwórz konto');
    expect(find.text('Zarejestruj się przez Google'), findsOneWidget);
    await tap(tester, 'Masz już konto?');
    expect(find.text('Kontynuuj z Google'), findsOneWidget);
  });

  testWidgets('password login submits trimmed email and reaches app', (
    tester,
  ) async {
    await pumpApp(tester, '/auth');
    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' test@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tap(tester, 'Zaloguj się');
    expect(auth.credentials, ['test@example.com', 'password123']);
    expect(find.text('SIGNED IN'), findsOneWidget);
  });

  for (final token in ['', 'confirmed-access']) {
    testWidgets(
      'password registration retains confirmation flow (token=$token)',
      (tester) async {
        auth.registrationToken = token;
        await pumpApp(tester, '/auth/register');
        for (final (index, value) in [
          'Test User',
          'test@example.com',
          'password123',
          'password123',
        ].indexed) {
          await tester.enterText(find.byType(TextFormField).at(index), value);
        }
        await tap(tester, 'Zarejestruj się');
        expect(auth.credentials, [
          'test@example.com',
          'password123',
          'Test User',
        ]);
        expect(find.text('CONFIRM test@example.com'), findsOneWidget);
        expect(auth.logouts, token.isEmpty ? 0 : 1);
      },
    );
  }

  testWidgets('callback observes initial session without exchanging a code', (
    tester,
  ) async {
    await pumpApp(tester, '/auth');
    auth.succeed();
    router.go('/auth/callback');
    await tester.pumpAndSettle();
    expect(find.text('SIGNED IN'), findsOneWidget);
    expect(auth.logouts, 0);
  });

  testWidgets(
    'callback error offers retry and late success can still navigate',
    (tester) async {
      await pumpApp(tester, '/auth/callback');
      auth.fail();
      await tester.pumpAndSettle();
      expect(find.text('Nie można się zalogować'), findsOneWidget);
      expect(find.text('Wróć do logowania'), findsOneWidget);
      auth.succeed();
      await tester.pumpAndSettle();
      expect(find.text('SIGNED IN'), findsOneWidget);
    },
  );

  testWidgets(
    'web reset email keeps the reset redirect, then permits retry after failure',
    (tester) async {
      when(
        () => reset.execute(
          'test@example.com',
          redirectTo: '${Uri.base.origin}/#/auth/reset',
        ),
      ).thenThrow(Exception('offline'));
      await pumpApp(tester, '/auth');
      Future<void> request() async {
        await tap(tester, 'Nie pamiętasz hasła?');
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          ),
          'test@example.com',
        );
        await tap(tester, 'Send link');
      }

      await request();
      expect(
        find.text('Nie udało się wysłać linku resetującego.'),
        findsOneWidget,
      );
      when(
        () => reset.execute(
          'test@example.com',
          redirectTo: '${Uri.base.origin}/#/auth/reset',
        ),
      ).thenAnswer((_) async {});
      await request();
      expect(
        find.text('Link do resetu hasła został wysłany. Sprawdź e-mail.'),
        findsOneWidget,
      );
      verify(
        () => reset.execute(
          'test@example.com',
          redirectTo: '${Uri.base.origin}/#/auth/reset',
        ),
      ).called(2);
    },
    skip: !kIsWeb,
  );

  testWidgets(
    'password update validates, retries after failure, then returns to login',
    (tester) async {
      when(() => update.execute('password123')).thenThrow(Exception('offline'));
      await pumpApp(tester, '/auth/reset');
      await tester.enterText(find.byType(TextFormField).at(0), 'password123');
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
      await tap(tester, 'Zaktualizuj hasło');
      expect(find.text('Hasła nie są zgodne'), findsOneWidget);
      verifyNever(() => update.execute(any()));
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tap(tester, 'Zaktualizuj hasło');
      expect(find.text('Nie udało się zresetować hasła.'), findsOneWidget);
      when(() => update.execute('password123')).thenAnswer((_) async {});
      await tap(tester, 'Zaktualizuj hasło');
      expect(find.text('Zaloguj się'), findsOneWidget);
      verify(() => update.execute('password123')).called(2);
    },
  );
}
