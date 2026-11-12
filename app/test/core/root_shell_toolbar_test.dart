import 'package:app/core/app_theme.dart';
import 'package:app/core/root_shell.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class ToolbarAuth extends AuthNotifier {
  ToolbarAuth(this.guest);
  final bool guest;
  int logouts = 0;
  @override
  AsyncValue<AuthEntity?> build() => AsyncData(
    guest
        ? null
        : AuthEntity(
            accessToken: '',
            refreshToken: '',
            userId: 'fixture',
            isAnonymous: false,
            email: 'fixture@example.invalid',
          ),
  );
  @override
  Future<void> logout() async {
    logouts++;
    state = const AsyncData(null);
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['OpenSans', 'Nunito']) {
      await (FontLoader(
        '${family}_regular',
      )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
    }
  });
  for (final guest in [true, false]) {
    for (final size in [(320.0, 1.6), (360.0, 1.0), (1440.0, 1.6)]) {
      testWidgets('toolbar guest=$guest width=${size.$1} scale=${size.$2}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(size.$1, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final auth = ToolbarAuth(guest);
        final router = GoRouter(
          initialLocation: '/squads',
          routes: [
            ShellRoute(
              builder: (_, state, child) =>
                  RootShell(location: state.uri.toString(), child: child),
              routes: [
                GoRoute(
                  path: '/squads',
                  builder: (_, _) =>
                      const Center(child: Text('Squads destination')),
                ),
                GoRoute(
                  path: '/me',
                  builder: (_, _) =>
                      const Center(child: Text('Profile destination')),
                ),
              ],
            ),
            GoRoute(
              path: '/auth',
              builder: (_, _) =>
                  const Scaffold(body: Text('Login destination')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authStateProvider.overrideWith(() => auth)],
            child: MaterialApp.router(
              theme: AppTheme.darkTheme,
              routerConfig: router,
              builder: (_, child) => MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(size.$2)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final brand = find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == 'pickteams.pl',
        );
        expect(brand, findsOneWidget);
        final bounds = tester.getRect(brand);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(size.$1));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: brand, matching: find.byType(RichText)),
        );
        expect(tester.widget<Text>(brand).semanticsLabel, 'pickteams.pl');
        expect(find.byTooltip('pickteams.pl'), findsOneWidget);
        if (size.$1 != 320) expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          find.byTooltip('Otwórz nawigację').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Otwórz nawigację'));
        await tester.pumpAndSettle();
        expect(find.text('Składy').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Otwórz nawigację'));
        await tester.pumpAndSettle();
        if (guest) {
          expect(find.text('Zaloguj').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Zaloguj'));
          await tester.pumpAndSettle();
          expect(find.text('Login destination'), findsOneWidget);
        } else {
          await tester.tap(find.byTooltip('fixture@example.invalid'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('fixture@example.invalid'));
          await tester.pumpAndSettle();
          expect(find.text('Profile destination'), findsOneWidget);
          await tester.tap(find.byTooltip('fixture@example.invalid'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Wyloguj'));
          await tester.pumpAndSettle();
          expect(auth.logouts, 1);
          expect(find.text('Login destination'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
