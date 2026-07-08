// Tests for MainScreenConfig
// (lib/config/navigation/main_screen_config.dart).
//
// Coverage strategy:
//   MainScreenConfig is a pure Dart configuration class (no platform channels,
//   no network I/O) with a constructor, copyWith, three static factories, and
//   a getNavItems() method.
//
//   Branches tested:
//     constructor      — all required fields stored; optional fields use defaults
//                        (enablePageAnimation = true, showAppBar = false, etc.).
//     copyWith         — each optional field can be overridden individually;
//                        unchanged fields retain their original values.
//     forPatient       — sets role to 'PATIENT'; patientId/primaryColor stored.
//     forCaregiver     — sets role to 'CAREGIVER'; caregiverId/patientId stored.
//     forFamilyMember  — sets role to 'FAMILY_LINK'.
//     getNavItems      — returns customNavItems when provided; falls back to
//                        BottomNavConfig.getNavItemsForRole when null.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/config/navigation/bottom_nav_config.dart';
import 'package:care_connect_app/config/navigation/main_screen_config.dart';

void main() {
  // getNavItems() instantiates BottomNavItem screens (Flutter widgets), so
  // the Flutter test binding must be initialised.
  TestWidgetsFlutterBinding.ensureInitialized();

  void expectValidNavItems(List<BottomNavItem> items) {
    final invalidLabels = items
        .where((item) => item.label.trim().isEmpty)
        .map((item) => item.routeName)
        .toList();
    final invalidRoutes = items
        .where((item) => item.routeName.trim().isEmpty)
        .map((item) => item.label)
        .toList();
    final missingTargets = items
        .where((item) => item.screen == null && item.onPress == null)
        .map((item) => item.routeName)
        .toList();

    expect(invalidLabels, isEmpty);
    expect(invalidRoutes, isEmpty);
    expect(missingTargets, isEmpty);
  }

  List<String> routeNames(List<BottomNavItem> items) =>
      items.map((item) => item.routeName).toList();

  // ─── Constructor ──────────────────────────────────────────────────────────

  group('MainScreenConfig constructor', () {
    test('stores required fields and applies default values', () {
      // Verifies that every field is accessible and that the documented
      // defaults match expected values.
      const cfg = MainScreenConfig(userRole: 'PATIENT', userId: 42);
      expect(cfg.userRole, 'PATIENT');
      expect(cfg.userId, 42);
      expect(cfg.patientId, isNull);
      expect(cfg.caregiverId, isNull);
      expect(cfg.customNavItems, isNull);
      expect(cfg.primaryColor, isNull);
      expect(cfg.backgroundColor, isNull);
      expect(cfg.enablePageAnimation, isTrue);
      expect(cfg.animationDuration, const Duration(milliseconds: 300));
      expect(cfg.animationCurve, Curves.easeInOut);
      expect(cfg.showAppBar, isFalse);
      expect(cfg.appBarTitle, isNull);
      expect(cfg.appBarActions, isNull);
    });

    test('stores optional fields when explicitly provided', () {
      // Verifies non-default values are stored correctly.
      const cfg = MainScreenConfig(
        userRole: 'ADMIN',
        userId: 1,
        patientId: 10,
        caregiverId: 20,
        enablePageAnimation: false,
        showAppBar: true,
        appBarTitle: 'Admin Dashboard',
        primaryColor: Colors.red,
      );
      expect(cfg.patientId, 10);
      expect(cfg.caregiverId, 20);
      expect(cfg.enablePageAnimation, isFalse);
      expect(cfg.showAppBar, isTrue);
      expect(cfg.appBarTitle, 'Admin Dashboard');
      expect(cfg.primaryColor, Colors.red);
    });
  });

  // ─── copyWith ─────────────────────────────────────────────────────────────

  group('MainScreenConfig.copyWith', () {
    const base = MainScreenConfig(userRole: 'PATIENT', userId: 5);

    test('returns a new instance with overridden fields', () {
      // Verifies that copyWith produces a distinct object with new values.
      final updated = base.copyWith(userRole: 'CAREGIVER', userId: 99);
      expect(updated.userRole, 'CAREGIVER');
      expect(updated.userId, 99);
    });

    test('preserves fields not passed to copyWith', () {
      // Verifies that untouched fields retain their original values.
      final updated = base.copyWith(showAppBar: true);
      expect(updated.userRole, 'PATIENT');
      expect(updated.userId, 5);
      expect(updated.showAppBar, isTrue);
    });

    test('can override patientId', () {
      // Verifies patientId can be set via copyWith.
      final updated = base.copyWith(patientId: 77);
      expect(updated.patientId, 77);
    });

    test('can override animationDuration', () {
      // Verifies custom animation duration survives copyWith.
      final updated = base.copyWith(
        animationDuration: const Duration(milliseconds: 500),
      );
      expect(updated.animationDuration, const Duration(milliseconds: 500));
    });
  });

  // ─── Static factories ─────────────────────────────────────────────────────

  group('MainScreenConfig.forPatient', () {
    test('sets userRole to PATIENT and stores userId', () {
      // Verifies the factory creates the correct role with the given userId.
      final cfg = MainScreenConfig.forPatient(userId: 10);
      expect(cfg.userRole, 'PATIENT');
      expect(cfg.userId, 10);
    });

    test('stores optional patientId and primaryColor', () {
      // Verifies that optional factory parameters are forwarded.
      final cfg = MainScreenConfig.forPatient(
        userId: 10,
        patientId: 55,
        primaryColor: Colors.blue,
      );
      expect(cfg.patientId, 55);
      expect(cfg.primaryColor, Colors.blue);
    });
  });

  group('MainScreenConfig.forCaregiver', () {
    test('sets userRole to CAREGIVER and stores userId', () {
      // Verifies the factory creates the correct role.
      final cfg = MainScreenConfig.forCaregiver(userId: 20);
      expect(cfg.userRole, 'CAREGIVER');
      expect(cfg.userId, 20);
    });

    test('stores optional caregiverId and patientId', () {
      // Verifies both ID fields are forwarded by the factory.
      final cfg = MainScreenConfig.forCaregiver(
        userId: 20,
        caregiverId: 3,
        patientId: 7,
      );
      expect(cfg.caregiverId, 3);
      expect(cfg.patientId, 7);
    });
  });

  group('MainScreenConfig.forFamilyMember', () {
    test('sets userRole to FAMILY_LINK', () {
      // Verifies the family-member factory sets the correct role string.
      final cfg = MainScreenConfig.forFamilyMember(userId: 30);
      expect(cfg.userRole, 'FAMILY_LINK');
      expect(cfg.userId, 30);
    });

    test('stores optional patientId', () {
      // Verifies patientId is forwarded by the factory.
      final cfg = MainScreenConfig.forFamilyMember(userId: 30, patientId: 12);
      expect(cfg.patientId, 12);
    });
  });

  // ─── getNavItems ──────────────────────────────────────────────────────────

  group('MainScreenConfig.getNavItems', () {
    test('returns customNavItems when provided', () {
      // Verifies that a custom list bypasses the role-based default.
      final customItems = BottomNavConfig.getNavItemsForRole('PATIENT');
      final cfg = MainScreenConfig(
        userRole: 'PATIENT',
        userId: 1,
        customNavItems: customItems,
      );
      expect(cfg.getNavItems(), same(customItems));
    });

    test('returns role-based items when customNavItems is null', () {
      // Verifies the fallback to BottomNavConfig for a PATIENT role.
      final cfg = MainScreenConfig.forPatient(userId: 1);
      final items = cfg.getNavItems();
      expect(items, isNotEmpty);
    });

    test('CAREGIVER role returns caregiver nav items', () {
      // Verifies the fallback uses the correct role when null customNavItems.
      final cfg = MainScreenConfig.forCaregiver(userId: 2);
      final items = cfg.getNavItems();
      expect(items, isNotEmpty);
    });

    test('role-based configs build valid navigation entries', () {
      final configs = [
        MainScreenConfig.forPatient(userId: 1),
        MainScreenConfig.forCaregiver(userId: 2),
        MainScreenConfig.forFamilyMember(userId: 3),
        const MainScreenConfig(userRole: 'ADMIN', userId: 4),
      ];

      for (final cfg in configs) {
        final items = cfg.getNavItems();
        expect(items, isNotEmpty);
        expectValidNavItems(items);
      }
    });

    test('shared main screen roles keep caregiver navigation entries stable',
        () {
      final caregiverItems =
          MainScreenConfig.forCaregiver(userId: 1).getNavItems();
      final familyItems =
          MainScreenConfig.forFamilyMember(userId: 2).getNavItems();
      final adminItems =
          const MainScreenConfig(userRole: 'ADMIN', userId: 3).getNavItems();

      expect(routeNames(familyItems), routeNames(caregiverItems));
      expect(routeNames(adminItems), routeNames(caregiverItems));
    });
  });
}
