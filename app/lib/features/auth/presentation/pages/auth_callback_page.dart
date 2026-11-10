import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/error/failure.dart';
import '../../domain/entities/auth_entity.dart';
import '../providers/auth_notifier.dart';

class AuthCallbackPage extends ConsumerStatefulWidget {
  const AuthCallbackPage({super.key});

  @override
  ConsumerState<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends ConsumerState<AuthCallbackPage> {
  Timer? _timeout;
  bool _timedOut = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    // Supabase Flutter owns URL parsing and PKCE on both web and native.
    // Also observe an already restored session after a cold-start callback.
    ref.listenManual<AsyncValue<AuthEntity?>>(authStateProvider, (_, next) {
      final entity = next.asData?.value;
      if (entity == null ||
          entity.isAnonymous ||
          entity.accessToken.isEmpty ||
          _navigating) {
        return;
      }
      _navigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/auth');
      });
    }, fireImmediately: true);
    _timeout = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final error = authState.error;
    final hasError = authState.hasError || _timedOut;
    String? message;

    if (hasError) {
      if (error is Failure) {
        message = error.message;
      } else {
        message = 'Logowanie nie powiodło się. Spróbuj ponownie.';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logowanie'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.login,
                size: 72,
                color: hasError ? theme.colorScheme.error : null,
              ),
              const SizedBox(height: 16),
              Text(
                hasError ? 'Nie można się zalogować' : 'Kończenie logowania',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message ?? 'Poczekaj, trwa łączenie konta.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              if (!hasError) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              // Also available when a cancelled or malformed link has no event.
              FilledButton(
                onPressed: () => context.go('/auth'),
                child: const Text('Wróć do logowania'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
