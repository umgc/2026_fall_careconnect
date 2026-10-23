import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/medicare_sharing_service.dart';

/// Route /medicare-sharing (WBS 6.2.59, #323). The patient chooses which of
/// their linked caregivers can see their Medicare coverage and visits.
///
/// Each switch saves straight away. While it saves, that switch is disabled;
/// if the save fails the switch goes back to where it was and an error says
/// so. Every change is announced, and the words "Sharing" / "Not sharing"
/// carry the state, not the switch's colour alone (WCAG 2.1 AA).
class MedicareSharingPage extends StatefulWidget {
  const MedicareSharingPage({super.key});

  @override
  State<MedicareSharingPage> createState() => _MedicareSharingPageState();
}

enum _Load { loading, loaded, failed }

class _MedicareSharingPageState extends State<MedicareSharingPage> {
  static const _teal = Color(0xFF00788F);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF4B5563);
  static const _border = Color(0xFFE5E7EB);
  static const _success = Color(0xFF047857);
  static const _error = Color(0xFFB91C1C);

  _Load _load = _Load.loading;
  MedicareSharingError? _loadError;
  List<SharingCaregiver> _caregivers = const [];
  final Set<int> _saving = {};
  _Banner? _banner;
  // A row is disabled while it saves, which takes keyboard focus away; these
  // let focus return to the row afterwards (DEF-MCR-32).
  final Map<int, FocusNode> _focus = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusFor(int id) => _focus.putIfAbsent(id, FocusNode.new);

  Future<void> _refresh() async {
    setState(() {
      _load = _Load.loading;
      _banner = null;
    });
    try {
      final list = await MedicareSharingService.instance.load();
      if (!mounted) return;
      setState(() {
        _caregivers = list;
        _load = _Load.loaded;
      });
    } on MedicareSharingException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.error;
        _load = _Load.failed;
      });
    }
  }

  Future<void> _toggle(SharingCaregiver caregiver, bool share) async {
    final id = caregiver.userId;
    final hadFocus = _focus[id]?.hasFocus ?? false;
    setState(() {
      _saving.add(id);
      _banner = null;
      _replace(id, share);
    });
    final ok = await MedicareSharingService.instance.setShared(id, share);
    if (!mounted) return;
    setState(() {
      _saving.remove(id);
      if (ok) {
        _banner = _Banner(
          share
              ? '${caregiver.name} can now see your Medicare coverage and visits.'
              : '${caregiver.name} can no longer see your Medicare information.',
          error: false,
        );
      } else {
        _replace(id, !share); // Put the switch back where it was.
        _banner = _Banner(
          share
              ? 'Couldn\'t confirm sharing with ${caregiver.name}. The switch shows the last confirmed state. Please try again.'
              : 'Couldn\'t confirm that sharing stopped for ${caregiver.name}. The switch shows the last confirmed state. Please try again.',
          error: true,
        );
      }
    });
    if (hadFocus) {
      // The row is enabled again after this frame; give its focus back then.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus[id]?.requestFocus();
      });
    }
  }

  void _replace(int id, bool shared) {
    _caregivers = [
      for (final c in _caregivers)
        c.userId == id ? c.copyWith(shared: shared) : c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0,
        titleTextStyle: const TextStyle(
            color: _text, fontSize: 20, fontWeight: FontWeight.w600),
        title: const Text('Share Medicare'),
        leading: IconButton(
          tooltip: 'Back to Connect Medicare',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/medicare-connect'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Choose which of your caregivers can see your Medicare '
                  'coverage and visits. You can turn sharing off at any time, '
                  'and it stops right away.',
                  style: TextStyle(fontSize: 16, height: 1.45, color: _text),
                ),
                const SizedBox(height: 16),
                if (_banner != null) ...[
                  _bannerView(_banner!),
                  const SizedBox(height: 12),
                ],
                ..._body(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_load) {
      case _Load.loading:
        return [
          Center(
            child: Semantics(
              label: 'Loading your caregivers',
              child: const CircularProgressIndicator(color: _teal),
            ),
          ),
        ];
      case _Load.failed:
        return [_failed()];
      case _Load.loaded:
        if (_caregivers.isEmpty) {
          return [
            _card(const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'You don\'t have any linked caregivers yet. When a caregiver '
                'is linked to you, they appear here and you can choose to '
                'share your Medicare information with them.',
                style: TextStyle(fontSize: 15, height: 1.4, color: _text),
              ),
            )),
          ];
        }
        return [
          _card(Column(
            children: [
              for (var i = 0; i < _caregivers.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: _border),
                _row(_caregivers[i]),
              ],
            ],
          )),
        ];
    }
  }

  Widget _row(SharingCaregiver c) {
    final saving = _saving.contains(c.userId);
    final stateText =
        saving ? 'Saving…' : (c.shared ? 'Sharing' : 'Not sharing');
    return SwitchListTile(
      // The tile's label is read with the switch, so one focus stop says
      // who it is, what it controls and its state.
      title: Text(c.name,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: _text)),
      subtitle: Text(
        c.email == null ? stateText : '$stateText · ${c.email}',
        style: TextStyle(
            fontSize: 14, color: c.shared && !saving ? _success : _muted),
      ),
      secondary: ExcludeSemantics(
        child: Icon(c.shared ? Icons.visibility : Icons.visibility_off_outlined,
            color: c.shared ? _success : _muted),
      ),
      value: c.shared,
      focusNode: _focusFor(c.userId),
      activeThumbColor: Colors.white,
      activeTrackColor: _teal,
      onChanged: saving ? null : (v) => _toggle(c, v),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _failed() {
    final message = switch (_loadError) {
      MedicareSharingError.signedOut =>
        'Your sign-in has expired. Please sign in again.',
      MedicareSharingError.notPatient =>
        'Only the patient can choose who sees their Medicare information.',
      MedicareSharingError.network =>
        'Couldn\'t reach CareConnect. Check your connection and try again.',
      _ => 'Couldn\'t load your caregivers. Please try again.',
    };
    final canRetry = _loadError != MedicareSharingError.notPatient &&
        _loadError != MedicareSharingError.signedOut;
    return _card(Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(message,
                style:
                    const TextStyle(fontSize: 15, height: 1.4, color: _error)),
          ),
          if (canRetry) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _refresh,
              style: TextButton.styleFrom(
                  foregroundColor: _teal, minimumSize: const Size(48, 48)),
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    ));
  }

  // A Material, not a decorated Container, so the switch rows' ink and focus
  // highlight paint on the card instead of underneath it.
  Widget _card(Widget child) => Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _border),
        ),
        child: child,
      );

  Widget _bannerView(_Banner b) {
    final fg = b.error ? _error : _success;
    final bg = b.error ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(b.error ? Icons.error_outline : Icons.check_circle,
                  color: fg, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(b.text,
                  style: TextStyle(color: fg, fontSize: 14, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner {
  final String text;
  final bool error;
  const _Banner(this.text, {required this.error});
}
