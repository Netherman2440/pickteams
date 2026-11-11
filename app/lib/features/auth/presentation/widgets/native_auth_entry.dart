import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_notifier.dart';

/// A cold native callback starts at `/` because Flutter link routing is off.
/// Let the SDK finish first, then reuse login's invite and session navigation.
class NativeAuthEntry extends ConsumerStatefulWidget {
  const NativeAuthEntry({required this.router, required this.child, super.key});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<NativeAuthEntry> createState() => _NativeAuthEntryState();
}

class _NativeAuthEntryState extends ConsumerState<NativeAuthEntry> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    ref.listenManual(authStateProvider, (_, next) {
      final entity = next.asData?.value;
      if (entity == null || entity.isAnonymous || entity.accessToken.isEmpty) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.router.routeInformationProvider.value.uri.path == '/') {
          widget.router.go('/auth');
        }
      });
      // Landing does not watch auth state. A late SDK event must request a
      // frame itself so the post-frame navigation also runs while it is idle.
      WidgetsBinding.instance.ensureVisualUpdate();
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
