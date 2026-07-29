import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/stml_service.dart';

/// STML-4: search recall history by keyword, sender, or date range.
class StmlSearchPage extends StatefulWidget {
  const StmlSearchPage({super.key});

  @override
  State<StmlSearchPage> createState() => _StmlSearchPageState();
}

class _StmlSearchPageState extends State<StmlSearchPage> {
  final _keywordController = TextEditingController();
  final _senderController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;

  bool _isSearching = false;
  bool _hasSearched = false;
  String? _error;
  StmlSearchResults? _results;

  @override
  void dispose() {
    _keywordController.dispose();
    _senderController.dispose();
    super.dispose();
  }

  bool get _hasAnyFilter =>
      _keywordController.text.trim().isNotEmpty ||
      _senderController.text.trim().isNotEmpty ||
      _fromDate != null ||
      _toDate != null;

  Future<void> _search() async {
    if (!_hasAnyFilter || _isSearching) return;

    final patientId = context.read<UserProvider>().user?.patientId;
    if (patientId == null) {
      setState(() => _error = 'No patient is selected for this account.');
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _error = null;
    });

    try {
      final results = await StmlService.search(
        patientId: patientId,
        keyword: _keywordController.text.trim(),
        sender: _senderController.text.trim(),
        fromDate: _fromDate?.toIso8601String().split('T').first,
        toDate: _toDate?.toIso8601String().split('T').first,
      );
      setState(() => _results = results);
    } on StmlException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _fromDate : _toDate) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => isFrom ? _fromDate = picked : _toDate = picked);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundSecondary,
      appBar: AppBar(
        title: const Text('Search your history'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _keywordController,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'Keyword',
                    hintText: 'e.g. medication, appointment',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _senderController,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'From (caller, sender)',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: true),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _fromDate == null ? 'From date' : _formatDate(_fromDate!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: false),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _toDate == null ? 'To date' : _formatDate(_toDate!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _hasAnyFilter && !_isSearching ? _search : null,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.textLight,
                    ),
                    child: _isSearching
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.textLight,
                            ),
                          )
                        : const Text('Search', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (!_hasSearched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              Text(
                'Enter a keyword, sender, or date range to search your call, '
                'visit, and mail history.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _search, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final results = _results?.results ?? const [];
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No results found for these filters.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, index) => _SearchResultCard(result: results[index]),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final StmlSearchResult result;

  const _SearchResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 18, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                result.sourceType,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                result.date,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          if (result.sender.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              result.sender,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Text(result.content, style: const TextStyle(fontSize: 18, height: 1.3)),
        ],
      ),
    );
  }
}
