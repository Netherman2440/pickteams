import 'dart:ui';

import 'package:app/core/widgets/player_list_row.dart';
import 'package:app/core/widgets/player_transfer_drag.dart';
import 'package:app/core/widgets/probability_slider.dart';
import 'package:app/core/widgets/team_transfer_target.dart';
import 'package:app/features/draft/presentation/widgets/draft_draggable_player_tile.dart';
import 'package:app/features/matches/presentation/widgets/match_player_tile.dart';
import 'package:app/features/players/domain/entities/player.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../fixtures/lineup_app.dart';
import '../../../fixtures/player_lists_app.dart';

final players = lineupPlayers(8, longNames: true).take(15).toList();

void viewport(WidgetTester tester, double width, {double height = 850}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> edit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Akcje meczu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edytuj składy'));
  await tester.pumpAndSettle();
}

Finder target(int index) => find.byType(TeamTransferTarget).at(index);
Finder tile(String id, {bool draft = false}) => draft
    ? find.byWidgetPredicate(
        (w) => w is DraftDraggablePlayerTile && w.player.playerId == id,
      )
    : find.byWidgetPredicate(
        (w) => w is MatchPlayerTile && w.player.playerId == id,
      );

List<String> names(WidgetTester tester, int side) => tester
    .widgetList<PlayerListRow>(
      find.descendant(of: target(side), matching: find.byType(PlayerListRow)),
    )
    .map((w) => w.name)
    .toList();

Future<TestGesture> move(
  WidgetTester tester,
  String id,
  int side,
  PointerDeviceKind kind, {
  bool draft = false,
  bool drop = true,
  double? y,
}) async {
  final source = tile(id, draft: draft);
  await tester.ensureVisible(source);
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(
    tester.getCenter(
      find.descendant(of: source, matching: find.byIcon(Icons.drag_indicator)),
    ),
    kind: kind,
  );
  if (kind == PointerDeviceKind.touch) {
    await tester.pump(const Duration(milliseconds: 600));
  }
  final bounds = tester.getRect(target(side));
  await gesture.moveTo(
    Offset(bounds.center.dx, y ?? tester.getCenter(source).dy),
  );
  await tester.pump();
  final highlighted = tester.widget<Container>(
    find.descendant(of: target(side), matching: find.byType(Container)).first,
  );
  final fill = (highlighted.decoration as BoxDecoration).color!;
  expect(fill, isNot(Colors.transparent));
  final theme = Theme.of(tester.element(target(side)));
  expect(
    contrast(
      theme.textTheme.bodyMedium!.color!,
      Color.alphaBlend(fill, theme.scaffoldBackgroundColor),
    ),
    greaterThanOrEqualTo(4.5),
  );
  if (drop) {
    await gesture.up();
    await tester.pumpAndSettle();
  }
  return gesture;
}

void identities(WidgetTester tester, Iterable<Player> roster) {
  final all = [...names(tester, 0), ...names(tester, 1)];
  expect(all.length, roster.length);
  expect(all.toSet(), roster.map((p) => p.name).toSet());
}

Color badge(WidgetTester tester, String side) =>
    (tester
                .widget<Container>(find.byKey(ValueKey('lineup-$side-badge')))
                .decoration
            as BoxDecoration)
        .color!;

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
}

