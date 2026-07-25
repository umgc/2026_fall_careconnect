import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'models/profile_share_result.dart';
import 'services/profile_share_service.dart';

/// Patient profile share screen: creates an opaque share token and shows QR + share.
class ProfileShareScreen extends StatefulWidget {
  const ProfileShareScreen({super.key});

  @override
  State<ProfileShareScreen> createState() => _ProfileShareScreenState();
}

class _ProfileShareScreenState extends State<ProfileShareScreen> {
  bool _loading = true;
  String? _error;
  ProfileShareResult? _share;

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
      final result = await ProfileShareService.createShare();
      if (!mounted) return;
      setState(() {
        _share = result;
        _loading = false;
      });
    } on ProfileShareException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong creating the share link. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _revoke() async {
    final share = _share;
    if (share == null) return;
    try {
      await ProfileShareService.revokeShare(share.tokenId);
      if (!mounted) return;
      setState(() {
        _share = null;
        _error = 'Share link revoked. Tap Try again to create a new one.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile share link revoked')),
      );
    } on ProfileShareException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _formatExpiry(DateTime? expiresAt) {
    if (expiresAt == null) return 'No expiration';
    final local = expiresAt.toLocal();
    final date =
        '${local.year}-${_two(local.month)}-${_two(local.day)}';
    final time = '${_two(local.hour)}:${_two(local.minute)}';
    return 'Expires $date at $time';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _copyUrl(BuildContext context) async {
    final url = _share?.shareUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share link copied to clipboard')),
    );
  }

  Future<void> _shareUrl(BuildContext context) async {
    final url = _share?.shareUrl;
    if (url == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: 'View my CareConnect profile: $url',
        subject: 'CareConnect profile share',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Profile'),
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

    if (_error != null && _share == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final share = _share!;
    return SingleChildScrollView(
      child: Column(
        children: [
          Text(
            'Anyone with this link can view a limited version of your profile. '
            'Your patient ID is never included in the URL.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: share.shareUrl,
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
          const SizedBox(height: 16),
          Chip(
            avatar: const Icon(Icons.schedule, size: 16),
            label: Text(_formatExpiry(share.expiresAt)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    share.shareUrl,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy link',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyUrl(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareUrl(context),
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share profile link'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _revoke,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Revoke link'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
