import 'dart:async';

import 'package:app/core/global_dependencies.dart';
import 'package:app/features/auth/application/oauth_sign_in_use_case.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/domain/entities/auth_provider.dart' as domain;
import 'package:app/features/auth/infrastructure/repositories/token_secure_storage.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockClient extends Mock implements SupabaseClient {}

class MockAuth extends Mock implements GoTrueClient {}

class MockTokens extends Mock implements TokenSecureStorage {}

class MockOAuth extends Mock implements OAuthSignInUseCase {}

Session session(String token) => Session(
  accessToken: token,
  refreshToken: 'refresh-$token',
  tokenType: 'bearer',
  user: User(
    id: 'user',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '',
    email: 'test@example.com',
  ),
);

void main() {
  late StreamController<AuthState> events;
  late MockTokens tokens;
  late MockOAuth oauth;
  late ProviderContainer container;
  late AuthNotifier notifier;

  setUpAll(() {
    registerFallbackValue(
      AuthEntity(
        accessToken: '',
        refreshToken: '',
        userId: '',
        isAnonymous: false,
        email: '',
      ),
    );
  });
  setUp(() {
    events = StreamController<AuthState>.broadcast(sync: true);
    tokens = MockTokens();
    oauth = MockOAuth();
    final client = MockClient();
    final auth = MockAuth();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentSession).thenReturn(null);
    when(() => auth.onAuthStateChange).thenAnswer((_) => events.stream);
    when(() => tokens.setTokensFromEntity(any())).thenAnswer((_) async {});
    when(() => tokens.clearTokens()).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        supabaseProvider.overrideWithValue(client),
        tokenSecureStorageProvider.overrideWithValue(tokens),
        oauthSignInUseCaseProvider.overrideWithValue(oauth),
      ],
    );
    notifier = container.read(authStateProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await events.close();
  });

  for (final fails in [false, true]) {
    test(
      'late provider launch (fails=$fails) cannot overwrite signed-in session',
      () async {
        final launch = Completer<void>();
        when(
          () => oauth.execute(domain.AuthProvider.google),
        ).thenAnswer((_) => launch.future);
        final result = notifier.signInWithProvider(
          provider: domain.AuthProvider.google,
        );
        events.add(AuthState(AuthChangeEvent.signedIn, session('new')));
        await Future<void>.delayed(Duration.zero);
        if (fails) {
          launch.completeError(Exception('late launch failure'));
        } else {
          launch.complete();
        }
        await result;
        expect(container.read(authStateProvider).value?.accessToken, 'new');
      },
    );
  }

  test('token storage cannot delay or reorder auth events', () async {
    final write = Completer<void>();
    when(
      () => tokens.setTokensFromEntity(any()),
    ).thenAnswer((_) => write.future);
    events.add(AuthState(AuthChangeEvent.signedIn, session('old')));
    expect(container.read(authStateProvider).value?.accessToken, 'old');
    events.add(AuthState(AuthChangeEvent.signedOut, null));
    expect(container.read(authStateProvider).value, isNull);
    write.complete();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authStateProvider).value, isNull);
    verifyInOrder([
      () => tokens.setTokensFromEntity(any()),
      () => tokens.clearTokens(),
    ]);
  });

  test(
    'SDK error permits retry; a late error cannot discard a session',
    () async {
      events.addError(const AuthException('Provider cancelled'));
      expect(container.read(authStateProvider).hasError, isTrue);
      when(
        () => oauth.execute(domain.AuthProvider.google),
      ).thenAnswer((_) async {});
      await notifier.signInWithProvider(provider: domain.AuthProvider.google);
      expect(container.read(authStateProvider).isLoading, isFalse);
      expect(container.read(authStateProvider).hasError, isFalse);
      events.add(AuthState(AuthChangeEvent.signedIn, session('new')));
      await Future<void>.delayed(Duration.zero);
      events.addError(const AuthException('Late cancelled callback'));
      expect(container.read(authStateProvider).value?.accessToken, 'new');
    },
  );

  test('browser close with no callback leaves a usable retry path', () async {
    when(
      () => oauth.execute(domain.AuthProvider.google),
    ).thenAnswer((_) async {});
    await notifier.signInWithProvider(provider: domain.AuthProvider.google);
    expect(
      container.read(authStateProvider),
      const AsyncData<AuthEntity?>(null),
    );
    await notifier.signInWithProvider(provider: domain.AuthProvider.google);
    verify(() => oauth.execute(domain.AuthProvider.google)).called(2);
  });
}
