import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/presentation/hitl_review_page.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:flutter/material.dart';

/// Caregiver/clinician queue of Tier-2 Ask AI holds awaiting review.
class HitlQueuePage extends StatefulWidget {
  const HitlQueuePage({
    super.key,
    this.api,
  });

  final HitlApiService? api;

  @override
  State<HitlQueuePage> createState() => _HitlQueuePageState();
}

class _HitlQueuePageState extends State<HitlQueuePage> {
  late final HitlApiService _api;
  late Future<List<HitlQueueItem>> _future;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? HitlApiService.instance;
    _future = _api.fetchQueue();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _api.fetchQueue();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI review queue'),
        actions: [
          IconButton(
            key: const Key('hitl-queue-refresh'),
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<HitlQueueItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load the review queue.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            final items = snapshot.data ?? const <HitlQueueItem>[];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text('No held answers waiting for review.'),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final preview = item.queryPreview?.trim().isNotEmpty == true
                    ? item.queryPreview!
                    : 'Held Ask AI answer';
                final triggers = item.triggerCodes.isEmpty
                    ? 'Review required'
                    : item.triggerCodes.join(', ');
                return ListTile(
                  key: Key('hitl-queue-item-${item.heldItemId}'),
                  title: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Patient ${item.patientId} · $triggers',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => HitlReviewPage(
                          heldItemId: item.heldItemId,
                          api: _api,
                        ),
                      ),
                    );
                    if (changed == true && mounted) {
                      await _reload();
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
