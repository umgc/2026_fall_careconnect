import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/invite_result.dart';
import 'services/invite_service.dart';

/// QR-based invite share screen for caregivers (issue #69).
///
/// Generates a care-circle invite via [InviteService], renders the invite URL
/// as a scannable QR code, and offers QR / deep-link / share options. Displays
/// the invite expiration and link type, and surfaces actionable errors when
/// generation fails.
///
/// Extends the app's existing emergency-QR pattern (qr_flutter + share_plus +
/// url_launcher) rather than introducing new libraries.
class InviteQrScreen extends StatefulWidget {
  /// The care-circle link this invite is scoped to.
  final int linkId;

  /// Optional email to pre-scope the invite to a specific recipient.
  final String? invitedEmail;

  /// Optional human-readable reason shown to the invitee ("Who Invited Me?").
  final String? inviteReason;

  const InviteQrScreen({
    super.key,
    required this.linkId,
    this.invitedEmail,
    this.inviteReason,
  });

  @override
  State<InviteQrScreen> createState() => _InviteQrScreenState();
}

class _InviteQrScreenState extends State<InviteQrScreen> {
  bool _loading = true;
  String? _error;
  InviteResult? _invite;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await InviteService.generateInvite(
        linkId: widget.linkId,
        invitedEmail: widget.invitedEmail,
        inviteReason: widget.inviteReason,
      );
      if (!mounted) return;
      setState(() {
        _invite = result;
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
        _error = 'Something went wrong generating the invite. Please try again.';
        _loading = false;
      });
    }
  }

  String _formatExpiry(DateTime? expiresAt) {
    if (expiresAt == null) return 'No expiration';
    final local = expiresAt.toLocal();
    final date = '${local.year}-${_two(local.month)}-${_two(local.day)}';
    final time = '${_two(local.hour)}:${_two(local.minute)}';
    return 'Expires $date at $time';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _prettyLinkType(String raw) {
    switch (raw) {
      case 'PERMANENT':
        return 'Permanent link';
      case 'TEMPORARY':
        return 'Temporary link';
      case 'EMERGENCY':
        return 'Emergency link';
      default:
        return raw;
    }
  }

  String _inviteUrlForCurrentSession(InviteResult invite) {
    // Web/local dev: always point to the currently running app shell so hash
    // routing works (`/#/invite/{token}`) and "Open link" doesn't jump to a
    // different host like app.careconnect.io.
    if (kIsWeb && invite.token.isNotEmpty) {
      return '${Uri.base.origin}/#/invite/${invite.token}';
    }
    return invite.inviteUrl;
  }

  Future<void> _copyUrl(BuildContext context) async {
    final invite = _invite;
    if (invite == null) return;
    final url = _inviteUrlForCurrentSession(invite);
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied to clipboard')),
    );
  }

  Future<void> _shareUrl(BuildContext context) async {
    final invite = _invite;
    if (invite == null) return;
    final url = _inviteUrlForCurrentSession(invite);
    final reason = widget.inviteReason;
    final text = reason != null && reason.isNotEmpty
        ? '$reason\n\nJoin my CareConnect care circle: $url'
        : 'Join my CareConnect care circle: $url';
    await SharePlus.instance.share(ShareParams(text: text, subject: 'CareConnect care-circle invite'));
  }

  Future<void> _openDeepLink(BuildContext context) async {
    final invite = _invite;
    if (invite == null) return;
    final url = _inviteUrlForCurrentSession(invite);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite link is invalid.')),
      );
      return;
    }

    // Web/local robustness: try opening in a new browser tab first.
    bool opened = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );

    // Fallback for platforms where default mode/new-tab is unavailable.
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    // Last-resort fallback: if this is a CareConnect invite URL, route directly
    // to the local invite landing path so local dev flow still works.
    if (!opened) {
      final token = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
      if (token != null && token.isNotEmpty && context.mounted) {
        context.go('/invite/$token');
        return;
      }
    }

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the invite link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Invite'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(context, theme),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildError(context, theme);
    }

    final invite = _invite!;
    final inviteUrl = _inviteUrlForCurrentSession(invite);
    return SingleChildScrollView(
      child: Column(
        children: [
          // QR code card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: inviteUrl,
              version: QrVersions.auto,
              size: 260,
              gapless: false,
              backgroundColor: theme.colorScheme.surface,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: theme.colorScheme.onSurface,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Metadata: link type + expiration
          _buildInfoChips(theme, invite),
          const SizedBox(height: 8),

          // The URL itself (selectable), with copy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Flexible (not Expanded) so the copy icon sits beside the
                // URL instead of being pushed to the far right of the row.
                Flexible(
                  child: SelectableText(
                    inviteUrl,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy link',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyUrl(context),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.only(left: 4),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Share + deep-link actions
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareUrl(context),
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share invite'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openDeepLink(context),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open link'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyUrl(context),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy link'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChips(ThemeData theme, InviteResult invite) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.link, size: 16),
          label: Text(_prettyLinkType(invite.linkType)),
        ),
        Chip(
          avatar: const Icon(Icons.schedule, size: 16),
          label: Text(_formatExpiry(invite.expiresAt)),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