void visibleBadge(WidgetTester tester, String side) {
  final finder = find.byKey(ValueKey('lineup-$side-badge'));
  final box = tester.widget<Container>(finder).decoration as BoxDecoration;
  final edge = (box.border as Border).top.color;
  final theme = Theme.of(tester.element(finder));
  expect(edge.a, 1);
  expect(
    contrast(edge, theme.scaffoldBackgroundColor),
    greaterThanOrEqualTo(3),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('probability labels wrap at 320px and 3x', (tester) async {
    viewport(tester, 320);
    for (final compact in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Scaffold(
              body: ProbabilitySlider(
                homeColor: Colors.white,
                awayColor: Colors.black,
                homeProbability: .5,
                compact: compact,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  for (final width in [360.0, 430.0]) {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      for (final save in [false, true]) {
        testWidgets(
          '7/8 match $kind width=$width save=$save keeps identities and colors',
          (tester) async {
            viewport(tester, width);
            final writes = FixtureWrites();
            final match = fixtureMatch(
              players: players,
              homeIds: players.take(7).map((p) => p.playerId).toList(),
              awayIds: players.skip(7).map((p) => p.playerId).toList(),
            );
            Widget fixture() => PlayerListsFixture(
              match: match,
              players: players,
              writes: writes,
            );
            await tester.pumpWidget(fixture());
            await tester.pumpAndSettle();
            await edit(tester);
            final initialTotals = tester
                .widgetList<Text>(find.textContaining('Ranking:'))
                .map((w) => w.data)
                .toList();
            expect(
              tester.getSize(target(0)).height,
              tester.getSize(target(1)).height,
            );
            await move(tester, 'p0', 1, kind);
            expect(names(tester, 0), hasLength(6));
            expect(names(tester, 1), hasLength(9));
            identities(tester, players);
            expect(
              tester
                  .widgetList<Text>(find.textContaining('Ranking:'))
                  .map((w) => w.data)
                  .toList(),
              isNot(initialTotals),
            );
            await move(tester, 'p7', 0, kind);
            identities(tester, players);
            for (final row in tester.widgetList<PlayerListRow>(
              find.byType(PlayerListRow),
            )) {
              final text = tester.widget<Text>(
                find.descendant(
                  of: find.byWidget(row),
                  matching: find.text(row.name),
                ),
              );
              expect(text.maxLines, isNull);
            }
            await tester.tap(find.byTooltip(save ? 'Zapisz' : 'Anuluj'));
            await tester.pumpAndSettle();
            expect(writes.teamSaves, save ? 1 : 0);
            expect(writes.metaSaves, 0);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(fixture());
            await tester.pumpAndSettle();
            await edit(tester);
            expect(names(tester, 0).contains(players[0].name), !save);
            expect(names(tester, 0).contains(players[7].name), save);
            identities(tester, players);
            expect(
              writes.storedMatch?.homeTeam?.color ?? match.homeTeam!.color,
              '#1E88E5',
            );
            expect(
              writes.storedMatch?.awayTeam?.color ?? match.awayTeam!.color,
              '#E53935',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
      testWidgets(
        'empty target accepts lowest opposite row once with $kind at $width',
        (tester) async {
          viewport(tester, width);
          final roster = fixturePlayers.take(8).toList();
          await tester.pumpWidget(
            PlayerListsFixture(
              match: fixtureMatch(
                homeIds: roster.map((p) => p.playerId).toList(),
                awayIds: [],
              ),
            ),
          );
          await tester.pumpAndSettle();
          await edit(tester);
          expect(
            tester.getSize(target(1)).height,
            tester.getSize(target(0)).height,
          );
          final y = tester.getCenter(tile('p7')).dy;
          await move(tester, 'p7', 1, kind, y: y);
          expect(names(tester, 1), [roster.last.name]);
          identities(tester, roster);
          await move(tester, 'p7', 0, kind);
          expect(names(tester, 1), isEmpty);
          identities(tester, roster);
          final gesture = await move(tester, 'p7', 1, kind, drop: false);
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(names(tester, 1), isEmpty);
          identities(tester, roster);
        },
      );
    }
  }

  for (final draft in [false, true]) {
    testWidgets(
      'quick touch scroll and canceled transfer do not move players: proposal=$draft',
      (tester) async {
        viewport(tester, 390, height: 640);
        final writes = FixtureWrites();
        await tester.pumpWidget(
          PlayerListsFixture(
            page: draft ? 'results' : 'match',
            players: players,
            writes: writes,
            match: fixtureMatch(
              players: players,
              homeIds: players.take(7).map((p) => p.playerId).toList(),
              awayIds: players.skip(7).map((p) => p.playerId).toList(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!draft) await edit(tester);
        final before = [names(tester, 0), names(tester, 1)];
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final oldOffset = scroll.position.pixels;
        await tester.drag(
          find.descendant(
            of: tile('p0', draft: draft),
            matching: find.byIcon(Icons.drag_indicator),
          ),
          const Offset(0, -130),
          kind: PointerDeviceKind.touch,
        );
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, greaterThan(oldOffset));
        expect([names(tester, 0), names(tester, 1)], before);
        final gesture = await move(
          tester,
          'p0',
          1,
          PointerDeviceKind.touch,
          draft: draft,
          drop: false,
        );
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect([names(tester, 0), names(tester, 1)], before);
        expect(writes.teamSaves + writes.metaSaves + writes.acceptances, 0);
      },
    );
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      if (!draft) continue; // Match transfers are covered by the matrix above.
      testWidgets(
        'proposal $kind transfers both ways and reaches an empty team',
        (tester) async {
          viewport(tester, 390);
          final roster = fixturePlayers.take(3).toList();
          await tester.pumpWidget(
            PlayerListsFixture(page: 'results', players: roster),
          );
          await tester.pumpAndSettle();
          await move(tester, 'p0', 1, kind, draft: true);
          expect(names(tester, 0), isEmpty);
          expect(
            tester.getSize(target(0)).height,
            tester.getSize(target(1)).height,
          );
          identities(tester, roster);
          await move(tester, 'p2', 0, kind, draft: true);
          expect(names(tester, 0), [roster.last.name]);
          identities(tester, roster);
        },
      );
    }
  }

  for (final role in [SquadRole.guest, SquadRole.member, SquadRole.owner]) {
    testWidgets('read-only $role has no transfer recognizers', (tester) async {
      viewport(tester, 390);
      await tester.pumpWidget(
        PlayerListsFixture(
          role: role,
          match: fixtureMatch(
            homeScore: role == SquadRole.owner ? 2 : null,
            awayScore: role == SquadRole.owner ? 1 : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerTransferDrag), findsNothing);
      expect(find.byType(TeamTransferTarget), findsNothing);
      if (role != SquadRole.owner) {
        expect(find.byTooltip('Akcje meczu'), findsNothing);
      }
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'palette $brightness saves white/black, reopens and cancels with contrasting checks',
      (tester) async {
        viewport(tester, 390);
        final writes = FixtureWrites();
        Widget fixture() =>
            PlayerListsFixture(brightness: brightness, writes: writes);
        await tester.pumpWidget(fixture());
        await tester.pumpAndSettle();
        await edit(tester);
        for (final (index, hex) in [(0, '#FFFFFF'), (1, '#000000')]) {
          await tester.tap(find.byTooltip('Zmień kolor').at(index));
          await tester.pumpAndSettle();
          final swatch = find.byKey(ValueKey('team-color-$hex'));
          expect(swatch, findsOneWidget);
          final unselected =
              tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: swatch,
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect((unselected.border as Border).top.color.a, 1);
          await tester.tap(swatch);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Zmień kolor').at(index));
          await tester.pumpAndSettle();
          final check = tester.widget<Icon>(
            find.descendant(of: swatch, matching: find.byIcon(Icons.check)),
          );
          expect(check.color, index == 0 ? Colors.black : Colors.white);
          final colorBox = tester.widget<Container>(
            find.descendant(of: swatch, matching: find.byType(Container)).first,
          );
          final decoration = colorBox.decoration as BoxDecoration;
          expect(decoration.border, isNotNull);
          final semantics = tester.widget<Semantics>(
            find
                .ancestor(
                  of: swatch,
                  matching: find.byWidgetPredicate(
                    (w) => w is Semantics && w.properties.label == 'Kolor $hex',
                  ),
                )
                .first,
          );
          expect(semantics.properties.selected, isTrue);
          await tester.tap(find.widgetWithText(TextButton, 'Anuluj'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Zapisz'));
        await tester.pumpAndSettle();
        expect(writes.metaSaves, 1);
        expect(writes.teamSaves, 0);
        expect(writes.storedMatch!.homeTeam!.color, '#FFFFFF');
        expect(writes.storedMatch!.awayTeam!.color, '#000000');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(fixture());
        await tester.pumpAndSettle();
        expect(badge(tester, 'home'), Colors.white);
        expect(badge(tester, 'away'), Colors.black);
        await edit(tester);
        await tester.tap(find.byTooltip('Zmień kolor').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('team-color-#E53935')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Anuluj'));
        await tester.pumpAndSettle();
        expect(badge(tester, 'home'), Colors.white);
        expect(writes.metaSaves, 1);
        expect(tester.takeException(), isNull);
      },
    );

    for (final redraw in [false, true]) {
      testWidgets(
        'proposal to fake acceptance and reopened details $brightness redraw=$redraw',
        (tester) async {
          viewport(tester, 390);
          final writes = FixtureWrites();
          final match = fixtureMatch();
          final home = redraw ? const Color(0xFF1E88E5) : Colors.white;
          final away = redraw ? const Color(0xFFE53935) : Colors.black;
          await tester.pumpWidget(
            PlayerListsFixture(
              page: 'results',
              brightness: brightness,
              writes: writes,
              match: match,
              proposalMatchId: redraw ? 'match' : null,
            ),
          );
          await tester.pumpAndSettle();
          expect(badge(tester, 'home'), home);
          expect(badge(tester, 'away'), away);
          visibleBadge(tester, 'home');
          visibleBadge(tester, 'away');
          final slider = tester.widget<ProbabilitySlider>(
            find.byType(ProbabilitySlider),
          );
          expect(slider.homeColor, home);
          expect(slider.awayColor, away);
          final bar = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(ProbabilitySlider),
                  matching: find.byWidgetPredicate(
                    (w) => w is Container && w.foregroundDecoration != null,
                  ),
                )
                .first,
          );
          final edge =
              ((bar.foregroundDecoration as BoxDecoration).border as Border)
                  .top
                  .color;
          expect(edge.a, 1);
          expect(
            contrast(
              edge,
              Theme.of(
                tester.element(find.byType(ProbabilitySlider)),
              ).colorScheme.surface,
            ),
            greaterThanOrEqualTo(3),
          );
          expect(find.textContaining('Gospodarze 52%'), findsOneWidget);
          expect(find.textContaining('Goście 48%'), findsOneWidget);
          await tester.tap(find.text('Zakceptuj propozycję'));
          await tester.pumpAndSettle();
          expect(writes.acceptances, 1);
          expect(
            writes.homeIds.toSet().intersection(writes.awayIds.toSet()),
            isEmpty,
          );
          expect(badge(tester, 'home'), home);
          expect(badge(tester, 'away'), away);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            PlayerListsFixture(writes: writes, brightness: brightness),
          );
          await tester.pumpAndSettle();
          expect(badge(tester, 'home'), home);
          expect(badge(tester, 'away'), away);
        },
      );
    }
  }
}
