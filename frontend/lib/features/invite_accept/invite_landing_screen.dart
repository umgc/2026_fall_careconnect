import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/app_router.dart';
import '../../services/auth_token_manager.dart';
import 'models/invite_preview.dart';
import 'services/invite_accept_service.dart';
import 'services/pending_invite.dart';

/// Invite-aware entry screen (issue #75).
///
/// Opened by an invite link (/invite/:token). Shows the "Who Invited Me?"
/// context (issue #59), then routes the user:
///   - not signed in  -> stash token, send to sign-up (or login) to authenticate
///   - signed in       -> accept the invite and join the care circle
///
/// Success and failure remain visible on this screen and survive the auth
/// redirect via [PendingInvite].
class InviteLandingScreen extends StatefulWidget {
  final String token;

  const InviteLandingScreen({super.key, required this.token});

  @override
  State<InviteLandingScreen> createState() => _InviteLandingScreenState();
}

enum _Phase { loading, preview, accepting, joined, failed }

class _InviteLandingScreenState extends State<InviteLandingScreen> {
  _Phase _phase = _Phase.loading;
  InvitePreview? _preview;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() => _phase = _Phase.loading);
    try {
      final preview = await InviteAcceptService.preview(widget.token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _phase = _Phase.preview;
      });
    } on InviteAcceptException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _phase = _Phase.failed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Something went wrong loading this invitation.';
        _phase = _Phase.failed;
      });
    }
  }

  /// Primary action: continue with the invite. Decides between accept-now
  /// (already signed in) and authenticate-first (stash + redirect).
  Future<void> _continue() async {
    final preview = _preview;
    if (preview == null || !preview.valid) return;

    final signedIn = await AuthTokenManager.isAuthenticated();
    if (!mounted) return;

    if (signedIn) {
      await _acceptNow();
    } else {
      // Persist the token across the auth redirect, then send the user to
      // registration. If they already have an account they can switch to login
      // from there; the token stays stashed either way.
      PendingInvite.set(widget.token);
      // Email-scoped invites want the user to sign in as the invited email.
      final route = preview.nextAction == 'SIGN_IN' ? '/login' : '/signup';
      context.push(route, extra: {
        'fromInvite': true,
        'invitedEmail': preview.invitedEmail,
      });
    }
  }

  Future<void> _acceptNow() async {
    setState(() => _phase = _Phase.accepting);
    try {
      await InviteAcceptService.accept(widget.token);
      PendingInvite.clear();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.joined;
        _message = 'You have joined the care circle.';
      });
    } on InviteAcceptException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _phase = _Phase.failed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Something went wrong accepting this invitation.';
        _phase = _Phase.failed;
      });
    }
  }

  void _goToDashboard() {
    navigateToDashboard(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Care-Circle Invitation'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: _buildContent(theme)),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    switch (_phase) {
      case _Phase.loading:
        return const CircularProgressIndicator();

      case _Phase.accepting:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Joining the care circle...'),
          ],
        );

      case _Phase.joined:
        return _buildResult(
          theme,
          icon: Icons.check_circle,
          color: Colors.green,
          title: 'Welcome aboard!',
          body: _message ?? 'You have joined the care circle.',
          actionLabel: 'Go to dashboard',
          onAction: _goToDashboard,
        );

      case _Phase.failed:
        return _buildResult(
          theme,
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
          title: 'Invitation problem',
          body: _message ?? 'This invitation could not be used.',
          actionLabel: 'Try again',
          onAction: _loadPreview,
        );

      case _Phase.preview:
        return _buildPreview(theme);
    }
  }

  Widget _buildPreview(ThemeData theme) {
    final preview = _preview!;

    if (!preview.valid) {
      // Non-valid preview (expired / revoked / accepted / invalid) — show a
      // clear, non-enumerating message with the suggested next action.
      final body = switch (preview.status) {
        'EXPIRED' => 'This invitation has expired. Ask the caregiver for a new one.',
        'REVOKED' => 'This invitation has been revoked. Ask the caregiver for a new one.',
        'ACCEPTED' => 'This invitation has already been accepted. Try signing in.',
        _ => 'This invitation link is not valid.',
      };
      final isSignIn = preview.nextAction == 'SIGN_IN';
      return _buildResult(
        theme,
        icon: Icons.info_outline,
        color: theme.colorScheme.secondary,
        title: 'Invitation unavailable',
        body: body,
        actionLabel: isSignIn ? 'Sign in' : 'Close',
        onAction: isSignIn ? () => context.push('/login') : () => context.go('/'),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.group_add, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text('You\'re invited', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(preview.contextSummary, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
        if (preview.expiresAt != null) ...[
          const SizedBox(height: 16),
          Chip(
            avatar: const Icon(Icons.schedule, size: 16),
            label: Text('Expires ${_formatDate(preview.expiresAt!)}'),
          ),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _continue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Accept invitation'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Widget _buildResult(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 56, color: color),
        const SizedBox(height: 20),
        Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(body, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(actionLabel),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
