import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:app/core/app_config.dart';
import 'package:app/core/app_router.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/features/squads/application/delete_squad_use_case.dart';
import 'package:app/features/squads/application/generate_invite_link_use_case.dart';
import 'package:app/features/squads/domain/entities/squad_member.dart';
import 'package:app/features/squads/domain/entities/user_squad_role.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';
import 'package:app/features/squads/presentation/state/squad_invite_link_provider.dart';
import 'package:app/features/squads/presentation/state/squad_settings_notifier.dart';
import 'package:app/features/squads/presentation/state/squads_notifier.dart';
import 'package:app/features/squads/presentation/widgets/danger_zone_section.dart';
import 'package:app/features/squads/presentation/widgets/member_tile.dart';

class SquadSettingsPage extends ConsumerStatefulWidget {
  const SquadSettingsPage({super.key, required this.squadId});

  final String squadId;

  @override
  ConsumerState<SquadSettingsPage> createState() => _SquadSettingsPageState();
}

class _SquadSettingsPageState extends ConsumerState<SquadSettingsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(squadSettingsProvider.notifier).load(widget.squadId);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersState = ref.watch(squadSettingsProvider);
    final squadState = ref.watch(squadDetailProvider(widget.squadId));

    return Scaffold(
      appBar: AppBar(title: Text('Ustawienia')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: squadState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _SettingsErrorView(error: error),
            data: (squad) {
              if (squad.role != SquadRole.owner) {
                return const _NoAccessView();
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zarządzaj członkami składu, rolami i widocznością.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    _MembersSection(
                      membersState: membersState,
                      currentUserRole: squad.role,
                      onPromote: (member) async {
                        await ref
                            .read(squadSettingsProvider.notifier)
                            .promoteToAdmin(member.userId);
                      },
                      onDemote: (member) async {
                        await ref
                            .read(squadSettingsProvider.notifier)
                            .demoteToMember(member.userId);
                      },
                      onRemove: (member) async {
                        await ref
                            .read(squadSettingsProvider.notifier)
                            .removeFromSquad(member.userId);
                      },
                      onAccept: (member) async {
                        await ref
                            .read(squadSettingsProvider.notifier)
                            .acceptRequest(member.userId);
                      },
                      onDecline: (member) async {
                        await ref
                            .read(squadSettingsProvider.notifier)
                            .declineRequest(member.userId);
                      },
                    ),
                    const SizedBox(height: 24),
                    _InviteSection(squadId: widget.squadId),
                    const SizedBox(height: 24),
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: ListTile(
                        title: const Text('Zmiana progów gwiazdek'),
                        subtitle: const Text(
                          'Ustaw poziom meczu dla tego składu. Połówki obliczamy automatycznie.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.pushNamed(
                          AppRoute.starThresholds.name,
                          pathParameters: {'squadId': widget.squadId},
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    DangerZoneSection(
                      squadId: widget.squadId,
                      squadName: squad.name,
                      visibility: squad.visibility,
                      onChangeName: (name) async {
                        await ref
                            .read(squadSettingsProvider.notifier)
                            .updateName(name);
                        ref.invalidate(squadDetailProvider(widget.squadId));
                      },
                      onChangeVisibility: (visibility) async {
                        await ref
                            .read(squadSettingsProvider.notifier)
                            .updateVisibility(visibility);
                        ref.invalidate(squadDetailProvider(widget.squadId));
                      },
                      onDelete: () => _deleteSquad(squad.name),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSquad(String squadName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć skład?'),
        content: Text(
          'To trwale usunie '
          '${squadName.isNotEmpty ? squadName : 'ten skład'} '
          'oraz wszystkie powiązane dane. Tej operacji nie można cofnąć.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref
          .read(deleteSquadUseCaseProvider)
          .execute(squadId: widget.squadId);
      await ref
          .read(squadsNotifierProvider.notifier)
          .loadSquads(searchQuery: null);
      if (mounted) {
        context.goNamed(AppRoute.squads.name);
      }
    } catch (error) {
      if (!mounted) return;
      final message = error is Failure ? error.message : error.toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
    }
  }
}

class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.membersState,
    required this.currentUserRole,
    required this.onPromote,
    required this.onDemote,
    required this.onRemove,
    required this.onAccept,
    required this.onDecline,
  });

  final AsyncValue<List<SquadMember>> membersState;
  final SquadRole currentUserRole;
  final Future<void> Function(SquadMember member) onPromote;
  final Future<void> Function(SquadMember member) onDemote;
  final Future<void> Function(SquadMember member) onRemove;
  final Future<void> Function(SquadMember member) onAccept;
  final Future<void> Function(SquadMember member) onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Members', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        membersState.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, stackTrace) => _SettingsErrorView(error: error),
          data: (members) {
            if (members.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SelectableText(
                  'Nie znaleziono członków dla tego składu.',
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                return MemberTile(
                  member: member,
                  currentUserRole: currentUserRole,
                  onPromote: () => onPromote(member),
                  onDemote: () => onDemote(member),
                  onRemove: () => onRemove(member),
                  onAccept: () => onAccept(member),
                  onDecline: () => onDecline(member),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _InviteSection extends ConsumerStatefulWidget {
  const _InviteSection({required this.squadId});

  final String squadId;

  @override
  ConsumerState<_InviteSection> createState() => _InviteSectionState();
}

class _InviteSectionState extends ConsumerState<_InviteSection> {
  bool _isGenerating = false;

  Future<void> _generateInviteLink() async {
    setState(() {
      _isGenerating = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(generateInviteLinkUseCaseProvider).execute(widget.squadId);
      if (!mounted) {
        return;
      }
      ref.invalidate(squadInviteLinkProvider(widget.squadId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Wygenerowano link zaproszenia')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Nie udało się wygenerować linku zaproszenia'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link skopiowany do schowka')));
  }

  String _formatValidity(DateTime validUntil) {
    final local = validUntil.toLocal();
    final formatter = DateFormat('yMMMd HH:mm');
    return formatter.format(local);
  }

  String _buildInviteUrl(String code) {
    final path = Uri(
      path: '/invite',
      queryParameters: {'code': code},
    ).toString();
    return '${Uri.base.origin}/#$path';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inviteState = ref.watch(squadInviteLinkProvider(widget.squadId));

    final inviteLink = inviteState.value;
    final inviteUrl = inviteLink != null
        ? _buildInviteUrl(inviteLink.code)
        : null;
    final isBusy = inviteState.isLoading || _isGenerating;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Link zaproszenia', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (inviteState.hasError)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  'Nie udało się wczytać linku zaproszenia: ${inviteState.error}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(squadInviteLinkProvider(widget.squadId)),
                  child: const Text('Ponów'),
                ),
              ],
            )
          else if (inviteState.isLoading && inviteLink == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            )
          else if (inviteUrl == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Brak aktywnego linku zaproszenia. Wygeneruj go, aby zaprosić członków.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: isBusy ? null : _generateInviteLink,
                  child: const Text('Wygeneruj link zaproszenia'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(inviteUrl, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow =
                        constraints.maxWidth < AppConfig.mobileWidth;
                    final validityText =
                        'Ważny do ${_formatValidity(inviteLink!.validUntil)}';
                    final copyButton = FilledButton.tonal(
                      onPressed: isBusy ? null : () => _copyLink(inviteUrl),
                      child: const Text('Kopiuj link'),
                    );
                    final regenerateButton = OutlinedButton(
                      onPressed: isBusy ? null : _generateInviteLink,
                      child: const Text('Wygeneruj ponownie'),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(validityText, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [copyButton, regenerateButton],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        copyButton,
                        const SizedBox(width: 12),
                        regenerateButton,
                        const Spacer(),
                        Text(validityText, style: theme.textTheme.bodySmall),
                      ],
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SettingsErrorView extends StatelessWidget {
  const _SettingsErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Error\n\n',
              style: textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: error.toString(),
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoAccessView extends StatelessWidget {
  const _NoAccessView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'No access\n\n',
                style: textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text:
                    'Tylko właściciel składu może wejść na stronę ustawień składu.',
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
