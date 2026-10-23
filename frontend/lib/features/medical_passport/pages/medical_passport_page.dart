import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme/app_theme.dart';
import '../../emergency_passport/services/qr_code_store.dart';
import '../models/medical_passport.dart';
import '../services/medical_passport_service.dart';

/// Route /medical-passport: the patient's own Emergency Care Passport (CC-12,
/// design screen 1).
///
/// The patient sees everything on file and chooses, section by section, what a
/// scan of their QR code shows. Allergies and medications are read from their
/// existing records; blood type, conditions and the emergency contact are
/// edited here.
class MedicalPassportPage extends StatefulWidget {
  const MedicalPassportPage({super.key, this.store});

  /// The copy of the QR code kept on this device (screen 2's). Tests pass one.
  final QrCodeStore? store;

  @override
  State<MedicalPassportPage> createState() => _MedicalPassportPageState();
}

const _ink = Color(0xFF0F172A);
// DEF-EMG-20: 0xFF64748B was 4.35:1 on the page grey; this is at least 5.1:1
// on every background the page puts muted text on.
const _muted = Color(0xFF526277);
const _brand = Color(0xFF0D6B5E);
const _brandSoft = Color(0xFFE6F4F1);
const _page = Color(0xFFF3F5F4);
const _border = Color(0xFFE2E8F0);
const _danger = Color(0xFFB42318);
const _dangerSoft = Color(0xFFFEF3F2);
const _warn = Color(0xFF93370D);
const _warnSoft = Color(0xFFFFFAEB);

/// Two columns from this width; one below it.
const wideLayoutBreakpoint = 900.0;

final _linkTheme = TextButtonThemeData(
  style: TextButton.styleFrom(foregroundColor: _brand, minimumSize: const Size(0, 44)),
);

class _MedicalPassportPageState extends State<MedicalPassportPage> {
  MedicalPassport? _passport;
  Object? _loadError;
  bool _loading = true;
  bool _codeBusy = false;
  final Set<PassportField> _saving = {};
  late final QrCodeStore _store = widget.store ?? QrCodeStore();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// Reloads: a full-page spinner only until the first passport arrives.
  Future<void> _load() async {
    setState(() {
      _loading = _passport == null;
      _loadError = null;
    });
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final passport = await MedicalPassportService.fetch();
      if (mounted) setState(() => _passport = passport);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
      // DEF-EMG-15: with a passport already on screen the error state is not
      // shown, so say the refresh failed.
      if (_passport != null) _toast('Couldn\'t refresh your passport. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setShared(PassportField field, bool shared) async {
    setState(() => _saving.add(field));
    try {
      final passport = await MedicalPassportService.setShared(field, shared);
      if (mounted) setState(() => _passport = passport);
    } catch (e) {
      _toast(_messageFor(e, 'Couldn\'t change what\'s shared. Try again.'));
    } finally {
      if (mounted) setState(() => _saving.remove(field));
    }
  }

  Future<void> _editDetails() async {
    final passport = _passport;
    if (passport == null) return;
    final update = await showDialog<PassportProfileUpdate>(
      context: context,
      builder: (context) => _branded(
          context, _EditDetailsDialog(initial: PassportProfileUpdate.from(passport))),
    );
    if (update == null || !mounted) return;
    try {
      final saved = await MedicalPassportService.updateProfile(update);
      if (mounted) setState(() => _passport = saved);
      _toast('Passport details saved.');
    } catch (e) {
      _toast(_messageFor(e, 'Couldn\'t save your details. Try again.'));
    }
  }

  /// Opens the patient's emergency QR (/emergency-qr, design screen 2), which
  /// makes, keeps, shows and turns off the code. Back here, reload: the code
  /// may have been made or turned off there.
  Future<void> _openQr() async {
    if (_codeBusy) return;
    setState(() => _codeBusy = true);
    try {
      await context.push('/emergency-qr');
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _codeBusy = false);
    }
  }

