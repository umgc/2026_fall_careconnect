import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../config/env_constant.dart';
import '../config/theme/app_theme.dart';

/// Dialog shown when user hasn't verified their email address
class EmailVerificationDialog extends StatefulWidget {
  final String email;

  const EmailVerificationDialog({
    super.key,
    required this.email,
  });

  /// Test seam: when true, [initState] skips the live WebSocket connection and
  /// verification-poll timer so callers that show this dialog can be exercised
  /// in widget tests without a real backend connection or a pending timer.
  /// Defaults to false (production behavior is unchanged).
  @visibleForTesting
  static bool debugDisableRealtime = false;

  @override
  State<EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<EmailVerificationDialog> {
  bool _isResending = false;
  String? _resendMessage;
  String? _resendError;
  WebSocketChannel? _wsChannel;
  bool _wsConnected = false;
  String _connectionMethod = 'Connecting...';
  Timer? _verificationPollTimer;
  bool _isCheckingVerification = false;

  @override
  void initState() {
    super.initState();
    if (!EmailVerificationDialog.debugDisableRealtime) {
      _connectWebSocket();
      _startVerificationPolling();
    }
  }

  @override
  void dispose() {
    _verificationPollTimer?.cancel();
    _wsChannel?.sink.close(status.normalClosure);
    super.dispose();
  }

  /// Connect to WebSocket for real-time email verification notifications
  void _connectWebSocket() {
    try {
      // Build WebSocket endpoint from configured backend URL.
      final backendUrl = Uri.parse(getBackendBaseUrl());
      final wsScheme = backendUrl.scheme == 'https' ? 'wss' : 'ws';
      final wsHost =
          backendUrl.hasPort ? '${backendUrl.host}:${backendUrl.port}' : backendUrl.host;
      final wsUrl = Uri.parse('$wsScheme://$wsHost/ws/careconnect');
      _wsChannel = WebSocketChannel.connect(wsUrl);

      // Listen to WebSocket messages
      _wsChannel!.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          if (mounted) {
            setState(() {
              _wsConnected = false;
              _connectionMethod = 'WebSocket Error - Using auto-check';
            });
          }
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          if (mounted) {
            setState(() {
              _wsConnected = false;
              _connectionMethod = 'WebSocket Disconnected - Using auto-check';
            });
          }
        },
      );

      // Send subscription message after a short delay to ensure connection
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _wsChannel != null) {
          _wsChannel!.sink.add(jsonEncode({
            'type': 'subscribe-email-verification',
            'email': widget.email,
          }));
          debugPrint('WebSocket subscription request sent for: ${widget.email}');
        }
      });

      if (mounted) {
        setState(() {
          _wsConnected = true;
          _connectionMethod = 'WebSocket (Real-time)';
        });
      }
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      if (mounted) {
        setState(() {
          _wsConnected = false;
          _connectionMethod = 'WebSocket Failed - Using auto-check';
        });
      }
    }
  }

  void _startVerificationPolling() {
    _checkVerificationStatus();
    _verificationPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkVerificationStatus();
    });
  }

  Future<void> _checkVerificationStatus() async {
    if (_isCheckingVerification || !mounted) return;
    _isCheckingVerification = true;
    try {
      final uri = Uri.parse(
        '${ApiConstants.auth}/check-verification?email=${Uri.encodeQueryComponent(widget.email)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final verified = data is Map<String, dynamic> && data['verified'] == true;
        if (verified) {
          _handleEmailVerified();
        }
      }
    } catch (_) {
      // Ignore transient polling failures; keep polling.
    } finally {
      _isCheckingVerification = false;
    }
  }

  /// Handle incoming WebSocket messages
  void _handleWebSocketMessage(dynamic data) {
    try {
      final message = jsonDecode(data.toString());
      debugPrint('WebSocket message received: ${message['type']}');

      switch (message['type']) {
        case 'connection-established':
          debugPrint('WebSocket connection established');
          break;
        case 'email-verification-subscription-confirmed':
          if (mounted) {
            setState(() {
              _connectionMethod = 'WebSocket (Real-time) ✓';
            });
          }
          break;
        case 'email-verified':
          _handleEmailVerified();
          break;
        case 'error':
          debugPrint('WebSocket error: ${message['message']}');
          break;
      }
    } catch (e) {
      debugPrint('Error handling WebSocket message: $e');
    }
  }

  /// Handle email verified notification
  void _handleEmailVerified() async {
    _verificationPollTimer?.cancel();
    _wsChannel?.sink.close(status.normalClosure);

    if (mounted) {
      // Show success message before closing
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified successfully! You can now log in.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      // Wait a moment for user to see the message
      await Future.delayed(const Duration(milliseconds: 500));
      Navigator.of(context).pop(true); // Return true to indicate verified
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
      _resendMessage = null;
      _resendError = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.auth}/resend-verification'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'email': widget.email}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _resendMessage = 'Verification email sent successfully!';
        });
      } else {
        setState(() {
          _resendError = 'Failed to send verification email. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _resendError = 'Error sending verification email: $e';
      });
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.email_outlined, color: AppTheme.primary, size: 28),
          SizedBox(width: 8),
          Text('Email Verification Required'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Please check your email and click the verification link to activate your account.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Email Address',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.email,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Check your inbox and spam folder',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.purple.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: _wsConnected
                      ? Icon(
                          Icons.check_circle,
                          color: Colors.green.shade700,
                          size: 16,
                        )
                      : CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.purple.shade700),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waiting for verification...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _connectionMethod,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.purple.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_resendMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resendMessage!,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_resendError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resendError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: _isResending ? null : _resendVerificationEmail,
          icon: _isResending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.refresh),
          label: Text(_isResending ? 'Sending...' : 'Resend Email'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: AppTheme.textLight,
          ),
        ),
      ],
    );
  }
}
