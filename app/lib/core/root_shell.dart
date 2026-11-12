import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/app_config.dart';
import 'package:app/features/auth/presentation/providers/auth_notifier.dart';
import 'package:app/features/squads/presentation/state/squad_detail_notifier.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  bool _isSidebarPinned = false;
  bool _isSidebarHovered = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final authEntity = authState.value;
    final isGuest = authEntity == null || authEntity.isAnonymous;
    final email = authEntity?.email ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppConfig.mobileWidth;
        final location = widget.location;
        final squadId = _extractSquadId(location);

        String? squadName;
        if (squadId != null) {
          final squadState = ref.watch(squadDetailProvider(squadId));
          squadState.when(
            data: (squad) {
              squadName = squad.name;
            },
            loading: () {},
            error: (_, _) {},
          );
        }

        final isSidebarExpanded = isMobile
            ? _isSidebarPinned
            : _isSidebarPinned || _isSidebarHovered;

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: _buildAppBar(
              context: context,
              ref: ref,
              isGuest: isGuest,
              email: email,
              isMobile: isMobile,
            ),
          ),
          body: isMobile
              ? _buildMobileBody(
                  context: context,
                  isSidebarExpanded: isSidebarExpanded,
                  isGuest: isGuest,
                  location: location,
                  squadName: squadName,
                )
              : _buildDesktopBody(
                  context: context,
                  isSidebarExpanded: isSidebarExpanded,
                  isGuest: isGuest,
                  location: location,
                  squadName: squadName,
                ),
        );
      },
    );
  }

  void _collapseSidebar() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isSidebarPinned = false;
      _isSidebarHovered = false;
    });
  }

  Widget _buildMobileBody({
    required BuildContext context,
    required bool isSidebarExpanded,
    required bool isGuest,
    required String location,
    required String? squadName,
  }) {
    const panelWidth = 260.0;

    return Stack(
      children: [
        SafeArea(child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !isSidebarExpanded,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              opacity: isSidebarExpanded ? 1 : 0,
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSidebarPinned = false;
                      });
                    },
                    child: Container(color: Colors.black26),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      offset: isSidebarExpanded
                          ? Offset.zero
                          : const Offset(-1, 0),
                      child: Material(
                        elevation: 8,
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: SizedBox(
                          width: panelWidth,
                          child: _SidebarNavigation(
                            isExpanded: true,
                            isGuest: isGuest,
                            location: location,
                            squadName: squadName,
                            onNavigate: _collapseSidebar,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopBody({
    required BuildContext context,
    required bool isSidebarExpanded,
    required bool isGuest,
    required String location,
    required String? squadName,
  }) {
    final theme = Theme.of(context);
    const railWidth = 56.0;
    const panelWidth = 260.0;

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                const SizedBox(width: railWidth),
                Expanded(child: widget.child),
              ],
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: railWidth,
            child: MouseRegion(
              onHover: (event) {
                if (_isSidebarPinned || _isSidebarHovered) {
                  return;
                }
                // Only expand when the cursor is directly over the icon rail.
                if (event.localPosition.dx <= railWidth) {
                  setState(() {
                    _isSidebarHovered = true;
                  });
                }
              },
              onExit: (_) {
                if (_isSidebarPinned) {
                  return;
                }
                setState(() {
                  _isSidebarHovered = false;
                });
              },
              child: Material(
                color: theme.colorScheme.surfaceContainerHighest,
                child: SizedBox(
                  width: railWidth,
                  child: _SidebarNavigation(
                    isExpanded: false,
                    isGuest: isGuest,
                    location: location,
                    squadName: squadName,
                    onNavigate: _collapseSidebar,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: isSidebarExpanded ? 0 : -panelWidth,
            width: panelWidth,
            child: IgnorePointer(
              ignoring: !isSidebarExpanded,
              child: MouseRegion(
                onEnter: (_) {
                  if (_isSidebarPinned) {
                    return;
                  }
                  setState(() {
                    _isSidebarHovered = true;
                  });
                },
                onExit: (_) {
                  if (_isSidebarPinned) {
                    return;
                  }
                  setState(() {
                    _isSidebarHovered = false;
                  });
                },
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  opacity: isSidebarExpanded ? 1 : 0,
                  child: Material(
                    elevation: 8,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: _SidebarNavigation(
                      isExpanded: true,
                      isGuest: isGuest,
                      location: location,
                      squadName: squadName,
                      onNavigate: _collapseSidebar,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar({
    required BuildContext context,
    required WidgetRef ref,
    required bool isGuest,
    required String email,
    required bool isMobile,
  }) {
    final theme = Theme.of(context);
    final titleColor =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: titleColor,
    );
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Otwórz nawigację',
          onPressed: () {
            setState(() {
              _isSidebarPinned = !_isSidebarPinned;
              if (isMobile) {
                _isSidebarHovered = false;
              } else if (!_isSidebarPinned) {
                _isSidebarHovered = false;
              }
            });
          },
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Tooltip(
            message: 'pickteams.pl',
            child: Text.rich(
              TextSpan(
                style: titleStyle,
                children: [
                  const TextSpan(text: 'pick'),
                  TextSpan(
                    text: 'teams',
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  const TextSpan(text: '.pl'),
                ],
              ),
              semanticsLabel: 'pickteams.pl',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );

    if (isGuest) {
      return AppBar(
        centerTitle: false,
        title: title,
        actions: [
          TextButton.icon(
            onPressed: () {
              context.go('/auth');
            },
            icon: const Icon(Icons.login, color: Colors.white),
            label: const Text('Zaloguj', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }

    return AppBar(
      centerTitle: false,
      title: title,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: PopupMenuButton<_ProfileMenuAction>(
            tooltip: email,
            position: PopupMenuPosition.under,
            onSelected: (action) async {
              switch (action) {
                case _ProfileMenuAction.profile:
                  context.go('/me');
                  break;
                case _ProfileMenuAction.logout:
                  await ref.read(authStateProvider.notifier).logout();
                  if (!context.mounted) {
                    return;
                  }
                  context.go('/auth');
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<_ProfileMenuAction>(
                value: _ProfileMenuAction.profile,
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<_ProfileMenuAction>(
                value: _ProfileMenuAction.logout,
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Wyloguj'),
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _ProfileMenuAction { profile, logout }

class _SidebarNavigation extends StatelessWidget {
  const _SidebarNavigation({
    required this.isExpanded,
    required this.isGuest,
    required this.location,
    required this.squadName,
    required this.onNavigate,
  });

  final bool isExpanded;
  final bool isGuest;
  final String location;
  final String? squadName;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final navItems = <_NavItem>[
      if (!isGuest)
        const _NavItem(icon: Icons.person, label: 'Profil', path: '/me'),
      const _NavItem(icon: Icons.groups, label: 'Składy', path: '/squads'),
    ];

    final squadId = _extractSquadId(location);
    final hasSquadSection = squadId != null;

    return Column(
      crossAxisAlignment: isExpanded
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        if (!isExpanded) const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final item in navItems)
                _SidebarNavItem(
                  item: item,
                  isExpanded: isExpanded,
                  isSelected: item.path == '/squads'
                      ? _isLocationExact(location, item.path)
                      : _isLocationSelected(location, item.path),
                  onNavigate: onNavigate,
                ),
              if (hasSquadSection) ...[
                if (isExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      (squadName != null && squadName!.isNotEmpty)
                          ? squadName!
                          : 'Skład',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Divider(height: 24),
                _SidebarNavItem(
                  item: _NavItem(
                    icon: Icons.home,
                    label: 'Główna',
                    path: '/squads/$squadId',
                  ),
                  isExpanded: isExpanded,
                  // Home should be selected only for the exact squad root route.
                  isSelected: _isLocationExact(location, '/squads/$squadId'),
                  onNavigate: onNavigate,
                ),
                _SidebarNavItem(
                  item: _NavItem(
                    icon: Icons.group,
                    label: 'Gracze',
                    path: '/squads/$squadId/players',
                  ),
                  isExpanded: isExpanded,
                  isSelected: _isLocationSelected(
                    location,
                    '/squads/$squadId/players',
                  ),
                  onNavigate: onNavigate,
                ),
                _SidebarNavItem(
                  item: _NavItem(
                    icon: Icons.sports_soccer,
                    label: 'Mecze',
                    path: '/squads/$squadId/matches',
                  ),
                  isExpanded: isExpanded,
                  isSelected: _isLocationSelected(
                    location,
                    '/squads/$squadId/matches',
                  ),
                  onNavigate: onNavigate,
                ),
                _SidebarNavItem(
                  item: _NavItem(
                    icon: Icons.emoji_events,
                    label: 'Turnieje',
                    path: '/squads/$squadId/tournaments',
                  ),
                  isExpanded: isExpanded,
                  isSelected: _isLocationSelected(
                    location,
                    '/squads/$squadId/tournaments',
                  ),
                  onNavigate: onNavigate,
                ),
                _SidebarNavItem(
                  item: _NavItem(
                    icon: Icons.bar_chart,
                    label: 'Statystyki',
                    path: '/squads/$squadId/stats',
                  ),
                  isExpanded: isExpanded,
                  isSelected: _isLocationSelected(
                    location,
                    '/squads/$squadId/stats',
                  ),
                  onNavigate: onNavigate,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.item,
    required this.isExpanded,
    required this.isSelected,
    required this.onNavigate,
  });

  final _NavItem item;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = item.path;

    void navigate() {
      if (path.isEmpty) {
        return;
      }
      final isRoot = path == '/me' || path == '/squads';
      if (isRoot) {
        context.go(path);
        onNavigate();
        return;
      }
      context.push(path);
      onNavigate();
    }

    if (!isExpanded) {
      return IconButton(
        icon: Icon(
          item.icon,
          color: isSelected ? theme.colorScheme.primary : theme.iconTheme.color,
        ),
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.18),
        tooltip: item.label,
        onPressed: navigate,
      );
    }

    return ListTile(
      leading: Icon(
        item.icon,
        color: isSelected ? theme.colorScheme.primary : theme.iconTheme.color,
      ),
      title: Text(item.label),
      selected: isSelected,
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.18),
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.22),
      onTap: navigate,
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label, required this.path});

  final IconData icon;
  final String label;
  final String path;
}

String _effectivePath(String location) {
  // On Flutter web with HashUrlStrategy, the real path is stored in `uri.fragment`
  // (e.g. `http://.../#/squads/123` -> fragment: `/squads/123`, path: `/`).
  final uri = Uri.parse(location);
  final path = uri.path;
  if (path.isNotEmpty && path != '/') {
    return path;
  }

  final fragment = uri.fragment.trim();
  if (fragment.isEmpty) {
    return path;
  }

  final normalized = fragment.startsWith('/') ? fragment : '/$fragment';
  return Uri.parse(normalized).path;
}

bool _isLocationExact(String location, String path) {
  final currentPath = _effectivePath(location);
  if (path.isEmpty) {
    return false;
  }
  return currentPath == path;
}

bool _isLocationSelected(String location, String path) {
  final currentPath = _effectivePath(location);
  if (path.isEmpty) {
    return false;
  }
  return currentPath == path || currentPath.startsWith('$path/');
}

String? _extractSquadId(String location) {
  final path = _effectivePath(location);
  final segments = Uri.parse(path).pathSegments;
  if (segments.length >= 2 && segments.first == 'squads') {
    return segments[1];
  }
  return null;
}
