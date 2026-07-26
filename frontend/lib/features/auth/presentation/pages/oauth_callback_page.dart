import 'dart:convert';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../services/api_service.dart';
import '../../../../providers/user_provider.dart';
import '../../../../config/router/app_router.dart';

class OAuthCallbackPage extends StatefulWidget {
  final String? token;
  final String? user;
  final String? error;

  const OAuthCallbackPage({super.key, this.token, this.user, this.error});

  @override
  State<OAuthCallbackPage> createState() => _OAuthCallbackPageState();
}

class _OAuthCallbackPageState extends State<OAuthCallbackPage> {
  String _status = 'Processing OAuth callback...';
  bool _isError = false;

  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _processOAuthCallback();
  }

  Future<void> _processOAuthCallback() async {
    final t = AppLocalizations.of(context)!;
    try {
      setState(() {
        _status = '${t.oauthcallback_initilizeAuth}...';
        _isError = false;
      });

      // Add a small delay to show the loading state
      await Future.delayed(const Duration(milliseconds: 500));

      // ✅ HANDLE OAUTH ERRORS
      if (widget.error != null) {
        setState(() {
          _status = _getErrorMessage(widget.error!);
          _isError = true;
        });
        _redirectToLogin();
        return;
      }

      // Check if we have required parameters
      if (widget.token == null || widget.user == null) {
        setState(() {
          _status = t.oauthcallback_missingAuthData;
          _isError = true;
        });
        _redirectToLogin();
        return;
      }

      setState(() {
        _status = '${t.oauthcallback_savingAuthData}...';
      });

      // Parse user data (it's URL encoded)
      final userDataString = Uri.decodeComponent(widget.user!);
      final userData = jsonDecode(userDataString);
      final userSession = UserSession.fromJson(userData);

      // Save JWT token
      await ApiService.saveJWTToken(widget.token!);

      setState(() {
        _status = '${t.oauthcallback_completeSignIn}...';
      });

      // Save user to provider
      if (mounted) {
        Provider.of<UserProvider>(context, listen: false).setUser(userSession);

        // Small delay to ensure everything is saved
        await Future.delayed(const Duration(milliseconds: 300));

        // Navigate to appropriate dashboard based on role
        if (mounted) {
          navigateToDashboard(context, routePatientToDailyBrief: true);
        }

        // Check for invalid role
        if (userSession.role.toUpperCase() != 'CAREGIVER' &&
            userSession.role.toUpperCase() != 'PATIENT') {
          setState(() {
            _status = '${t.oauthcallback_unknownUserRole}: ${userSession.role}';
            _isError = true;
          });
          _redirectToLogin();
        }
      }
    } catch (e) {
      setState(() {
        _status = '${t.oauthcallback_failedToProcessAuth}: $e';
        _isError = true;
      });
      _redirectToLogin();
    }
  }

  // ✅ IMPROVED ERROR MESSAGES
  String _getErrorMessage(String error) {
    final t = AppLocalizations.of(context)!;
    switch (error.toLowerCase()) {
      case 'oauth_failed':
        return t.oauthcallback_oauthFailed;
      case 'access_denied':
        return t.oauthcallback_accessDenied;
      case 'invalid_request':
        return t.oauthcallback_invalidRequest;
      case 'server_error':
        return t.oauthcallback_serverError;
      default:
        return '${t.oauthcallback_authError}: $error';
    }
  }

  void _redirectToLogin() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        context.go('/login');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Text(
                'Care Connect',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003366),
                ),
              ),
              const SizedBox(height: 40),

              // Status indicator
              if (!_isError) ...[
                const CircularProgressIndicator(color: Color(0xFF003366)),
                const SizedBox(height: 24),
              ] else ...[
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 24),
              ],

              // Status text
              Text(
                _status,
                style: TextStyle(
                  fontSize: 16,
                  color: _isError ? Colors.red : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),

              if (_isError) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                  ),
                  child: Text(
                    t.signup_backLoginButton,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
