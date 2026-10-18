import 'package:flutter/material.dart';
import 'package:personal_memory_os/core/utils/error_text.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/router/app_router.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _busy = false;
  String? _error;

  Future<void> _handleEmailAuth() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    final provider = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool success;
    if (_isSignUp) {
      success = await provider.signUp(email, password, email.split('@').first);
    } else {
      success = await provider.signInWithEmail(email, password);
    }
    if (!mounted) return;
    if (success) {
      context.go(AppRoutes.today);
      return;
    }
    setState(() {
      _busy = false;
      _error = friendlyError(provider.error ?? '');
    });
  }

  Future<void> _handleGoogle() async {
    if (_busy) return;
    final provider = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await provider.signInWithGoogle();
    if (!mounted) return;
    if (ok) {
      context.go(AppRoutes.today);
      return;
    }
    setState(() {
      _busy = false;
      // Closing the Google sheet is not an error; anything else is explained.
      _error = provider.error == null ? null : friendlyError(provider.error!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              _buildLogo(),
              const SizedBox(height: 40),
              Text(
                _isSignUp ? 'Create account' : 'Welcome back',
                style: AppTextStyles.displayLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Your personal memory and action layer.',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 40),
              _buildForm(),
              const SizedBox(height: 20),
              Consumer<AuthProvider>(
                builder: (_, p, __) => p.error != null
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.urgent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.urgent.withValues(alpha: 0.3)),
                        ),
                        child: Text(p.error!,
                            style: const TextStyle(
                                color: AppColors.urgent, fontSize: 13)),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Sign up",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.psychology_outlined,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Memory OS', style: AppTextStyles.titleLarge),
            Text('Personal Reminder & Memory', style: AppTextStyles.caption),
          ],
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: AppTextStyles.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'Email address',
            prefixIcon: Icon(Icons.email_outlined,
                color: AppColors.textMuted, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: AppTextStyles.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Password',
            prefixIcon: const Icon(Icons.lock_outlined,
                color: AppColors.textMuted, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.textMuted,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onSubmitted: (_) => _handleEmailAuth(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: Color(0xFF7F1D1D), height: 1.35),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Consumer<AuthProvider>(
          builder: (_, p, __) => SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (p.status == AuthStatus.unknown || _busy)
                  ? null
                  : _handleEmailAuth,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isSignUp ? 'Create account' : 'Sign in'),
            ),
          ),
        ),
        Consumer<AuthProvider>(
          builder: (_, p, __) => !p.canUseGoogle
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('google-sign-in'),
                      onPressed: (p.status == AuthStatus.unknown || _busy) ? null : _handleGoogle,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Continue with Google'),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
