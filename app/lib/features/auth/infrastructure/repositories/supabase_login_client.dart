import 'package:app/core/global_dependencies.dart';
import 'package:app/core/error/failure.dart';
import 'package:app/core/error/supabase_error_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logging/logging.dart';

import '../../domain/entities/auth_entity.dart';
import '../../domain/entities/auth_provider.dart' as domain_auth;
import '../../domain/repositories/login_repository.dart';

class SupabaseLoginClient implements LoginRepository {
  final SupabaseClient _supabase;
  final Logger _logger = Logger('SupabaseLoginClient');

  SupabaseLoginClient(this._supabase);

  OAuthProvider _mapProvider(domain_auth.AuthProvider provider) {
    switch (provider) {
      case domain_auth.AuthProvider.google:
        return OAuthProvider.google;
    }
  }

  @override
  Future<AuthEntity> login(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null || response.session == null) {
        throw const ServerFailure('Login failed: No user or session returned');
      }

      _logger.info('Login successful for user: ${response.user!.id}');

      return AuthEntity(
        accessToken: response.session!.accessToken,
        refreshToken: response.session!.refreshToken!,
        userId: response.user!.id,
        isAnonymous: false,
        email: response.user!.email!,
      );
    } catch (e, stackTrace) {
      _logger.severe('Login failed', e, stackTrace);
      throw e.toFailure();
    }
  }

  @override
  Future<AuthEntity> register(
    String email,
    String password,
    String fullName,
  ) async {
    try {
      final trimmedFullName = fullName.trim();
      final metadata = <String, dynamic>{};
      if (trimmedFullName.isNotEmpty) {
        metadata['full_name'] = trimmedFullName;
      }
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );
      final session = response.session;
      final user = response.user;

      if (user == null) {
        throw const ServerFailure('Registration failed: No user returned');
      }

      _logger.info('Registration successful for user: ${response.user!.id}');

      return AuthEntity(
        accessToken: session?.accessToken ?? '',
        refreshToken: session?.refreshToken ?? '',
        userId: user.id,
        isAnonymous: false,
        email: user.email ?? email,
      );
    } catch (e, stackTrace) {
      _logger.severe('Registration failed', e, stackTrace);
      throw e.toFailure();
    }
  }

  @override
  Future<AuthEntity> guestLogin() async {
    try {
      final response = await _supabase.auth.signInAnonymously();

      if (response.user == null || response.session == null) {
        throw const GuestLoginFailure();
      }

      _logger.info('Guest login successful for user: ${response.user!.id}');

      return AuthEntity(
        accessToken: response.session!.accessToken,
        refreshToken: response.session!.refreshToken!,
        userId: response.user!.id,
        isAnonymous: true,
        email: '',
      );
    } catch (e, stackTrace) {
      _logger.severe('Guest login failed', e, stackTrace);
      throw e.toFailure();
    }
  }

  @override
  Future<AuthEntity> refreshSession(String? refreshToken) async {
    try {
      if (refreshToken == null) {
        throw const ServerFailure('No refresh token provided');
      }

      final response = await _supabase.auth.refreshSession(refreshToken);
      if (response.session == null) {
        throw const ServerFailure(
          'Session refresh failed: No session returned',
        );
      }

      return AuthEntity(
        accessToken: response.session!.accessToken,
        refreshToken: response.session!.refreshToken!,
        userId: response.user!.id,
        isAnonymous: false,
        email: response.user!.email!,
      );
    } catch (e, stackTrace) {
      _logger.warning('Session refresh failed', e, stackTrace);
      throw e.toFailure();
    }
  }

  @override
  Future<void> signInWithProvider(
    domain_auth.AuthProvider provider, {
    String? redirectTo,
  }) async {
    try {
      final launched = await _supabase.auth.signInWithOAuth(
        _mapProvider(provider),
        redirectTo: redirectTo,
      );
      if (!launched) {
        throw const ServerFailure('OAuth sign-in could not be started');
      }
    } catch (e, stackTrace) {
      _logger.severe('OAuth sign-in failed', e, stackTrace);
      throw e.toFailure();
    }
  }

  @override
  Future<void> requestPasswordReset(String email, {String? redirectTo}) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
    } catch (e, stackTrace) {
      _logger.severe('Password reset request failed', e, stackTrace);
      throw e.toFailure();
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      if (_supabase.auth.currentSession == null) {
        throw const UnauthorizedFailure('Missing recovery session');
      }
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e, stackTrace) {
      _logger.severe('Password update failed', e, stackTrace);
      throw e.toFailure();
    }
  }
}

final supabaseLoginClientProvider = Provider<SupabaseLoginClient>((ref) {
  final supabase = ref.read(supabaseProvider);
  return SupabaseLoginClient(supabase);
});
