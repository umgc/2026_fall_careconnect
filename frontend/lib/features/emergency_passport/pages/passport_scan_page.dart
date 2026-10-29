import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/public_passport.dart';
import '../services/passport_scan_service.dart';

/// The public page a phone camera opens after scanning a patient's emergency
/// QR code (CC-12, design screens 3 and 4). No sign-in. Loads once and never
/// refreshes by itself, because the scan endpoint is rate limited.
class PassportScanPage extends StatefulWidget {
  const PassportScanPage({
    super.key,
    required this.token,
    this.service,
    this.launcher,
  });

  final String token;
  final PassportScanService? service;

  /// Opens a tel: link. Replaced in tests.
  final Future<bool> Function(Uri uri)? launcher;

  @override
  State<PassportScanPage> createState() => _PassportScanPageState();
}

class _PassportScanPageState extends State<PassportScanPage> {
  static const _red = Color(0xFFB91C1C);
  static const _redTint = Color(0xFFFEF2F2);
  static const _slate = Color(0xFF1F2937);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF374151);
  static const _border = Color(0xFFD1D5DB);
  static const _page = Color(0xFFF3F4F6);

  late final PassportScanService _service =
      widget.service ?? PassportScanService();
  ScanResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Opening another code while this page is showing (a new link in the same
  // tab) reuses this page, so load again for the new code.
  @override
  void didUpdateWidget(covariant PassportScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = widget.token;
    final result = await _service.scan(token);
    // Ignore an answer for a code that is no longer on screen.
    if (!mounted || token != widget.token) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _call(String number) async {
    final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: digits);
    try {
      final launcher = widget.launcher;
      if (launcher != null) {
        await launcher(uri);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {
      // No phone app (a desktop browser). The number is still on screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final emergencyHeader = !_loading && result is ScanShown;
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            _header(emergencyHeader ? _red : _slate),
            Expanded(
              child: _loading
                  ? Center(
                      child: Semantics(
                        label: 'Loading emergency information',
                        liveRegion: true,
                        child: const CircularProgressIndicator(),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: switch (result) {
                            ScanShown(:final passport) => _shown(passport),
                            ScanNotActive() => _notActive(),
                            ScanRateLimited() => _problem(
                                'Too many tries',
                                'Please wait a minute, then press Try again.',
                              ),
                            _ => _problem(
                                'We couldn\'t load this information',
                                'Check the internet connection, then press Try again.',
                              ),
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Color color) => Semantics(
        header: true,
        child: Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: const Row(
            children: [
              Icon(Icons.medical_services, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'EMERGENCY MEDICAL INFORMATION',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // ---------- Screen 3: the shared information ----------

  Widget _shown(PublicPassport p) {
    final children = <Widget>[_identity(p)];
    final allergies = p.allergies ?? const <PassportAllergy>[];
    final medications = p.medications ?? const <PassportMedication>[];

    if (allergies.isNotEmpty) {
      children.add(_section(
        title: 'ALLERGIES',
        icon: Icons.warning_amber_rounded,
        accent: _red,
        background: _redTint,
        children: [for (final a in allergies) _allergy(a)],
      ));
    }
    if (medications.isNotEmpty) {
      children.add(_section(
        title: 'CURRENT MEDICATIONS',
        icon: Icons.medication_outlined,
        children: [for (final m in medications) _medication(m)],
      ));
    }
    if (p.chronicConditions != null) {
      children.add(_section(
        title: 'CHRONIC CONDITIONS',
        icon: Icons.monitor_heart_outlined,
        children: [_body(p.chronicConditions!)],
      ));
    }
    if (p.emergencyContact != null) {
      children.add(_contact(p.emergencyContact!));
    }
    if (p.sharesNothing) {
      children.add(_card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('No information shared'),
            const SizedBox(height: 6),
            _body('This person hasn\'t shared any medical information.'),
          ],
        ),
      ));
      children.add(_call911Card());
    }

    children.add(_footer(p.lastUpdated));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _identity(PublicPassport p) {
    final blood = p.bloodType;
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, color: _text),
                ),
                if (p.age != null) ...[
                  const SizedBox(height: 4),
                  _body('Age ${p.age}'),
                ],
              ],
            ),
          ),
          if (blood != null)
            Semantics(
              label: 'Blood type ${bloodTypeSpoken(blood)}',
              excludeSemantics: true,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _text,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text('BLOOD TYPE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                    Text(bloodTypeLabel(blood),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _allergy(PassportAllergy a) {
    final severity = severityLabel(a.severity);
    final serious = a.severity == 'SEVERE' || a.severity == 'LIFE_THREATENING';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // DEF-EMG-10: at large text sizes the badge wraps inside its share of
      // the row instead of pushing the row off screen.
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.allergen,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _text)),
                  if (a.reaction != null) _body('Reaction: ${a.reaction}'),
                ],
              ),
            ),
            if (severity != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: serious ? _red : Colors.white,
                    border: Border.all(color: serious ? _red : _muted),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    severity,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: serious ? Colors.white : _text,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _medication(PassportMedication m) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [m.name, if (m.dosage != null) m.dosage].join(' '),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: _text),
            ),
            if (m.frequency != null) _body(m.frequency!),
          ],
        ),
      );

  Widget _contact(PassportContact c) {
    final phone = c.phone;
    return _section(
      title: 'EMERGENCY CONTACT',
      icon: Icons.contact_phone_outlined,
      children: [
        if (c.name != null)
          Text(c.name!,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: _text)),
        if (c.relationship != null) _body(c.relationship!),
        if (phone != null) ...[
          const SizedBox(height: 12),
          _bigButton(
            label: 'Call $phone',
            semanticsLabel: 'Call ${c.name ?? 'emergency contact'} at $phone',
            color: const Color(0xFF047857),
            icon: Icons.call,
            onPressed: () => _call(phone),
          ),
        ],
      ],
    );
  }

  Widget _footer(DateTime? lastUpdated) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lastUpdated != null)
              Text(
                'Last updated ${DateFormat('MMM d, yyyy').format(lastUpdated.toLocal())}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: _text),
              ),
            const SizedBox(height: 6),
            _body('Shared by this person. They chose what to show, and some '
                'details are entered by them. This is not a full medical record.'),
          ],
        ),
      );

  // ---------- Screen 4: the code isn't active ----------

  Widget _notActive() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Icon(Icons.block, size: 32, color: _muted),
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: _title('This code isn\'t active'),
                ),
                const SizedBox(height: 8),
                _body('The owner may have replaced it with a new one. No '
                    'medical information is available from this code.'),
              ],
            ),
          ),
          _call911Card(),
        ],
      );

  // ---------- Too many tries / couldn't load ----------

  Widget _problem(String title, String message) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(liveRegion: true, child: _title(title)),
                const SizedBox(height: 8),
                _body(message),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    // DEF-EMG-09: the theme's cyan text was 2.85:1 on white.
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _muted),
                    ),
                    onPressed: _load,
                    child:
                        const Text('Try again', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
          _call911Card(),
        ],
      );

  // ---------- Shared pieces ----------

  Widget _call911Card() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('IF THIS IS AN EMERGENCY',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 10),
            _bigButton(
              label: 'Call 911',
              color: _red,
              icon: Icons.call,
              onPressed: () => _call('911'),
            ),
            const SizedBox(height: 10),
            _body('Check for a medical ID bracelet, a wallet card or the '
                'phone\'s built-in medical ID.'),
          ],
        ),
      );

  Widget _bigButton({
    required String label,
    String? semanticsLabel,
    required Color color,
    required IconData icon,
    required VoidCallback onPressed,
  }) =>
      Semantics(
        button: true,
        label: semanticsLabel ?? label,
        onTap: onPressed,
        excludeSemantics: true,
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color accent = _muted,
    Color background = Colors.white,
  }) =>
      _card(
        background: background,
        borderColor: accent == _muted ? _border : accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 6),
                  // DEF-EMG-10: wraps at large text sizes instead of overflowing.
                  Flexible(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: 0.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      );

  Widget _card({
    required Widget child,
    Color background = Colors.white,
    Color borderColor = _border,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _title(String text) => Text(text,
      style: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: _text));

  Widget _body(String text) => Text(text,
      style: const TextStyle(fontSize: 16, height: 1.4, color: _muted));
}
