import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/auth_service.dart';
import '../../../../config/theme/app_theme.dart';

class PasswordResetConfirmScreen extends StatefulWidget {
  final String token;
  final String email;

  const PasswordResetConfirmScreen({
    super.key,
    required this.token,
    required this.email,
  });

  @override
  State<PasswordResetConfirmScreen> createState() =>
      _PasswordResetConfirmScreenState();
}

class _PasswordResetConfirmScreenState
    extends State<PasswordResetConfirmScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter a new password';
        _message = null;
      });
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _error = 'Passwords do not match';
        _message = null;
      });
      return;
    }

    if (_passwordController.text.length < 6) {
      setState(() {
        _error = 'Password must be at least 6 characters';
        _message = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });

    try {
      final result = await AuthService.resetPassword(
        email: widget.email,
        resetToken: widget.token,
        newPassword: _passwordController.text.trim(),
        t: AppLocalizations.of(context)!,
      );

      setState(() {
        _message = result;
        _isLoading = false;
      });

      // Navigate back to login after successful reset
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.go('/login');
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to reset password: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
        elevation: 2,
        title: const Text('Reset Password'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Care Connect',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                    shadows: const [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 1,
                        color: Colors.black26,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Closer Connections. Better Care.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Set New Password',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: AppTheme.inputDecoration('New Password'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: AppTheme.inputDecoration('Confirm New Password'),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.error.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppTheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppTheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_message != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.success.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: AppTheme.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _message!,
                            style: const TextStyle(color: AppTheme.success),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: AppTheme.primaryButtonStyle,
                    onPressed: _isLoading ? null : _resetPassword,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppTheme.textLight,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Reset Password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
