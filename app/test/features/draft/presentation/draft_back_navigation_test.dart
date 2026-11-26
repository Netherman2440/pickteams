import 'package:app/core/app_router.dart';
import 'package:app/features/auth/domain/entities/auth_entity.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/draft/presentation/pages/draft_selection_page.dart';
import 'package:app/features/matches/application/usecases/get_squad_matches_usecase.dart';
import 'package:app/features/players/application/usecases/get_squad_players_usecase.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/squads/domain/entities/squad.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/pages/squad_shell_page.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final entry in ['draft', 'create']) {
      for (final systemBack in [true, false]) {
        testWidgets(
          '$platform direct $entry: systemBack=$systemBack returns to squad',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            final router = await _mount(
              tester,
              '/squads/test-squad/matches/$entry',
            );
            expect(find.byType(DraftSelectionPage), findsOneWidget);
            _hideKeyboard(tester);
            await tester.pumpAndSettle();
            if (systemBack) {
              expect(await tester.binding.handlePopRoute(), isTrue);
            } else {
              await tester.tap(find.byType(BackButton));
            }
            await tester.pumpAndSettle();
            _expectSquad(router, tester);
            // Do not trap the user at squad home or add duplicate home pages.
            expect(await tester.binding.handlePopRoute(), isFalse);
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }
    }
  }

  testWidgets('squad quick action pushes draft and system Back returns home', (
    tester,
  ) async {
    final router = await _mount(tester, '/squads/test-squad');
    await tester.tap(find.text('Szybkie akcje'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj mecz'));
    await tester.pumpAndSettle();
    expect(find.byType(DraftSelectionPage), findsOneWidget);
    _hideKeyboard(tester);
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    _expectSquad(router, tester);
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('draft pushed from matches retains that legitimate history', (
    tester,
  ) async {
    final router = await _mount(tester, '/squads/test-squad/matches');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(DraftSelectionPage), findsOneWidget);
    _hideKeyboard(tester);
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/squads/test-squad/matches',
    );
    expect(find.text('Nie znaleziono meczów.'), findsOneWidget);
  });

  testWidgets('system Back traverses relation steps before leaving selection', (
    tester,
  ) async {
    final router = await _mount(
      tester,
      '/squads/test-squad/matches/draft',
      selected: true,
    );
    await tester.tap(find.byTooltip('Przejdź do relacji'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/squads/test-squad/matches/relations',
    );
    router.pushNamed(
      AppRoute.draftAgainstRelations.name,
      pathParameters: {'squadId': 'test-squad'},
      extra: {
        'selectedIds': ['p1', 'p2'],
      },
    );
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/squads/test-squad/matches/relations',
    );
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(DraftSelectionPage), findsOneWidget);
    expect(find.text('Wybrani gracze (2)'), findsOneWidget);
    _hideKeyboard(tester);
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    _expectSquad(router, tester);
  });

  testWidgets(
    'IME visibility change alone does not navigate or restore on system Back',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final router = await _mount(tester, '/squads/test-squad/matches/draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      // Android consumes the first Back in the IME before Flutter receives a
      // route pop. Model only that boundary; this is not an Android device test.
      _hideKeyboard(tester);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/squads/test-squad/matches/draft',
      );
      expect(tester.testTextInput.isVisible, isFalse);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      _expectSquad(router, tester);
      expect(tester.testTextInput.isVisible, isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('an unrelated root route still declines system Back', (
    tester,
  ) async {
    final router = await _mount(tester, '/squads/test-squad/matches');
    expect(await tester.binding.handlePopRoute(), isFalse);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/squads/test-squad/matches',
    );
  });
}

void _hideKeyboard(WidgetTester tester) {
  tester.testTextInput.hide();
  tester.view.viewInsets = FakeViewPadding.zero;
  addTearDown(tester.view.resetViewInsets);
}

void _expectSquad(GoRouter router, WidgetTester tester) {
  expect(router.routeInformationProvider.value.uri.path, '/squads/test-squad');
  expect(
    tester.widget<SquadShellPage>(find.byType(SquadShellPage)).squadId,
    'test-squad',
  );
  expect(
    find.descendant(
      of: find.byType(SquadShellPage),
      matching: find.text('Test squad'),
    ),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
}

Future<GoRouter> _mount(
  WidgetTester tester,
  String location, {
  bool selected = false,
}) async {
  final players = _Players();
  final matches = _Matches();
  when(() => players.execute(squadId: any(named: 'squadId'))).thenAnswer(
    (_) async => [
      for (final id in ['p1', 'p2'])
        Player(
          playerId: id,
          squadId: 'test-squad',
          name: id,
          ranking: 50,
          baseRanking: 50,
          createdAt: DateTime(2026),
        ),
    ],
  );
  when(
    () => matches.execute(squadId: any(named: 'squadId')),
  ).thenAnswer((_) async => []);
  final router = GoRouter(
    routes: appRouter.configuration.routes,
    initialLocation: location,
    initialExtra: selected
        ? {
            'selectedIds': ['p1', 'p2'],
          }
        : null,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(_Auth.new),
        getSquadPlayersUseCaseProvider.overrideWithValue(players),
        getSquadMatchesUseCaseProvider.overrideWithValue(matches),
        squadDetailProvider.overrideWith(
          (ref, id) async => Squad(
            squadId: id,
            ownerId: 'test',
            name: 'Test squad',
            visibility: SquadVisibility.private,
            sportType: SportType.football,
            createdAt: DateTime(2026),
            role: SquadRole.owner,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return router;
}

class _Players extends Mock implements GetSquadPlayersUseCase {}

class _Matches extends Mock implements GetSquadMatchesUseCase {}

class _Auth extends AuthNotifier {
  @override
  AsyncValue<AuthEntity?> build() => const AsyncData(null);
}
