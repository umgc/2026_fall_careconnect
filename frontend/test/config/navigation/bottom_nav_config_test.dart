// Tests for BottomNavItem and BottomNavConfig
// (lib/config/navigation/bottom_nav_config.dart).
//
// Coverage strategy:
//   BottomNavItem is a const data class with an assert and a localizedLabel
//   helper that switches on labelKey.
//   BottomNavConfig provides three static list factories and a role-dispatch
//   method (getNavItemsForRole).
//
//   Branches tested (BottomNavItem.localizedLabel):
//     'nav_home'        → t.navHome
//     'nav_symptoms'    → t.navSymptoms
//     'nav_health'      → t.navHealth
//     'nav_messages'    → t.navMessages
//     'nav_menu'        → t.navMenu
//     'nav_patientList' → t.navPatientList
//     'nav_analytics'   → t.navAnalytics
//     'nav_more'        → t.navMore
//     null / unknown    → falls back to item.label
//
//   Branches tested (BottomNavConfig.getNavItemsForRole):
//     'PATIENT'         → patient items (5 items)
//     'CAREGIVER'       → caregiver items
//     'FAMILY_LINK'     → caregiver items
//     'ADMIN'           → caregiver items
//     unknown role      → defaults to patient items

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/config/navigation/bottom_nav_config.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // English localizations instance used as a stand-in for AppLocalizations.
  // lookupAppLocalizations is a top-level function that requires no context.
  final t = lookupAppLocalizations(const Locale('en'));

  // ─── BottomNavConfig.getNavItemsForRole ───────────────────────────────────

  group('BottomNavConfig.getNavItemsForRole', () {
    test('PATIENT returns 5 nav items', () {
      // Verifies the patient navigation set has the expected item count.
      final items = BottomNavConfig.getNavItemsForRole('PATIENT');
      expect(items.length, 5);
    });

    test('CAREGIVER returns caregiver nav items (6)', () {
      // Verifies the caregiver set has the expected item count.
      final items = BottomNavConfig.getNavItemsForRole('CAREGIVER');
      expect(items.length, 6);
    });

    test('FAMILY_LINK returns the same items as CAREGIVER', () {
      // Verifies FAMILY_LINK shares the caregiver branch.
      final caregiverItems = BottomNavConfig.getNavItemsForRole('CAREGIVER');
      final familyItems = BottomNavConfig.getNavItemsForRole('FAMILY_LINK');
      expect(familyItems.length, caregiverItems.length);
    });

    test('ADMIN returns the same items as CAREGIVER', () {
      // Verifies ADMIN falls into the caregiver branch.
      final caregiverItems = BottomNavConfig.getNavItemsForRole('CAREGIVER');
      final adminItems = BottomNavConfig.getNavItemsForRole('ADMIN');
      expect(adminItems.length, caregiverItems.length);
    });

    test('unknown role defaults to patient items', () {
      // Verifies the fallthrough branch returns patient navigation.
      final unknownItems = BottomNavConfig.getNavItemsForRole('GUEST');
      final patientItems = BottomNavConfig.getNavItemsForRole('PATIENT');
      expect(unknownItems.length, patientItems.length);
    });

    test('role matching is case-insensitive', () {
      // Verifies lowercase 'patient' is treated the same as 'PATIENT'.
      final lower = BottomNavConfig.getNavItemsForRole('patient');
      final upper = BottomNavConfig.getNavItemsForRole('PATIENT');
      expect(lower.length, upper.length);
    });

    test('patient items include a home route', () {
      // Spot-checks that the first patient item is the home route.
      final items = BottomNavConfig.getNavItemsForRole('PATIENT');
      expect(items.any((i) => i.routeName == 'home'), isTrue);
    });

    test('caregiver items include a tasks route', () {
      // Spot-checks that caregiver items contain the patient-list (tasks) route.
      final items = BottomNavConfig.getNavItemsForRole('CAREGIVER');
      expect(items.any((i) => i.routeName == 'tasks'), isTrue);
    });
  });

  // ─── BottomNavItem.localizedLabel ─────────────────────────────────────────

  group('BottomNavItem.localizedLabel', () {
    // Helper: build a minimal BottomNavItem with the given labelKey.
    BottomNavItem item(String label, String? key) => BottomNavItem(
          label: label,
          labelKey: key,
          icon: Icons.circle,
          routeName: 'test',
          screen: const SizedBox.shrink(),
        );

    test('"nav_home" returns t.navHome', () {
      // Verifies the localised label for the home key.
      expect(item('Home', 'nav_home').localizedLabel(t), t.navHome);
    });

    test('"nav_symptoms" returns t.navSymptoms', () {
      expect(item('Symptoms', 'nav_symptoms').localizedLabel(t), t.navSymptoms);
    });

    test('"nav_health" returns t.navHealth', () {
      expect(item('Health', 'nav_health').localizedLabel(t), t.navHealth);
    });

    test('"nav_messages" returns t.navMessages', () {
      expect(
        item('Messages', 'nav_messages').localizedLabel(t),
        t.navMessages,
      );
    });

    test('"nav_menu" returns t.navMenu', () {
      expect(item('Menu', 'nav_menu').localizedLabel(t), t.navMenu);
    });

    test('"nav_patientList" returns t.navPatientList', () {
      expect(
        item('Patient List', 'nav_patientList').localizedLabel(t),
        t.navPatientList,
      );
    });

    test('"nav_analytics" returns t.navAnalytics', () {
      expect(
        item('Analytics', 'nav_analytics').localizedLabel(t),
        t.navAnalytics,
      );
    });

    test('"nav_more" returns t.navMore', () {
      expect(item('More', 'nav_more').localizedLabel(t), t.navMore);
    });

    test('null labelKey falls back to the item label', () {
      // Verifies the default branch returns the raw label string.
      const fallbackLabel = 'Custom Label';
      expect(item(fallbackLabel, null).localizedLabel(t), fallbackLabel);
    });

    test('unknown labelKey falls back to the item label', () {
      // Verifies an unrecognised key also returns the raw label.
      const fallbackLabel = 'Special';
      expect(item(fallbackLabel, 'nav_unknown').localizedLabel(t), fallbackLabel);
    });
  });
}
