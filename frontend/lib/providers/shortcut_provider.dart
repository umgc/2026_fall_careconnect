// lib/providers/shortcut_provider.dart
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your generated localizations to resolve labels at render-time.
import 'package:care_connect_app/l10n/app_localizations.dart';

class ShortcutDef {
  final String key; // unique id for persistence
  final IconData icon;
  final String label; // fallback (English) if labelKey not provided
  final String? labelKey; // optional i18n key (maps to AppLocalizations)
  final String routeTemplate; // supports {userId}, etc.
  final Set<String>? visibleFor; // e.g. {'CAREGIVER','ADMIN','FAMILY_LINK'}
  final bool defaultSelected; // used on first run

  const ShortcutDef({
    required this.key,
    required this.icon,
    required this.label,
    this.labelKey,
    required this.routeTemplate,
    this.visibleFor,
    this.defaultSelected = false,
  });

  bool isVisibleFor(String roleUpper) {
    if (visibleFor == null || visibleFor!.isEmpty) return true;
    return visibleFor!.contains(roleUpper);
  }

  String resolveRoute(Map<String, String> ctx) {
    var r = routeTemplate;
    ctx.forEach((k, v) => r = r.replaceAll('{$k}', v));
    return r;
  }

  // Returns localized label if labelKey is present, otherwise falls back to `label`.
  String localizedLabel(AppLocalizations t) {
    if (labelKey == null) return label;
    switch (labelKey) {
      case 'dashboard':
        return t.shortcut_dashboard;
      case 'invoiceAssistant':
        return t.shortcut_invoices;
      case 'calendarAssistant':
        return t.shortcut_calendar;
      case 'socialFeed':
        return t.shortcut_feed;
      case 'medicationManagement':
        return t.shortcut_meds;
      case 'evv':
        return t.shortcut_evv;
      case 'wearables':
        return t.shortcut_wearables;
      case 'fileManagement':
        return t.shortcut_files;
      case 'gamification':
        return t.shortcut_gamification;
      default:
        return label; // unknown key, use fallback
    }
  }
}

class ShortcutProvider extends ChangeNotifier {
  static const _prefsActiveKey = 'shortcut_active_keys';
  static const int maxShortcuts = 8;

  final Map<String, ShortcutDef> _catalog = <String, ShortcutDef>{};
  final Set<String> _activeKeys = <String>{};

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool get isLoaded => _loaded;

  UnmodifiableListView<ShortcutDef> get catalog =>
      UnmodifiableListView(_catalog.values);
  UnmodifiableListView<String> get activeKeys =>
      UnmodifiableListView(_activeKeys);

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final saved = _prefs!.getStringList(_prefsActiveKey) ?? const <String>[];

    // Always ensure built-ins exist before applying active selection
    _registerBuiltins();

    _activeKeys
      ..clear()
      ..addAll(saved);

    // First run: seed defaults from built-ins
    if (_activeKeys.isEmpty) {
      final defaults = _catalog.values
          .where((d) => d.defaultSelected)
          .map((d) => d.key)
          .take(maxShortcuts)
          .toList();
      if (defaults.isNotEmpty) {
        _activeKeys
          ..clear()
          ..addAll(defaults);
        await _persist();
      }
    }

    _loaded = true;
    notifyListeners();
  }

  // Pages or features can call this to add more shortcuts at runtime
  void registerAll(Iterable<ShortcutDef> defs) {
    for (final d in defs) {
      _catalog[d.key] = d;
    }
    notifyListeners();
  }

  Future<void> toggle(String key) async {
    if (!_catalog.containsKey(key)) return;
    if (_activeKeys.contains(key)) {
      _activeKeys.remove(key);
    } else {
      if (_activeKeys.length >= maxShortcuts) return;
      _activeKeys.add(key);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setAll(Iterable<String> keys) async {
    _activeKeys
      ..clear()
      ..addAll(keys.take(maxShortcuts).where((k) => _catalog.containsKey(k)));
    await _persist();
    notifyListeners();
  }

  List<ShortcutDef> visibleActiveForRole(String roleUpper) {
    return _activeKeys
        .map((k) => _catalog[k])
        .whereType<ShortcutDef>()
        .where((d) => d.isVisibleFor(roleUpper))
        .toList(growable: false);
  }

  List<ShortcutDef> visibleCatalogForRole(String roleUpper) {
    return _catalog.values
        .where((d) => d.isVisibleFor(roleUpper))
        .toList(growable: false);
  }

  bool isActive(String key) => _activeKeys.contains(key);

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_prefsActiveKey, _activeKeys.toList());
  }

  void _registerBuiltins() {
    if (_catalog.isNotEmpty) return; // already registered
    _catalog.addAll({
      'dash': ShortcutDef(
        key: 'dash',
        icon: Icons.dashboard,
        label: 'Dashboard',
        labelKey: 'dashboard',
        routeTemplate: '/dashboard',
        defaultSelected: true,
      ),
      'inv': ShortcutDef(
        key: 'inv',
        icon: Icons.receipt,
        label: 'Invoice Assistant',
        labelKey: 'invoiceAssistant',
        routeTemplate: '/invoice-assistant/dashboard',
        visibleFor: const {'CAREGIVER', 'ADMIN', 'PATIENT'},
        defaultSelected: true,
      ),
      'cal': ShortcutDef(
        key: 'cal',
        icon: Icons.calendar_today,
        label: 'Calendar Assistant',
        labelKey: 'calendarAssistant',
        routeTemplate: '/calendar',
        defaultSelected: true,
      ),
      'feed': ShortcutDef(
        key: 'feed',
        icon: Icons.forum,
        label: 'Social Feed',
        labelKey: 'socialFeed',
        routeTemplate: '/social-feed?userId={userId}',
        defaultSelected: true,
      ),
      'meds': ShortcutDef(
        key: 'meds',
        icon: Icons.medical_information,
        label: 'Medication Management',
        labelKey: 'medicationManagement',
        routeTemplate: '/medication',
        defaultSelected: true,
      ),
      'evv': ShortcutDef(
        key: 'evv',
        icon: Icons.shield,
        label: 'EVV',
        labelKey: 'evv',
        routeTemplate: '/evv',
        visibleFor: const {'CAREGIVER', 'ADMIN'},
        defaultSelected: true,
      ),
      'wear': ShortcutDef(
        key: 'wear',
        icon: Icons.watch,
        label: 'Wearables',
        labelKey: 'wearables',
        routeTemplate: '/wearables',
        defaultSelected: true,
      ),
      'files': ShortcutDef(
        key: 'files',
        icon: Icons.folder,
        label: 'File Management',
        labelKey: 'fileManagement',
        routeTemplate: '/file-management',
        defaultSelected: true,
      ),
      // not selected by default
      'gam': ShortcutDef(
        key: 'gam',
        icon: Icons.emoji_events,
        label: 'Gamification',
        labelKey: 'gamification',
        routeTemplate: '/gamification',
        defaultSelected: false,
      ),
    });
  }
}
