import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_provider.dart';
import '../../../../services/enhanced_auth_service.dart';
import '../../../../services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';


class AlexaLoginPage extends StatefulWidget {
  const AlexaLoginPage({super.key});

  @override
  State<AlexaLoginPage> createState() => _AlexaLoginPageState();
}

class _AlexaLoginPageState extends State<AlexaLoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _busy = false;
  String? _error;
  bool _showPassword = false;
  
  // Alexa OAuth parameters
  String? _redirectUri;
  String? _state;
  bool _isAlexaFlow = false;

  // Debug logging
  String _debugLog = '';

  @override
  void initState() {
    super.initState();
    // Check for Alexa OAuth parameters in query string
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAlexaOAuthParams();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().split('.')[0];
    final logEntry = "[$timestamp] $message";
    print(logEntry);
    
    setState(() {
      _debugLog = "$logEntry\n$_debugLog";
      if (_debugLog.split('\n').length > 50) {
        _debugLog = _debugLog.split('\n').take(50).join('\n');
      }
    });
  }
Map<String, String> _mergedQueryParamsFromUriBase() {
  final base = Uri.base; 
  final preHash = base.queryParameters;


  final frag = base.fragment.trim();
  Map<String, String> postHash = const {};

  if (frag.isNotEmpty) {
    final normalized = frag.startsWith('/') ? frag : '/$frag';
    final fragUri = Uri.tryParse(normalized);
    if (fragUri != null) {
      postHash = fragUri.queryParameters;
    }
  }

  return {...preHash, ...postHash};
}
  /// Check if this is an Alexa OAuth flow by looking at URL parameters
  void _checkForAlexaOAuthParams() {
    _log("🔍 Checking for Alexa OAuth parameters...");
    
    try {
      // Try to get URL query parameters from GoRouter
      final routeState = GoRouter.of(context).routerDelegate.currentConfiguration;
      final uri = routeState.uri;
      final qp = _mergedQueryParamsFromUriBase();

      _log("Current URI: $uri");
      _log("Query Parameters: ${uri.queryParameters}");
      
      _redirectUri = qp['redirect_uri'];
      _state = qp['state'];

      // Fall back to route extra if query params don't have it
      if (_redirectUri == null) {
        final extra = routeState.extra;
        if (extra is Map<String, dynamic>) {
          _redirectUri = extra['redirect_uri'] as String?;
          _state = extra['state'] as String?;
          _log("✓ Got params from route extra - redirect_uri: $_redirectUri, state: $_state");
        }
      }
      
      // TESTING ONLY: Hardcoded fallback for debugging (remove in production)
      if (_redirectUri == null) {
        _log("⚠️ No Alexa params found - using hardcoded test values");
        _redirectUri = "https://pitangui.amazon.com/api/skill/link/M1VZ06KRKERWBD";
        _state = "test-state-123";
      }
      
      _isAlexaFlow = _redirectUri != null && _redirectUri!.isNotEmpty;
      
      if (_isAlexaFlow) {
        _log("✅ Alexa OAuth Flow Detected");
        _log("Redirect URI: $_redirectUri");
        _log("State: $_state");
      } else {
        _log("ℹ️ Standard login flow");
      }
    } catch (e) {
      _log("❌ Error checking OAuth params: $e");
    }
  }

  /// Login function that validates email and password
  Future<void> _login() async {
    // Clear previous errors
    setState(() {
      _error = null;
      _debugLog = '';
    });

    // Get email and password
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    _log("🚀 Starting login flow");
    _log("Email: $email");

    // Validate inputs
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = "Please enter your email and password.";
      });
      _log("❌ Validation failed: empty fields");
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      // Step 1: Call the auth service to login
      _log("\n📍 STEP 1: Authenticating with backend...");
      
      final authResult = await EnhancedAuthService.loginWithRoleValidation(
        email: email,
        password: password,
        t: AppLocalizations.of(context)!,
      );

      if (authResult.isSuccess) {
        _log("✅ Login Successful");
        
        // Login successful - get the JWT token
        final user = authResult.userSession!;
        final jwtToken = authResult.userSession?.token;
        
        _log("JWT Token: ${jwtToken?.substring(0, 20)}...${jwtToken?.substring(jwtToken.length - 20)}");
        
        if (mounted) {
          Provider.of<UserProvider>(context, listen: false).setUser(user);
          
          // If this is an Alexa OAuth flow, proceed to get authorization code
          if (_isAlexaFlow && jwtToken != null) {
            _log("\n📍 STEP 2: Handling Alexa OAuth flow...");
            await _handleAlexaOAuthFlow(jwtToken);
          }
        }
      } else {
        // Login failed - show error message
        _log("❌ Login failed: ${authResult.errorMessage}");
        setState(() {
          _error = authResult.errorMessage ?? "Login failed. Please try again.";
        });
      }
    } catch (e) {
      _log("❌ Exception during login: $e");
      setState(() {
        _error = "An unexpected error occurred.";
      });
    } finally {
      setState(() {
        _busy = false;
      });
    }
  }

  /// Handle Alexa OAuth flow - request temp code and redirect
  Future<void> _handleAlexaOAuthFlow(String jwtToken) async {
    try {
      setState(() {
        _error = null;
      });

      // Step 2: Request Alexa temporary code from backend
      _log("POST /v1/api/auth/sso/alexa/code");
      
      final codeResult = await AuthService.getAlexaAuthorizationCode(
        token: jwtToken,
        t: AppLocalizations.of(context)!,
      );

      _log("Response: ${codeResult['message']}");

      if (codeResult['isSuccess'] == true && codeResult['code'] != null) {
        final code = codeResult['code'] as String;
        _log("✅ Authorization code generated: $code");

        // Step 3: Build redirect URI with code and state
        _log("\n📍 STEP 3: Redirecting to Alexa...");
        
        String redirectUrl = '$_redirectUri?code=${Uri.encodeComponent(code)}';
        if (_state != null && _state!.isNotEmpty) {
          redirectUrl += '&state=${Uri.encodeComponent(_state!)}';
        }

        _log("Redirect URL: $redirectUrl");

        // Redirect to Alexa
        if (mounted) {
          _log("🔄 Launching Alexa redirect...");
          await launchUrl(Uri.parse(redirectUrl));
        }
      } else {
        _log("❌ Failed to generate code: ${codeResult['message']}");
        setState(() {
          _error = codeResult['message'] ?? "Failed to generate authorization code.";
        });
      }
    } catch (e) {
      _log("❌ Exception during Alexa OAuth: $e");
      setState(() {
        _error = "Failed to link Alexa account: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 500,
                minHeight:
                    MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 24 : 32,
                vertical: 32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo section - CareConnect Logo Image
                  Container(
                    width: isMobile ? 140 : 160,
                    height: isMobile ? 140 : 160,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/CareConnectLogo.png',
                        width: isMobile ? 120 : 140,
                        height: isMobile ? 120 : 140,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback: Show text logo
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: const Color(0xff1e3a8a),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.favorite,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'CareConnect',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xff1e3a8a),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Patient Care App',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title and Subtitle
                  Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isMobile ? 24 : 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xff1a2b4a),
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Sign in to your account to manage your health',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Form Section
                  Column(
                    children: [
                      // Email field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email Address',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xff1a2b4a),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Enter your email',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xff1e3a8a),
                                  width: 1.5,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Password field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Password',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xff1a2b4a),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Enter your password',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xff1e3a8a),
                                  width: 1.5,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showPassword = !_showPassword;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Forgot password link
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.go('/reset-password'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 0,
                            ),
                          ),
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: Color(0xff1e40af),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Debug Log (if visible)
                      if (_debugLog.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '📋 Debug Log:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _debugLog,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'Courier',
                                  color: Color(0xFF333333),
                                  height: 1.3,
                                ),
                                maxLines: 15,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Error message
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xffFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xffFECACA),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xff991b1b),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Sign In button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff1e3a8a),
                            disabledBackgroundColor:
                                const Color(0xff1e3a8a).withValues(alpha: 0.6),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Sign In',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Create account section
                      Center(
                        child: Column(
                          children: [
                            Text(
                              "Don't have an account?",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => context.go('/signup'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Create Account',
                                style: TextStyle(
                                  color: Color(0xff1a2b4a),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Security badges
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSecurityBadge('Secure', Icons.lock),
                      const SizedBox(width: 24),
                      _buildSecurityBadge('HIPAA Compliant', Icons.verified),
                      const SizedBox(width: 24),
                      _buildSecurityBadge('Accessible', Icons.accessibility),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Additional security info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'End-to-end encrypted',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff1e40af),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'AA',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'WCAG AA compliant',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBadge(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.green[600]),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}