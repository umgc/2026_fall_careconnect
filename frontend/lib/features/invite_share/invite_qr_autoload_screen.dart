import 'package:flutter/material.dart';

import 'invite_qr_screen.dart';
import 'services/invite_service.dart';

/// Resolves the current patient's care-circle link ID and then opens the
/// invite QR experience without requiring manual URL parameters.
class InviteQrAutoloadScreen extends StatefulWidget {
  final String? invitedEmail;
  final String? inviteReason;

  const InviteQrAutoloadScreen({
    super.key,
    this.invitedEmail,
    this.inviteReason,
  });

  @override
  State<InviteQrAutoloadScreen> createState() => _InviteQrAutoloadScreenState();
}

class _InviteQrAutoloadScreenState extends State<InviteQrAutoloadScreen> {
  bool _loading = true;
  String? _error;
  int? _linkId;

  @override
  void initState() {
    super.initState();
    _resolveLinkId();
  }

  Future<void> _resolveLinkId() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final id = await InviteService.resolveDefaultLinkIdForCurrentPatient();
      if (!mounted) return;
      setState(() {
        _linkId = id;
        _loading = false;
      });
    } on InviteException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start invite sharing. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkId = _linkId;
    if (linkId != null) {
      return InviteQrScreen(
        linkId: linkId,
        invitedEmail: widget.invitedEmail,
        inviteReason: widget.inviteReason,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Share Invite')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _error ?? 'Could not load invite flow.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _resolveLinkId,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
