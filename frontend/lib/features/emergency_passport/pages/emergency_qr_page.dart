import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/passport_view.dart';
import '../services/passport_service.dart';
import '../services/qr_code_store.dart';
import '../utils/qr_image.dart' as qr_image;

/// The patient's own emergency QR code (CC-12, design screen 2): show it,
/// save it as a picture, make a new one, and see what a scan shows.
///
/// The server gives a code only once, when it is made, so the app keeps it
/// on this device ([QrCodeStore]). On another device, or after a reinstall,
/// the patient makes a new code instead.
class EmergencyQrPage extends StatefulWidget {
  const EmergencyQrPage({
    super.key,
    this.service,
    this.store,
    this.makeImage,
    this.saveImage,
    this.onChangeSharing,
  });

  final PassportService? service;
  final QrCodeStore? store;

  /// Replaced in tests: drawing and saving a picture needs a real device.
  final Future<Uint8List> Function(String data)? makeImage;
  final Future<bool> Function(Uint8List png, String fileName)? saveImage;

  /// Opens the screen where the patient picks what to share. Hidden when null.
  final VoidCallback? onChangeSharing;

  @override
  State<EmergencyQrPage> createState() => _EmergencyQrPageState();
}

class _EmergencyQrPageState extends State<EmergencyQrPage> {
  static const _teal = Color(0xFF00788F);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF374151);
  static const _border = Color(0xFFD1D5DB);
  static const _green = Color(0xFF047857);
  static const _page = Color(0xFFF3F4F6);

  late final PassportService _service = widget.service ?? PassportService();
  late final QrCodeStore _store = widget.store ?? QrCodeStore();

  PassportView? _view;
  QrCodeStatus? _code;
  StoredQrCode? _saved;
  PassportError? _error;
  bool _loading = true;
  bool _making = false;
  // DEF-EMG-26: turning off has its own flag, so the screen says "Turning
  // off…" and never "Making a new code…" while a code is being turned off.
  bool _turningOff = false;
  bool _saving = false;

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
      final view = await _service.getPassport();
      final saved = await _store.read();
      if (!mounted) return;
      setState(() {
        _view = view;
        _code = view.code;
        _saved = saved;
        _loading = false;
      });
    } on PassportException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.error;
        _loading = false;
      });
    }
  }

  /// The QR to show: the one kept on this device, if it is the active code.
  String? get _qrUrl {
    final code = _code;
    final saved = _saved;
    if (code == null || saved == null) return null;
    final diff = saved.createdAt.difference(code.createdAt).inMilliseconds.abs();
    return diff < 1000 ? saved.url : null;
  }

  /// Asks before an action that stops the current code working.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        // DEF-EMG-12: the light theme's cyan button text was 2.85:1 on the
        // white dialog; the theme's own text colour reads in both themes.
        final actionStyle = TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.onSurface);
        return AlertDialog(
          title: Text(title),
          content: Text(message, style: const TextStyle(fontSize: 16, height: 1.4)),
          actions: [
            TextButton(
              style: actionStyle,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: actionStyle,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(action),
            ),
          ],
        );
      },
    );
    return ok == true && mounted;
  }

  Future<void> _makeNewCode() async {
    if (_code != null) {
      final ok = await _confirm(
        title: 'Make a new code?',
        message: 'Your current QR code will stop working right away. If you '
            'saved it as a picture or lock screen, save the new one too.',
        action: 'Make new code',
      );
      if (!ok) return;
    }

    setState(() => _making = true);
    try {
      final code = await _service.makeNewCode();
      final saved = StoredQrCode(url: code.url, createdAt: code.createdAt);
      await _store.save(saved);
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _code = QrCodeStatus(createdAt: code.createdAt);
        _making = false;
      });
      _snack('Your new QR code is ready. Save it so you have it with you.');
    } on PassportException {
      if (!mounted) return;
      setState(() => _making = false);
      _snack('We couldn\'t make a new code. Please try again.');
    }
  }

  Future<void> _turnOff() async {
    final ok = await _confirm(
      title: 'Turn off your QR code?',
      message: 'Anyone who scans it will see "This code isn\'t active". A '
          'saved picture or lock screen stops working too. You can make a new '
          'code at any time.',
      action: 'Turn off',
    );
    if (!ok) return;

    setState(() => _turningOff = true);
    try {
      await _service.turnOffCode();
      await _store.clear();
      if (!mounted) return;
      setState(() {
        _code = null;
        _saved = null;
        _turningOff = false;
      });
      _snack('Your QR code is turned off.');
    } on PassportException {
      if (!mounted) return;
      setState(() => _turningOff = false);
      _snack('We couldn\'t turn off your code. Please try again.');
    }
  }

  Future<void> _saveImage(String url) async {
    setState(() => _saving = true);
    var ok = false;
    try {
      final png = await (widget.makeImage ?? qr_image.lockScreenQrPng)(url);
      ok = await (widget.saveImage ?? qr_image.saveQrImage)(
          png, 'careconnect-emergency-qr.png');
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _snack(ok
        ? 'QR image ready. Save it to your photos.'
        : 'We couldn\'t save the image. You can take a screenshot instead.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Emergency QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _back,
        ),
      ),
      body: _loading
          ? Center(
              child: Semantics(
                label: 'Loading your emergency QR',
                liveRegion: true,
                child: const CircularProgressIndicator(),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _error != null ? _errorView(_error!) : _content(),
                ),
              ),
            ),
    );
  }

  Widget _content() {
    final view = _view!;
    final url = _qrUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (url != null)
          _qrCard(view, url)
        else if (_code != null)
          _notOnThisDevice()
        else
          _noCodeYet(),
        _whatAScanShows(view),
        _card(
          child: _body('Anyone who scans your code sees your name, age and the '
              'sections marked Shown. If you lose your phone or a saved image, '
              'make a new code. The old one stops working right away.'),
        ),
      ],
    );
  }

  // ---------- The QR ----------

  Widget _qrCard(PassportView view, String url) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Semantics(
                label: 'Your emergency QR code',
                image: true,
                excludeSemantics: true,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(view.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: _text)),
            const SizedBox(height: 6),
            _status(),
            const SizedBox(height: 16),
            _primaryButton(
              label: _saving ? 'Saving…' : 'Save QR image',
              icon: Icons.download,
              onPressed: _saving ? null : () => _saveImage(url),
            ),
            const SizedBox(height: 8),
            _body('Tip: set the saved image as your lock screen so it can be '
                'scanned without unlocking your phone.'),
            const SizedBox(height: 12),
            _secondaryButton(
              label: _making ? 'Making a new code…' : 'Make a new code',
              onPressed: _making || _turningOff ? null : _makeNewCode,
            ),
            const SizedBox(height: 4),
            _turnOffButton(),
          ],
        ),
      );

  Widget _status() {
    final code = _code!;
    final created = DateFormat('MMM d, yyyy').format(code.createdAt.toLocal());
    final scanned = code.lastScannedAt == null
        ? 'never'
        : DateFormat('MMM d, yyyy').format(code.lastScannedAt!.toLocal());
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 18, color: _green),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Active · created $created',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: _green)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Last scanned: $scanned',
            style: const TextStyle(fontSize: 15, color: _muted)),
      ],
    );
  }

  Widget _notOnThisDevice() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Your QR isn\'t saved on this device'),
            const SizedBox(height: 8),
            _body('For your safety, a code is shown only once, on the device '
                'that made it. Make a new code to see it here. Your current '
                'code will stop working.'),
            const SizedBox(height: 8),
            _status(),
            const SizedBox(height: 16),
            _primaryButton(
              label: _making ? 'Making a new code…' : 'Make a new code',
              icon: Icons.qr_code_2,
              onPressed: _making || _turningOff ? null : _makeNewCode,
            ),
            const SizedBox(height: 4),
            _turnOffButton(),
          ],
        ),
      );

  Widget _noCodeYet() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('You don\'t have an emergency QR yet'),
            const SizedBox(height: 8),
            _body('Make a QR code that a responder can scan with any phone '
                'camera to see the information you choose to share.'),
            const SizedBox(height: 16),
            _primaryButton(
              label: _making ? 'Making your code…' : 'Create my emergency QR',
              icon: Icons.qr_code_2,
              onPressed: _making ? null : _makeNewCode,
            ),
          ],
        ),
      );

  // ---------- What a scan shows ----------

  Widget _whatAScanShows(PassportView view) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text('WHAT A SCAN SHOWS',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _muted,
                      letterSpacing: 0.5)),
            ),
            const SizedBox(height: 4),
            _row('Name and age', 'Always shown', true),
            for (final f in PassportField.values)
              _row(f.label, view.isShared(f) ? 'Shown' : 'Hidden',
                  view.isShared(f)),
            if (widget.onChangeSharing != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: widget.onChangeSharing,
                  child: const Text('Change what\'s shared',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _row(String label, String value, bool shown) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(label,
                    style: const TextStyle(fontSize: 16, color: _text)),
              ),
              // DEF-EMG-13: wraps at large text sizes instead of pushing the
              // row off screen.
              Flexible(
                flex: 2,
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: shown ? _green : _muted)),
              ),
            ],
          ),
        ),
      );

  // ---------- Problems ----------

  Widget _errorView(PassportError error) {
    final (title, message, retry) = switch (error) {
      PassportError.network => (
          'We couldn\'t load your emergency QR',
          'Check your internet connection, then try again.',
          true
        ),
      PassportError.signedOut => (
          'Please sign in again',
          'Your session has ended. Sign in to see your emergency QR.',
          false
        ),
      PassportError.notPatient => (
          'Only for patients',
          'The emergency QR is available to patient accounts only.',
          false
        ),
      PassportError.server => (
          'Something went wrong',
          'We couldn\'t load your emergency QR. Please try again.',
          true
        ),
    };
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(liveRegion: true, child: _title(title)),
          const SizedBox(height: 8),
          _body(message),
          const SizedBox(height: 16),
          if (retry)
            _secondaryButton(label: 'Try again', onPressed: _load)
          else if (error == PassportError.signedOut)
            _secondaryButton(
                label: 'Sign in', onPressed: () => context.go('/login')),
        ],
      ),
    );
  }

  // ---------- Shared pieces ----------

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) =>
      // DEF-EMG-13: a minimum, not a fixed, height, so a label that wraps at
      // large text sizes is not cut off.
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      );

  /// A quieter, red action: turning the code off can't be undone (a new code
  /// is a different code). Red B91C1C on white is 6.5:1.
  Widget _turnOffButton() => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
          onPressed: _making || _turningOff ? null : _turnOff,
          child: Text(_turningOff ? 'Turning off…' : 'Turn off QR code',
              style: const TextStyle(fontSize: 16)),
        ),
      );

  Widget _secondaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) =>
      // DEF-EMG-13: as for the primary button.
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _teal,
            side: const BorderSide(color: _teal),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onPressed,
          child: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      );

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  // DEF-EMG-14: a card's title is a heading for screen readers, as it is on
  // screen.
  Widget _title(String text) => Semantics(
        header: true,
        child: Text(text,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: _text)),
      );

  Widget _body(String text) => Text(text,
      style: const TextStyle(fontSize: 16, height: 1.4, color: _muted));
}
