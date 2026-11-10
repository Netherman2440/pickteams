import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/auth_entity.dart';
import '../../application/login_use_case.dart';
import '../../application/register_use_case.dart';
import '../../application/guest_login_use_case.dart';
import '../../application/logout_use_case.dart';
import '../../application/oauth_sign_in_use_case.dart';
import '../../../../core/error/supabase_error_extension.dart';
import '../../domain/entities/auth_provider.dart';
import '../../../../core/global_dependencies.dart';
import '../../infrastructure/repositories/token_secure_storage.dart';

final _logger = Logger('AuthNotifier');

class AuthNotifier extends Notifier<AsyncValue<AuthEntity?>> {
  late final LoginUseCase _loginUseCase = ref.read(loginUseCaseProvider);
  late final RegisterUseCase _registerUseCase = ref.read(
    registerUseCaseProvider,
  );
  late final GuestLoginUseCase _guestLoginUseCase = ref.read(
    guestLoginUseCaseProvider,
  );
  late final LogoutUseCase _logoutUseCase = ref.read(logoutUseCaseProvider);
  late final OAuthSignInUseCase _oauthSignInUseCase = ref.read(
    oauthSignInUseCaseProvider,
  );
  int _authRevision = 0;
  Future<void> _tokenWrites = Future<void>.value();

  // Publish SDK state immediately. Serialize the compatibility token mirror so
  // slow storage cannot reorder signed-in, token-refreshed and signed-out events.
  void _persist(Future<void> Function() write) {
    _tokenWrites = _tokenWrites.then((_) => write()).catchError((
      Object error,
      StackTrace stack,
    ) {
      _logger.severe('Failed to persist auth state.', error, stack);
    });
  }

  @override
  AsyncValue<AuthEntity?> build() {
    final supabase = ref.read(supabaseProvider);
    final tokenRepository = ref.read(tokenSecureStorageProvider);

    AuthEntity? initial;
    final session = supabase.auth.currentSession;
    final user = session?.user;
    if (session != null && user != null) {
      initial = AuthEntity(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
        userId: user.id,
        isAnonymous: user.isAnonymous,
        email: user.email ?? '',
      );
    }

    final sub = supabase.auth.onAuthStateChange.listen(
      (data) {
        final event = data.event;
        final session = data.session;
        final user = session?.user;

        if (event == AuthChangeEvent.signedOut) {
          _authRevision++;
          state = const AsyncValue.data(null);
          _persist(tokenRepository.clearTokens);
          return;
        }

        if (session == null || user == null) {
          return;
        }
        _authRevision++;

        final entity = AuthEntity(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken ?? '',
          userId: user.id,
          isAnonymous: user.isAnonymous,
          email: user.email ?? '',
        );

        state = AsyncValue.data(entity);
        _persist(() => tokenRepository.setTokensFromEntity(entity));
      },
      onError: (Object error, StackTrace stack) {
        _authRevision++;
        // A stale failed callback must not discard an authenticated session.
        final current = state.asData?.value;
        if (current != null &&
            !current.isAnonymous &&
            current.accessToken.isNotEmpty) {
          return;
        }
        state = AsyncValue.error(error.toFailure(), stack);
      },
    );

    ref.onDispose(sub.cancel);

    return AsyncValue.data(initial);
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _loginUseCase.execute(email, password),
    );
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final entity = await _registerUseCase.execute(email, password, fullName);

      // If email confirmation is required (no access token),
      // we might want to throw a specific message or handle it.
      // For now, returning the entity (even if partial) is fine.
      // The UI can check entity.accessToken.isEmpty if needed.
      return entity;
    });
  }

  Future<void> signInWithProvider({
    required AuthProvider provider,
    String? redirectTo,
  }) async {
    final previous = state.asData?.value;
    final revision = ++_authRevision;
    state = const AsyncValue.loading();
    try {
      await _oauthSignInUseCase.execute(provider, redirectTo: redirectTo);
      // Launch completion is not sign-in completion. Do not wait for a callback:
      // closing the external browser without one must leave the buttons usable.
      if (ref.mounted && revision == _authRevision) {
        state = AsyncValue.data(previous);
      }
    } catch (error, stackTrace) {
      if (ref.mounted && revision == _authRevision) {
        state = AsyncValue.error(error, stackTrace);
      }
    }
  }

  Future<void> guestLogin() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _guestLoginUseCase.execute());
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _logoutUseCase.execute();
      return null;
    });
  }
}

final authStateProvider =
    NotifierProvider<AuthNotifier, AsyncValue<AuthEntity?>>(AuthNotifier.new);
