import 'package:flutter/material.dart';
import '../models/identity_conflict.dart';
import '../services/identity_conflict_service.dart';

class DobConfirmationScreen extends StatefulWidget {
  const DobConfirmationScreen({super.key, this.service});

  /// Injected in tests; defaults to [IdentityConflictService].
  final IdentityConflictService? service;

  @override
  State<DobConfirmationScreen> createState() => _DobConfirmationScreenState();
}

class _DobConfirmationScreenState extends State<DobConfirmationScreen> {
  // Text colours meet WCAG 2.1 AA (4.5:1); the lighter 00A7C8 and 6B7280
  // did not on the chips, the grey value rows or the white button text.
  static const _teal = Color(0xFF006B80);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF4B5563);
  static const _border = Color(0xFFE5E7EB);
  static const _warning = Color(0xFFF59E0B);
  static const _success = Color(0xFF047857);

  late final IdentityConflictService _service =
      widget.service ?? IdentityConflictService();
  bool _loading = true;
  bool _loadFailed = false;
  List<IdentityConflict> _conflicts = [];
  final Set<int> _resolving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final list = await _service.fetchPending();
      if (!mounted) return;
      setState(() {
        _conflicts = list.where((c) => c.isDob && c.isPending).toList();
        _loading = false;
      });
    } catch (_) {
      // Never show "all caught up" when we couldn't actually check.
      if (!mounted) return;
      setState(() {
        _conflicts = [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _resolve(IdentityConflict c, bool accepted) async {
    setState(() => _resolving.add(c.id));
    var ok = false;
    try {
      ok = await _service.resolve(c.id, accepted: accepted);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _resolving.remove(c.id);
      if (ok) _conflicts.removeWhere((x) => x.id == c.id);
    });
    // A failed save keeps the card and says so; nothing changed.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? _success : const Color(0xFFB91C1C),
        content: Text(!ok
            ? 'We couldn\u2019t save your choice. Nothing was changed. Please try again.'
            : accepted
                ? 'Date of birth updated.'
                : 'Kept your current date of birth.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: const Text('Confirm your information',
            style: TextStyle(
                color: _text, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _loadFailed
              ? _loadError()
              : _conflicts.isEmpty
              ? _allDone()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _intro(),
                    const SizedBox(height: 16),
                    ..._conflicts.map(_conflictCard),
                  ],
                ),
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: _warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_conflicts.length == 1
                    ? '1 item needs your confirmation'
                    : '${_conflicts.length} items need your confirmation',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: _text)),
                const SizedBox(height: 4),
                const Text(
                  'A connected source reported a different date of birth. '
                  'Nothing changes until you choose.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictCard(IdentityConflict c) {
    final busy = _resolving.contains(c.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.fieldLabel.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: _muted,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Which date of birth is correct?',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _text)),
          const SizedBox(height: 12),
          _valueRow(
            label: 'Current',
            value: c.canonicalValueBefore,
            source: c.canonicalSourceLabel,
          ),
          const SizedBox(height: 8),
          _valueRow(
            label: 'New',
            value: c.incomingValue,
            source: c.incomingSourceLabel,
          ),
          const SizedBox(height: 8),
          const Text(
            'A different date of birth can sometimes mean records were linked '
            'by mistake. We won\u2019t change anything until you confirm.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (busy)
            const Center(child: CircularProgressIndicator(color: _teal))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: _border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _resolve(c, false),
                    child: const Text('Keep current',
                        style: TextStyle(color: _text)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _resolve(c, true),
                    child: const Text('Use new date'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _valueRow(
      {required String label, required String value, String? source}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, color: _teal, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _text)),
          const Spacer(),
          if (source != null)
            Text('From $source',
                style: const TextStyle(fontSize: 12, color: _muted)),
        ],
      ),
    );
  }

  Widget _loadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _muted, size: 44),
            const SizedBox(height: 12),
            const Text('We couldn\u2019t check your information',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _text)),
            const SizedBox(height: 6),
            const Text('Nothing was changed. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 14)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(
                  foregroundColor: _teal, minimumSize: const Size(48, 48)),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allDone() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle, color: _success, size: 44),
          SizedBox(height: 12),
          Text('You\u2019re all caught up',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('No information needs your confirmation right now.',
              style: TextStyle(color: _muted)),
        ],
      ),
    );
  }
}