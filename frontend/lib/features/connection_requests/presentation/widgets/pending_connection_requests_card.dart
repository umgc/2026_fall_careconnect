import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../models/connection_request_summary.dart';
import '../../services/connection_request_service.dart';

/// Patient dashboard card listing caregivers who asked to connect. A caregiver
/// sees none of the patient's records until the patient accepts here; the card
/// renders nothing when there are no pending requests.
class PendingConnectionRequestsCard extends StatefulWidget {
  /// Loaders default to [ConnectionRequestService]; tests pass fakes.
  final Future<List<ConnectionRequestSummary>> Function() loadRequests;
  final Future<void> Function(int requestId) acceptRequest;
  final Future<void> Function(int requestId) declineRequest;

  /// Called after a request is accepted, so the dashboard can refresh.
  final VoidCallback? onAccepted;

  const PendingConnectionRequestsCard({
    super.key,
    this.loadRequests = ConnectionRequestService.incoming,
    this.acceptRequest = ConnectionRequestService.accept,
    this.declineRequest = ConnectionRequestService.decline,
    this.onAccepted,
  });

  @override
  State<PendingConnectionRequestsCard> createState() =>
      _PendingConnectionRequestsCardState();
}

class _PendingConnectionRequestsCardState
    extends State<PendingConnectionRequestsCard> {
  List<ConnectionRequestSummary> _requests = const [];
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await widget.loadRequests();
      if (mounted) setState(() => _requests = requests);
    } catch (e) {
      // The card is supplementary; a failed load leaves the dashboard as it was.
      debugPrint('PendingConnectionRequestsCard: $e');
    }
  }

  Future<void> _answer(ConnectionRequestSummary request, bool accept) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(request.id));
    try {
      if (accept) {
        await widget.acceptRequest(request.id);
      } else {
        await widget.declineRequest(request.id);
      }
      if (!mounted) return;
      setState(() =>
          _requests = _requests.where((r) => r.id != request.id).toList());
      messenger.showSnackBar(SnackBar(
        content: Text(accept
            ? l10n.connectionRequests_accepted(request.caregiverName)
            : l10n.connectionRequests_declined),
      ));
      if (accept) widget.onAccepted?.call();
    } catch (e) {
      debugPrint('PendingConnectionRequestsCard: $e');
      if (!mounted) return;
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.connectionRequests_error)));
    } finally {
      if (mounted) setState(() => _busy.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_requests.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.connectionRequests_title,
                  style: theme.textTheme.titleMedium),
              for (final request in _requests) ...[
                const SizedBox(height: 12),
                Text(l10n
                    .connectionRequests_wantsToConnect(request.caregiverName)),
                if (request.message != null && request.message!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('"${request.message}"',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: Key('decline-${request.id}'),
                      onPressed: _busy.contains(request.id)
                          ? null
                          : () => _answer(request, false),
                      child: Text(l10n.connectionRequests_decline),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: Key('accept-${request.id}'),
                      onPressed: _busy.contains(request.id)
                          ? null
                          : () => _answer(request, true),
                      child: Text(l10n.connectionRequests_accept),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
