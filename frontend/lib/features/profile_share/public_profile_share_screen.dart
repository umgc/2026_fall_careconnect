import 'package:flutter/material.dart';

import 'services/profile_share_service.dart';

/// Public landing page for /p/:token — resolves a limited profile via opaque token.
class PublicProfileShareScreen extends StatefulWidget {
  final String token;

  const PublicProfileShareScreen({super.key, required this.token});

  @override
  State<PublicProfileShareScreen> createState() =>
      _PublicProfileShareScreenState();
}

class _PublicProfileShareScreenState extends State<PublicProfileShareScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ProfileShareService.resolveShare(widget.token);
      if (!mounted) return;
      final status = (data['status'] as String?) ?? 'INVALID';
      if (status != 'ACTIVE') {
        setState(() {
          _error = (data['message'] as String?) ??
              'This share link is not available ($status).';
          _loading = false;
        });
        return;
      }
      setState(() {
        _profile = data;
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
        _error = 'Could not load this shared profile.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final first = (_profile?['firstName'] as String?) ?? '';
    final last = (_profile?['lastName'] as String?) ?? '';
    final name = '$first $last'.trim().isEmpty ? 'CareConnect member' : '$first $last'.trim();
    final comm = _profile?['preferredCommunicationMethod'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (comm != null && comm.isNotEmpty)
          Text('Preferred communication: $comm', style: theme.textTheme.bodyLarge)
        else
          Text(
            'Limited public profile shared via CareConnect.',
            style: theme.textTheme.bodyLarge,
          ),
        const SizedBox(height: 24),
        Text(
          'This is a limited view. Sensitive medical details are not shown.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
