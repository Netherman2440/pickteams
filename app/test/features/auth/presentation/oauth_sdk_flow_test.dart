import 'dart:async';
import 'dart:convert';

import 'package:app/features/auth/infrastructure/repositories/token_secure_storage.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/pages/auth_callback_page.dart';
import 'package:app/features/auth/presentation/pages/auth_page.dart';
import 'package:app/features/auth/presentation/pages/register_page.dart';
import 'package:app/features/auth/presentation/widgets/native_auth_entry.dart';
import 'package:app/features/squads/application/join_squad_from_invite_use_case.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockTokens extends Mock implements TokenSecureStorage {}

class MockJoin extends Mock implements JoinSquadFromInviteUseCase {}

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

const callback = 'pl.pickteams://auth/callback';
const links = 'com.llfbandit.app_links/events';
const launcher = MethodChannel('plugins.flutter.io/url_launcher');

Map<String, dynamic> sessionJson() => {
  'access_token': 'mock-access-token',
  'refresh_token': 'mock-refresh-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': 'mock-user',
    'aud': 'authenticated',
    'email': 'test@example.com',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<http.Request> requests;
  late List<MethodCall> launches;
  late List<Object> sdkErrors;
  late StreamSubscription<AuthState> sdkObserver;
  late bool launchSucceeds;
  late bool exchangeSucceeds;
  late MockTokens tokens;
  late MemoryPkceStorage pkceStorage;
  late MockJoin join;
  GoRouter? router;

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
  setUp(() async {
    requests = [];
    launches = [];
    sdkErrors = [];
    launchSucceeds = true;
    exchangeSucceeds = true;
    tokens = MockTokens();
    pkceStorage = MemoryPkceStorage();
    when(() => tokens.setTokensFromEntity(any())).thenAnswer((_) async {});
    when(() => tokens.clearTokens()).thenAnswer((_) async {});
    join = MockJoin();
    when(() => join.execute()).thenAnswer((_) async => null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(links),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(launcher, (call) async {
      launches.add(call);
      return launchSucceeds;
    });
    await Supabase.initialize(
      url: 'https://auth.test.invalid',
      publishableKey: 'test-only-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: pkceStorage,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/v1/token' &&
            request.url.queryParameters['grant_type'] == 'pkce') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['auth_code'], 'test-code');
          expect(body['code_verifier'], isNotEmpty);
          expect(
            body['code_verifier'],
            pkceStorage.values.values.single.split('/').first,
          );
          if (!exchangeSucceeds) {
            return http.Response('{"msg":"Invalid auth code"}', 400);
          }
          return http.Response(jsonEncode(sessionJson()), 200);
        }
        fail('Unexpected HTTP request: ${request.method} ${request.url.path}');
      }),
    );
    sdkObserver = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) {},
      onError: (Object error) => sdkErrors.add(error),
    );
  });

  tearDown(() async {
    router?.dispose();
    router = null;
    await sdkObserver.cancel();
    await Supabase.instance.dispose();
    messenger.setMockMethodCallHandler(launcher, null);
    messenger.setMockMethodCallHandler(const MethodChannel(links), null);
  });

  Future<void> pumpApp(WidgetTester tester, String initial) async {
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('LANDING')),
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
          path: '/auth/confirm',
          builder: (_, _) => const Text('EMAIL CONFIRMATION'),
        ),
        GoRoute(
          path: '/me',
          builder: (_, _) => const Text('AUTHENTICATED APP'),
        ),
        GoRoute(
          path: '/squads/invited',
          builder: (_, _) => const Text('INVITED SQUAD'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenSecureStorageProvider.overrideWithValue(tokens),
          joinSquadFromInviteUseCaseProvider.overrideWithValue(join),
        ],
        child: NativeAuthEntry(
          router: router!,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpSdkUntil(WidgetTester tester, bool Function() done) async {
    // SDK stream controllers are created outside fakeAsync; plugin callbacks
    // and widget work run inside it. Advance both queues, never wait in one
    // zone for a future that needs the other zone to make progress.
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      if (done()) return;
    }
    fail('SDK operation did not finish after 100 async/frame turns');
  }

  Future<void> sendLink(WidgetTester tester, String uri) async {
    var received = false;
    final event = Supabase.instance.client.auth.onAuthStateChange.first
        .then<void>(
          (_) => received = true,
          onError: (Object _) => received = true,
        );
    await messenger.handlePlatformMessage(
      links,
      const StandardMethodCodec().encodeSuccessEnvelope(uri),
      (_) {},
    );
    await pumpSdkUntil(tester, () => received);
    await event;
    await tester.pumpAndSettle();
  }

  Future<void> launchGoogle(WidgetTester tester, bool register) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final button = find.text(
      register ? 'Zarejestruj się przez Google' : 'Kontynuuj z Google',
    );
    await tester.ensureVisible(button);
    final count = launches.length;
    await tester.tap(button);
    await pumpSdkUntil(tester, () => launches.length > count);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
  }

  Future<void> prepareOAuth(
    WidgetTester tester, {
    String redirect = callback,
  }) async {
    var ready = false;
    final result = Supabase.instance.client.auth
        .getOAuthSignInUrl(provider: OAuthProvider.google, redirectTo: redirect)
        .then((_) => ready = true);
    await pumpSdkUntil(tester, () => ready);
    await result;
  }

  for (final register in [false, true]) {
    testWidgets(
      'SDK PKCE return from ${register ? 'registration' : 'login'} reaches app without logout or duplicate exchange',
      (tester) async {
        await pumpApp(tester, register ? '/auth/register' : '/auth');
        await launchGoogle(tester, register);
        expect(launches, hasLength(1));
        final args = launches.single.arguments as Map;
        final url = Uri.parse(args['url'] as String);
        expect(url.queryParameters['redirect_to'], callback);
        expect(url.queryParameters['provider'], 'google');
        expect(url.queryParameters['code_challenge'], isNotEmpty);
        expect(
          url.queryParameters['code_challenge_method']?.toLowerCase(),
          's256',
        );
        expect(args['useWebView'], isFalse);
        expect(args['useSafariVC'], isFalse);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await sendLink(tester, '$callback?code=test-code');
        expect(sdkErrors, isEmpty);
        expect(Supabase.instance.client.auth.currentSession, isNotNull);
        expect(find.text('AUTHENTICATED APP'), findsOneWidget);
        expect(requests, hasLength(1));
        expect(pkceStorage.values, isEmpty);
        // A stale return has no remaining verifier. The real SDK emits an
        // error, but neither it nor the app may discard the newer session.
        final signedIn = Supabase.instance.client.auth.currentSession;
        await sendLink(tester, '$callback?code=stale-code');
        expect(sdkErrors.single, isA<AuthException>());
        expect(Supabase.instance.client.auth.currentSession, signedIn);
        expect(find.text('AUTHENTICATED APP'), findsOneWidget);
        expect(requests, hasLength(1));
      },
    );

    testWidgets(
      'launch failure and provider cancel allow retry (register=$register)',
      (tester) async {
        await pumpApp(tester, register ? '/auth/register' : '/auth');
        launchSucceeds = false;
        await launchGoogle(tester, register);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        launchSucceeds = true;
        await launchGoogle(tester, register);
        await sendLink(
          tester,
          '$callback?error=access_denied&error_description=Cancelled',
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await launchGoogle(tester, register);
        await sendLink(tester, '$callback?code=test-code');
        expect(find.text('AUTHENTICATED APP'), findsOneWidget);
        expect(launches, hasLength(3));
      },
    );
  }

  testWidgets('failed SDK code exchange can retry and join pending invite', (
    tester,
  ) async {
    when(() => join.execute()).thenAnswer((_) async => 'invited');
    await pumpApp(tester, '/auth');
    await launchGoogle(tester, false);
    exchangeSucceeds = false;
    await sendLink(tester, '$callback?code=test-code');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    exchangeSucceeds = true;
    await launchGoogle(tester, false);
    await sendLink(tester, '$callback?code=test-code');
    expect(find.text('INVITED SQUAD'), findsOneWidget);
    expect(requests, hasLength(2));
  });

  testWidgets('callback observes SDK session without reading native Uri.base', (
    tester,
  ) async {
    await pumpApp(tester, '/auth/callback');
    // Generate the verifier exactly as the SDK does before a browser launch.
    await prepareOAuth(tester);
    await sendLink(tester, '$callback?code=test-code');
    expect(find.text('AUTHENTICATED APP'), findsOneWidget);
    expect(requests, hasLength(1));
  });

  testWidgets(
    'SDK accepts the existing web URL shape without a second exchange',
    (tester) async {
      await pumpApp(tester, '/auth/callback');
      await prepareOAuth(
        tester,
        redirect: 'https://web.test.invalid/#/auth/callback',
      );
      // The parser is shared by the SDK's native stream and web initial-URL path.
      // This tests parsing, not a real browser/provider redirect.
      await sendLink(
        tester,
        'https://web.test.invalid/?code=test-code#/auth/callback',
      );
      expect(sdkErrors, isEmpty);
      expect(find.text('AUTHENTICATED APP'), findsOneWidget);
      expect(requests, hasLength(1));
    },
  );

  testWidgets(
    'callback with no event offers retry, times out, and still accepts late success',
    (tester) async {
      await pumpApp(tester, '/auth/callback');
      expect(find.text('Wróć do logowania'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await prepareOAuth(tester);
      await sendLink(tester, '$callback?code=test-code');
      expect(find.text('AUTHENTICATED APP'), findsOneWidget);
      expect(requests, hasLength(1));
    },
  );

  for (final beforeMount in [false, true]) {
    testWidgets(
      'cold native return reaches app (session before mount=$beforeMount)',
      (tester) async {
        await prepareOAuth(tester);
        if (beforeMount) await sendLink(tester, '$callback?code=test-code');
        await pumpApp(tester, '/');
        if (!beforeMount) await sendLink(tester, '$callback?code=test-code');
        await tester.pumpAndSettle();
        expect(find.text('AUTHENTICATED APP'), findsOneWidget);
        expect(requests, hasLength(1));
      },
    );
  }

  testWidgets('callback error returns to a usable login form', (tester) async {
    await pumpApp(tester, '/auth/callback');
    await sendLink(tester, '$callback?error=access_denied');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Wróć do logowania'));
    await tester.pumpAndSettle();
    await launchGoogle(tester, false);
    expect(launches, hasLength(1));
    expect(requests, isEmpty);
  });
}
