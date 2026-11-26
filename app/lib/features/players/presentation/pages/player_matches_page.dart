import 'package:flutter/material.dart';
import '../widgets/player_context_header.dart';
import '../widgets/player_navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/matches/presentation/widgets/match_tile.dart';
import 'package:app/features/players/presentation/state/player_matches_provider.dart';
import 'package:app/features/players/presentation/state/player_name_provider.dart';

class PlayerMatchesPage extends ConsumerWidget {
  const PlayerMatchesPage({
    super.key,
    required this.squadId,
    required this.playerId,
  });

  final String squadId;
  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(playerMatchesProvider(playerId));
    final playerNameAsync = ref.watch(playerNameProvider(playerId));
    final title = playerNameAsync.maybeWhen(
      data: (name) => '$name > Mecze',
      orElse: () => 'Mecze',
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PlayerContent(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PlayerContextHeader(
                squadId: squadId,
                playerId: playerId,
                selected: PlayerSection.matches,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(playerMatchesProvider(playerId).future),
                child: matchesAsync.when(
                  data: (matches) {
                    if (matches.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Nie znaleziono meczów.')),
                        ],
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(8),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final match = matches[index];
                        return MatchTile(match: match, squadId: squadId);
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(
                    child: SelectableText.rich(
                      TextSpan(
                        text: 'Błąd: $error',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