  Future<void> _turnOffCode() async {
    final off = await _confirm(
      title: 'Turn off your QR code?',
      // DEF-EMG-28: a scan of a turned-off code shows screen 4, "This code
      // isn't active", not nothing. Same words as screen 2's dialog.
      body: 'Anyone who scans it will see "This code isn\'t active". A saved '
          'picture or lock screen stops working too. You can make a new code '
          'at any time.',
      action: 'Turn off',
    );
    if (!off) return;
    setState(() => _codeBusy = true);
    try {
      await MedicalPassportService.revokeCode();
      // DEF-EMG-27: forget the copy kept on this device, as screen 2's Turn off
      // does, so a turned-off link isn't left in storage.
      await _store.clear();
      await _load();
      _toast('QR code turned off.');
    } catch (e) {
      _toast(_messageFor(e, 'Couldn\'t turn off the QR code. Try again.'));
    } finally {
      if (mounted) setState(() => _codeBusy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _branded(
        context,
        AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  /// Dialogs are built from the app's theme, not the page's: give them the
  /// passport's green for links, focus and selection too.
  ///
  /// DEF-EMG-20: the page is light in every app theme, so its dialogs are too;
  /// on the dark dialog surface its green "Cancel" was 2.69:1 and its muted text
  /// 2.77:1.
  static Widget _branded(BuildContext context, Widget dialog) {
    final current = Theme.of(context);
    final theme = current.brightness == Brightness.dark ? AppTheme.lightTheme : current;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: _brand),
        textButtonTheme: _linkTheme,
      ),
      child: dialog,
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _messageFor(Object error, String fallback) =>
      error is MedicalPassportException && error.statusCode == 400 && error.message != null
          ? error.message!
          : fallback;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      // No title: the page's own heading says "Medical passport".
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
      ),
      // Text buttons and switches in the passport's green, not the app's default.
      body: Theme(
        data: Theme.of(context).copyWith(textButtonTheme: _linkTheme),
        child: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading your passport'),
      );
    }
    final passport = _passport;
    if (passport == null) {
      final error = _loadError;
      if (error is MedicalPassportException && error.notAPatient) {
        return const _Notice(
          icon: Icons.badge_outlined,
          text: 'Only patients have a medical passport.',
        );
      }
      if (error is MedicalPassportException && error.signedOut) {
        // DEF-EMG-17: a way out, not a dead end.
        return _Notice(
          icon: Icons.lock_outline,
          text: 'Your session has ended. Sign in again to see your passport.',
          action: 'Sign in',
          onAction: () => context.go('/login'),
        );
      }
      return _Notice(
        icon: Icons.cloud_off_outlined,
        text: 'Couldn\'t load your passport.',
        action: 'Try again',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: _content(passport),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(MedicalPassport p) {
    final left = [
      _MedicationsCard(
        passport: p,
        saving: _saving.contains(PassportField.medications),
        onShare: (v) => _setShared(PassportField.medications, v),
      ),
      _AllergiesCard(
        passport: p,
        saving: _saving.contains(PassportField.allergies),
        onShare: (v) => _setShared(PassportField.allergies, v),
      ),
      _ConditionsCard(
        passport: p,
        saving: _saving.contains(PassportField.chronicConditions),
        onShare: (v) => _setShared(PassportField.chronicConditions, v),
        onEdit: _editDetails,
      ),
    ];
    final right = [
      _ContactCard(
        passport: p,
        saving: _saving.contains(PassportField.emergencyContact),
        onShare: (v) => _setShared(PassportField.emergencyContact, v),
        onEdit: _editDetails,
      ),
      _EmergencyCard(
        passport: p,
        busy: _codeBusy,
        onOpenQr: _openQr,
        onTurnOff: _turnOffCode,
      ),
      const _PrivacyNote(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(passport: p, busy: _codeBusy, onOpenQr: _openQr),
        const SizedBox(height: 20),
        _IdentityCard(
          passport: p,
          saving: _saving.contains(PassportField.bloodType),
          onShareBloodType: (v) => _setShared(PassportField.bloodType, v),
          onEdit: _editDetails,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < wideLayoutBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _spaced([...left, ...right]),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _spaced(left),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _spaced(right),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  static List<Widget> _spaced(List<Widget> children) => [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          children[i],
        ],
      ];
}

/// "Jul 1, 2026" in the device's locale and time zone.
String formatPassportDate(DateTime when) => DateFormat.yMMMd().format(when.toLocal());

// ---- Header and identity ---------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.passport, required this.busy, required this.onOpenQr});

  final MedicalPassport passport;
  final bool busy;
  final VoidCallback onOpenQr;

  @override
  Widget build(BuildContext context) {
    final updated = passport.lastUpdated;
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PRIVATE & SECURE',
                style: TextStyle(
                    color: _brand, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              Semantics(
                header: true,
                child: const Text(
                  'Medical passport',
                  style: TextStyle(color: _ink, fontSize: 30, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Keep your essential health information ready for the moments that matter.',
                style: TextStyle(color: _muted, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                updated == null
                    ? 'Nothing added yet'
                    : 'Last updated ${formatPassportDate(updated)}',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _brand,
            // DEF-EMG-20: the app theme's onPrimary is near-black (3.03:1 here).
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          onPressed: busy ? null : onOpenQr,
          icon: const Icon(Icons.qr_code_2),
          label: Text(passport.hasCode ? 'Show emergency QR' : 'Create emergency QR'),
        ),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.passport,
    required this.saving,
    required this.onShareBloodType,
    required this.onEdit,
  });

  final MedicalPassport passport;
  final bool saving;
  final ValueChanged<bool> onShareBloodType;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (passport.age != null) 'Age ${passport.age}',
      'Blood type ${passport.bloodType?.label ?? 'not set'}',
    ];
    final person = Row(
      children: [
        _Avatar(initials: passport.initials, size: 52),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(passport.name,
                  style: const TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(details.join('  ·  '), style: const TextStyle(color: _muted, fontSize: 14)),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  _ShareSwitch(
                    key: shareSwitchKey(PassportField.bloodType),
                    label: 'blood type',
                    subject: 'Blood type',
                    shared: passport.isShared(PassportField.bloodType),
                    saving: saving,
                    // DEF-EMG-18: a stored "shared" can always be turned off.
                    enabled: passport.bloodType != null ||
                        passport.isShared(PassportField.bloodType),
                    onChanged: onShareBloodType,
                  ),
                  TextButton(onPressed: onEdit, child: const Text('Edit details')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    return _Panel(
      child: LayoutBuilder(builder: (context, constraints) {
        final status = _StatusPanel(passport: passport);
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Padding(padding: const EdgeInsets.all(20), child: person), status],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Padding(padding: const EdgeInsets.all(20), child: person)),
              SizedBox(width: 200, child: status),
            ],
          ),
        );
      }),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.passport});

  final MedicalPassport passport;

  @override
  Widget build(BuildContext context) {
    final ready = passport.ready;
    final hint = ready
        ? null
        : !passport.hasCode
            ? 'Create your QR code'
            : 'Share at least one section';
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(20),
      child: Semantics(
        container: true,
        label: 'Passport status: ${ready ? 'ready to share' : 'not ready. $hint'}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('PASSPORT STATUS',
                style: TextStyle(
                    color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: ready ? _brand : _warn),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(ready ? 'Ready to share' : 'Not ready',
                      style: TextStyle(
                          color: ready ? _brand : _warn, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: const TextStyle(color: _muted, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Section cards ---------------------------------------------------------

class _MedicationsCard extends StatelessWidget {
  const _MedicationsCard({required this.passport, required this.saving, required this.onShare});

  final MedicalPassport passport;
  final bool saving;
  final ValueChanged<bool> onShare;

  @override
  Widget build(BuildContext context) {
    final meds = passport.medications;
    return _SectionCard(
      icon: Icons.medication_outlined,
      title: 'Medications',
      count: meds.length,
      field: PassportField.medications,
      passport: passport,
      saving: saving,
      onShare: onShare,
      empty: 'No active medications on file. Add them in your medication list.',
      children: [
        for (final m in meds)
          _Row(
            icon: Icons.medication_outlined,
            title: [m.name, if (m.dosage case final d?) d].join(' '),
            subtitle: m.frequency,
            badge: const _Badge(text: 'Active', color: _brand, background: _brandSoft),
          ),
      ],
    );
  }
}

class _AllergiesCard extends StatelessWidget {
  const _AllergiesCard({required this.passport, required this.saving, required this.onShare});

  final MedicalPassport passport;
  final bool saving;
  final ValueChanged<bool> onShare;

  @override
  Widget build(BuildContext context) {
    final allergies = passport.allergies;
    return _SectionCard(
      icon: Icons.warning_amber_rounded,
      title: 'Allergies',
      count: allergies.length,
      field: PassportField.allergies,
      passport: passport,
      saving: saving,
      onShare: onShare,
      empty: 'No active allergies on file. Add them in your allergy list.',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          // Two to a row when each still gets 200 px, as in the design; else one.
          child: LayoutBuilder(builder: (context, constraints) {
            const gap = 12.0;
            final twoUp = constraints.maxWidth >= 2 * 200 + gap;
            final width = twoUp ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final a in allergies) SizedBox(width: width, child: _AllergyTile(allergy: a)),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _AllergyTile extends StatelessWidget {
  const _AllergyTile({required this.allergy});

  final PassportAllergy allergy;

  @override
  Widget build(BuildContext context) {
    final severity = severityLabel(allergy.severity);
    final serious = allergy.severity == 'SEVERE' || allergy.severity == 'LIFE_THREATENING';
    return IntrinsicHeight(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: serious ? _dangerSoft : Colors.white,
          border: Border.all(color: serious ? const Color(0xFFFECDCA) : _border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(allergy.allergen,
                      style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                ),
                if (severity != null)
                  _Badge(
                    text: severity.toUpperCase(),
                    color: serious ? _danger : _warn,
                    background: serious ? const Color(0xFFFEE4E2) : _warnSoft,
                  ),
              ],
            ),
            if (allergy.reaction case final reaction?) ...[
              const SizedBox(height: 6),
              Text('Reaction: $reaction', style: const TextStyle(color: _muted, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Life-threatening" for LIFE_THREATENING; null when no severity is recorded.
String? severityLabel(String? severity) => switch (severity) {
      'MILD' => 'Mild',
      'MODERATE' => 'Moderate',
      'SEVERE' => 'Severe',
      'LIFE_THREATENING' => 'Life-threatening',
      _ => null,
    };

class _ConditionsCard extends StatelessWidget {
  const _ConditionsCard({
    required this.passport,
    required this.saving,
    required this.onShare,
    required this.onEdit,
  });

  final MedicalPassport passport;
  final bool saving;
  final ValueChanged<bool> onShare;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final conditions = passport.chronicConditions;
    return _SectionCard(
      icon: Icons.monitor_heart_outlined,
      title: 'Conditions',
      field: PassportField.chronicConditions,
      passport: passport,
      saving: saving,
      onShare: onShare,
      action: TextButton(onPressed: onEdit, child: const Text('Edit')),
      empty: 'No conditions added. Add any a responder should know about.',
      children: [
        if (conditions != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(conditions, style: const TextStyle(color: _ink, height: 1.45)),
          ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.passport,
    required this.saving,
    required this.onShare,
    required this.onEdit,
  });

  final MedicalPassport passport;
  final bool saving;
  final ValueChanged<bool> onShare;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final contact = passport.emergencyContact;
    final phone = contact?.phone;
    return _SectionCard(
      icon: Icons.phone_outlined,
      title: 'Emergency contact',
      field: PassportField.emergencyContact,
      passport: passport,
      saving: saving,
      onShare: onShare,
      action: TextButton(onPressed: onEdit, child: const Text('Edit')),
      empty: 'No emergency contact added.',
      children: [
        if (contact != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Avatar(initials: initialsOf(contact.name), size: 40, warm: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contact.name ?? 'Name not added',
                              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                          if (contact.relationship case final r?)
                            Text(r, style: const TextStyle(color: _muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (phone != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      alignment: Alignment.centerLeft,
                      foregroundColor: _ink,
                      side: const BorderSide(color: _border),
                    ),
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                    icon: const Icon(Icons.phone_outlined, size: 18),
                    label: Text(phone, semanticsLabel: 'Call $phone'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A white card with a header (icon, title, count, share switch) and rows.
/// With no rows it shows [empty] and the switch is off: there is nothing to
/// share yet.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.field,
    required this.passport,
    required this.saving,
    required this.onShare,
    required this.empty,
    required this.children,
    this.count,
    this.action,
  });

  final IconData icon;
  final String title;
  final PassportField field;
  final MedicalPassport passport;
  final bool saving;
  final ValueChanged<bool> onShare;
  final String empty;
  final List<Widget> children;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final hasContent = children.isNotEmpty && (count == null || count! > 0);
    final updated = passport.lastUpdatedBySection[field];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: _brand),
                    const SizedBox(width: 10),
                    // DEF-EMG-21: the title and the switch wrap rather than run off
                    // the card at 200% text.
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(title,
                            style: const TextStyle(
                                color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      _Badge(text: '$count', color: _muted, background: const Color(0xFFF1F5F9)),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (action != null) action!,
                    Flexible(
                      child: _ShareSwitch(
                        key: shareSwitchKey(field),
                        label: title.toLowerCase(),
                        shared: passport.isShared(field),
                        saving: saving,
                        // DEF-EMG-18: a stored "shared" can always be turned off.
                        enabled: hasContent || passport.isShared(field),
                        onChanged: onShare,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          if (hasContent) ...children
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(empty, style: const TextStyle(color: _muted)),
            ),
          if (hasContent && updated != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Updated ${formatPassportDate(updated)}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// The share switch for [field], for tests and automation.
Key shareSwitchKey(PassportField field) => ValueKey('share-${field.apiName}');

/// "Shared on QR" / "Hidden" with a switch. Disabled while saving, and when the
/// section is empty and not shared. DEF-EMG-18: an empty section the patient
/// shared earlier still reads "Shared on QR" (the backend keeps the choice, counts
/// it for "Ready to share", and shows the section on a scan as soon as it has
/// content again), so the patient can see that and turn it off.
class _ShareSwitch extends StatelessWidget {
  const _ShareSwitch({
    super.key,
    required this.label,
    required this.shared,
    required this.saving,
    required this.enabled,
    required this.onChanged,
    this.subject,
  });

  final String label;

  /// Named in the visible text when the switch isn't in its section's header,
  /// e.g. "Blood type shared on QR".
  final String? subject;
  final bool shared;
  final bool saving;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = shared;
    final canChange = enabled && !saving;
    return Semantics(
      label: 'Show $label on QR code',
      toggled: on,
      enabled: canChange,
      // DEF-EMG-19: excludeSemantics drops the Switch's own tap action, so give
      // this node one; without it TalkBack and VoiceOver cannot toggle it.
      onTap: canChange ? () => onChanged(!on) : null,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
                subject == null
                    ? (on ? 'Shared on QR' : 'Hidden')
                    : '$subject ${on ? 'shared on QR' : 'hidden'}',
                style: TextStyle(
                    color: on ? _brand : _muted, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Switch(
            value: on,
            activeTrackColor: _brand,
            onChanged: canChange ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.badge});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: _brandSoft, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: _brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                if (subtitle case final s?) ...[
                  const SizedBox(height: 2),
                  Text(s, style: const TextStyle(color: _muted, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (badge != null) badge!,
        ],
      ),
    );
  }
}

// ---- The QR code -----------------------------------------------------------

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({
    required this.passport,
    required this.busy,
    required this.onOpenQr,
    required this.onTurnOff,
  });

  final MedicalPassport passport;
  final bool busy;
  final VoidCallback onOpenQr;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final code = passport.code;
    final scanned = code?.lastScannedAt;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.qr_code_2, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 12),
          Text(passport.ready ? 'Ready in an emergency' : 'Get ready for an emergency',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Your QR code gives first responders quick access to the details you choose to share.',
            style: TextStyle(color: Colors.white, height: 1.45),
          ),
          if (code != null) ...[
            const SizedBox(height: 8),
            Text(
              scanned == null
                  ? 'Code active. Not scanned yet.'
                  : 'Code active. Last scanned ${formatPassportDate(scanned)}.',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _brand,
              minimumSize: const Size(0, 48),
            ),
            onPressed: busy ? null : onOpenQr,
            child: Text(code == null ? 'Create QR passport' : 'Open emergency QR'),
          ),
          if (code != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
              onPressed: busy ? null : onTurnOff,
              child: const Text('Turn off QR code'),
            ),
        ],
      ),
    );
  }
}

// ---- Editing ----------------------------------------------------------------

class _EditDetailsDialog extends StatefulWidget {
  const _EditDetailsDialog({required this.initial});

  final PassportProfileUpdate initial;

  @override
  State<_EditDetailsDialog> createState() => _EditDetailsDialogState();
}

class _EditDetailsDialogState extends State<_EditDetailsDialog> {
  late BloodType? _bloodType = widget.initial.bloodType;
  late final _conditions = TextEditingController(text: widget.initial.chronicConditions);
  late final _name = TextEditingController(text: widget.initial.contactName);
  late final _relationship = TextEditingController(text: widget.initial.contactRelationship);
  late final _phone = TextEditingController(text: widget.initial.contactPhone);

  @override
  void dispose() {
    _conditions.dispose();
    _name.dispose();
    _relationship.dispose();
    _phone.dispose();
    super.dispose();
  }

  static String? _clean(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit passport details'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<BloodType?>(
                initialValue: _bloodType,
                decoration: const InputDecoration(labelText: 'Blood type'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (final t in BloodType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _bloodType = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _conditions,
                decoration: const InputDecoration(labelText: 'Conditions'),
                maxLength: PassportProfileUpdate.maxChronicConditions,
                minLines: 2,
                maxLines: 5,
              ),
              const SizedBox(height: 4),
              const Text('Emergency contact', style: TextStyle(fontWeight: FontWeight.w700)),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                maxLength: PassportProfileUpdate.maxContactName,
              ),
              TextField(
                controller: _relationship,
                decoration: const InputDecoration(labelText: 'Relationship'),
                maxLength: PassportProfileUpdate.maxContactRelationship,
              ),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                maxLength: PassportProfileUpdate.maxContactPhone,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(
            context,
            PassportProfileUpdate(
              bloodType: _bloodType,
              chronicConditions: _clean(_conditions),
              contactName: _clean(_name),
              contactRelationship: _clean(_relationship),
              contactPhone: _clean(_phone),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---- Small pieces -----------------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.size, this.warm = false});

  final String initials;
  final double size;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: warm ? const Color(0xFFFEF0C7) : _brandSoft,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        // DEF-EMG-21: decorative, in a fixed box, so it shrinks to fit at large text.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(initials,
              style: TextStyle(
                  color: warm ? _warn : _brand, fontWeight: FontWeight.w700, fontSize: size / 3)),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.background});

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
        children: [
          TextSpan(text: 'Privacy note: ', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(
            text: 'A scan shows your name, age and only the sections marked '
                '"Shared on QR". No account details are shared.',
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action, this.onAction});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: _muted),
            const SizedBox(height: 12),
            // DEF-EMG-22: it replaces the spinner without moving focus, so tell a
            // screen reader.
            Semantics(
              liveRegion: true,
              child: Text(text,
                  textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 16)),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white),
                onPressed: onAction,
                child: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
