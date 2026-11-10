import 'package:app/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/auth_provider.dart';
import '../../infrastructure/oauth_redirect.dart';
import '../providers/auth_notifier.dart';
import '../widgets/brand_header.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  late final TextEditingController fullNameController;
  late final TextEditingController emailController;
  late final TextEditingController passwordController;
  late final TextEditingController confirmController;
  late final GlobalKey<FormState> formKey;
  bool _passwordRegistrationRequested = false;
  bool _handlingAuthNavigation = false;

  @override
  void initState() {
    super.initState();
    fullNameController = TextEditingController();
    emailController = TextEditingController();
    passwordController = TextEditingController();
    confirmController = TextEditingController();
    formKey = GlobalKey<FormState>();
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;
    final theme = Theme.of(context);

    // Listen for authentication state changes
    ref.listen(authStateProvider, (previous, next) {
      next.whenOrNull(
        data: (data) async {
          if (data != null && !data.isAnonymous && !_handlingAuthNavigation) {
            _handlingAuthNavigation = true;
            // OAuth returns a completed session, not an email confirmation.
            // AuthPage owns invite joining and authenticated navigation.
            if (!_passwordRegistrationRequested) {
              if (data.accessToken.isNotEmpty) {
                context.go('/auth');
              } else {
                _handlingAuthNavigation = false;
              }
              return;
            }
            if (data.accessToken.isNotEmpty) {
              await ref.read(authStateProvider.notifier).logout();
            }
            if (!context.mounted) {
              return;
            }
            final email = emailController.text.trim();
            final encoded = Uri.encodeComponent(
              email.isEmpty ? data.email : email,
            );
            context.go('/auth/confirm?email=$encoded');
          }
        },
        error: (error, stack) {
          _passwordRegistrationRequested = false;
          _handlingAuthNavigation = false;
          String message = 'Rejestracja nie powiodła się. Spróbuj ponownie.';
          if (error is UserAlreadyExistsFailure) {
            message = 'Konto z tym adresem e-mail już istnieje.';
          } else if (error is NetworkFailure) {
            message = 'Brak połączenia z internetem.';
          } else if (error is Failure) {
            message = error.message;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        },
      );
    });

    Future<void> handleRegister() async {
      if (!(formKey.currentState?.validate() ?? false)) {
        return;
      }

      _passwordRegistrationRequested = true;
      await ref
          .read(authStateProvider.notifier)
          .register(
            fullName: fullNameController.text.trim(),
            email: emailController.text.trim(),
            password: passwordController.text,
          );
      // Navigation is handled by listener
    }

    Future<void> handleGoogleSignIn() async {
      _passwordRegistrationRequested = false;
      final redirectTo = ref.read(oauthRedirectProvider);
      await ref
          .read(authStateProvider.notifier)
          .signInWithProvider(
            provider: AuthProvider.google,
            redirectTo: redirectTo,
          );
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          const maxCardWidth = 420.0;
          final horizontalPadding = constraints.maxWidth < 600 ? 24.0 : 48.0;

          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxCardWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandHeader(maxWidth: maxCardWidth),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Zarejestruj konto',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: fullNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Imię i nazwisko',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty) {
                                    return 'Podaj imię i nazwisko';
                                  }
                                  if (text.length < 2) {
                                    return 'Imię i nazwisko jest za krótkie';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: emailController,
                                decoration: const InputDecoration(
                                  labelText: 'E-mail',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                textCapitalization: TextCapitalization.none,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty) {
                                    return 'Podaj e-mail';
                                  }
                                  final emailRegex = RegExp(
                                    r'^[^@]+@[^@]+\.[^@]+$',
                                  );
                                  if (!emailRegex.hasMatch(text)) {
                                    return 'Podaj poprawny e-mail';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: passwordController,
                                decoration: const InputDecoration(
                                  labelText: 'Hasło',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                                obscureText: true,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  final text = value ?? '';
                                  if (text.isEmpty) {
                                    return 'Podaj hasło';
                                  }
                                  if (text.length < 6) {
                                    return 'Hasło musi mieć co najmniej 6 znaków';
                                  }

                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: confirmController,
                                decoration: const InputDecoration(
                                  labelText: 'Potwierdź hasło',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                validator: (value) {
                                  if (value != passwordController.text) {
                                    return 'Hasła nie są zgodne';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => handleRegister(),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : handleRegister,
                                  child: isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Zarejestruj się'),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'lub',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                    ),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed: isLoading
                                      ? null
                                      : handleGoogleSignIn,
                                  icon: const Icon(Icons.g_mobiledata),
                                  label: const Text(
                                    'Zarejestruj się przez Google',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        if (context.mounted) {
                                          context.go('/auth');
                                        }
                                      },
                                child: const Text('Masz już konto?'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
