// lib/navigation/route_registry.dart
// Central catalog for search and navigation.
// Supports both GoRouter routes and direct widget pushes.

import 'package:flutter/material.dart';

// Imports for widgetBuilder entries used below

enum AppRole { PATIENT, CAREGIVER, FAMILY_LINK, ADMIN }

enum NavKind { routePath, routeName, widgetBuilder }

class RouteParam {
  final String key; // query or path param name
  final String label; // prompt text
  final bool isPathParam; // set true if this is a :param in path
  final String? defaultValue;
  const RouteParam({
    required this.key,
    required this.label,
    this.isPathParam = false,
    this.defaultValue,
  });
}

class RouteMeta {
  final String title;
  final String description;
  final List<String> keywords;

  final NavKind kind;
  final String? path; // use when kind == routePath
  final String? routeName; // use when kind == routeName
  final Widget Function(Map<String, String> args)?
      builder; // when kind == widgetBuilder

  final Set<AppRole> roles;
  final List<RouteParam> params;
  final IconData icon;
  final bool launchable; // false when page requires complex extras

  const RouteMeta({
    required this.title,
    required this.description,
    required this.keywords,
    required this.kind,
    this.path,
    this.routeName,
    this.builder,
    required this.roles,
    this.params = const [],
    this.icon = Icons.arrow_forward,
    this.launchable = true,
  });
}

AppRole? toAppRole(String role) {
  switch (role.toUpperCase()) {
    case 'PATIENT':
      return AppRole.PATIENT;
    case 'CAREGIVER':
      return AppRole.CAREGIVER;
    case 'FAMILY_LINK':
      return AppRole.FAMILY_LINK;
    case 'ADMIN':
      return AppRole.ADMIN;
  }
  return null;
}

const Set<AppRole> allRoles = {
  AppRole.PATIENT,
  AppRole.CAREGIVER,
  AppRole.FAMILY_LINK,
  AppRole.ADMIN,
};

const Set<AppRole> staffRoles = {
  AppRole.CAREGIVER,
  AppRole.ADMIN,
};

// IMPORTANT: final (not const) so we can include closures and other non-constant values.
final routeCatalog = <RouteMeta>[
  // Entry point and auth
  RouteMeta(
    title: 'Welcome',
    description: 'Welcome page',
    keywords: ['root', 'start', 'landing'],
    kind: NavKind.routePath,
    path: '/',
    roles: allRoles,
    icon: Icons.home,
  ),

  // Dashboards and role flows
  RouteMeta(
    title: 'Dashboard',
    description: 'Main dashboard',
    keywords: ['home', 'main'],
    kind: NavKind.routePath,
    path: '/dashboard',
    roles: allRoles,
    icon: Icons.dashboard,
  ),
  RouteMeta(
    title: 'Dashboard (Patient direct)',
    description: 'Patient dashboard via path',
    keywords: ['dashboard', 'patient'],
    kind: NavKind.routePath,
    path: '/dashboard/patient',
    roles: {AppRole.PATIENT, AppRole.ADMIN},
    icon: Icons.person,
  ),
  RouteMeta(
    title: 'Dashboard Caregiver',
    description:
        'Caregiver dashboard via path with caregiverId and optional patientId',
    keywords: ['dashboard', 'caregiver'],
    kind: NavKind.routePath,
    path: '/dashboard/caregiver',
    roles: {AppRole.CAREGIVER, AppRole.ADMIN},
    icon: Icons.health_and_safety,
  ),

  RouteMeta(
    title: 'Home',
    description: 'Redirects to dashboard if logged in',
    keywords: ['home'],
    kind: NavKind.routePath,
    path: '/home',
    roles: allRoles,
    icon: Icons.refresh,
  ),

  // Registration flows
  RouteMeta(
    title: 'Register Caregiver',
    description: 'Caregiver registration',
    keywords: ['caregiver', 'register'],
    kind: NavKind.routePath,
    path: '/register/caregiver',
    roles: allRoles,
    icon: Icons.app_registration,
  ),
  RouteMeta(
    title: 'Register Patient',
    description: 'Patient registration',
    keywords: ['patient', 'register'],
    kind: NavKind.routePath,
    path: '/register/patient',
    roles: allRoles,
    icon: Icons.app_registration,
  ),
  RouteMeta(
    title: 'Add Patient',
    description: 'Add a patient',
    keywords: ['patient', 'add'],
    kind: NavKind.routePath,
    path: '/add-patient',
    roles: staffRoles,
    icon: Icons.person_add_alt_1,
  ),

  // Social
  RouteMeta(
    title: 'Social Feed',
    description: 'Main social feed',
    keywords: ['social', 'feed'],
    kind: NavKind.routePath,
    path: '/social-feed',
    roles: allRoles,
    icon: Icons.dynamic_feed,
  ),

  RouteMeta(
    title: 'Subscription',
    description: 'Subscription management',
    keywords: ['subscription', 'billing'],
    kind: NavKind.routePath,
    path: '/subscription',
    roles: allRoles,
    icon: Icons.subscriptions,
  ),

  // Password flows
  RouteMeta(
    title: 'Reset Password',
    description: 'Reset password screen',
    keywords: ['password', 'reset'],
    kind: NavKind.routePath,
    path: '/reset-password',
    roles: allRoles,
    icon: Icons.lock_reset,
  ),

  // Gamification
  RouteMeta(
    title: 'Gamification',
    description: 'Gamification screen',
    keywords: ['game', 'points'],
    kind: NavKind.routePath,
    path: '/gamification',
    roles: allRoles,
    icon: Icons.sports_esports,
  ),

  // Video and calls
  RouteMeta(
    title: 'Video Call',
    description: 'Start an AWS Chime call',
    keywords: ['video', 'call', 'chime'],
    kind: NavKind.routePath,
    path: '/video-call-chime',
    roles: allRoles,
    icon: Icons.video_call,
    launchable: false,
  ),

  // Wearables and integrations
  RouteMeta(
    title: 'Wearables',
    description: 'Wearables screen',
    keywords: ['wearables', 'fitbit', 'devices'],
    kind: NavKind.routePath,
    path: '/wearables',
    roles: allRoles,
    icon: Icons.watch,
  ),
  RouteMeta(
    title: 'Home Monitoring',
    description: 'Home monitoring screen',
    keywords: ['home', 'monitoring'],
    kind: NavKind.routePath,
    path: '/home-monitoring',
    roles: allRoles,
    icon: Icons.sensor_occupied,
  ),
  RouteMeta(
    title: 'Smart Devices',
    description: 'Smart devices page',
    keywords: ['smart', 'devices', 'iot'],
    kind: NavKind.routePath,
    path: '/smart-devices',
    roles: allRoles,
    icon: Icons.devices_other,
  ),
  RouteMeta(
    title: 'Medication Management',
    description: 'Medication management',
    keywords: ['medication', 'rx'],
    kind: NavKind.routePath,
    path: '/medication',
    roles: allRoles,
    icon: Icons.medication,
  ),

  // EVV flows
  RouteMeta(
    title: 'EVV Dashboard',
    description: 'Electronic Visit Verification dashboard',
    keywords: ['evv', 'visit'],
    kind: NavKind.routePath,
    path: '/evv',
    roles: staffRoles,
    icon: Icons.verified,
  ),
  // Profile and settings
  RouteMeta(
    title: 'Profile Settings',
    description: 'Update profile settings',
    keywords: ['profile', 'settings'],
    kind: NavKind.routePath,
    path: '/profile-settings',
    roles: allRoles,
    icon: Icons.settings,
  ),
  RouteMeta(
    title: 'Profile',
    description: 'Profile page',
    keywords: ['profile', 'account'],
    kind: NavKind.routePath,
    path: '/profile',
    roles: allRoles,
    icon: Icons.person_outline,
  ),
  RouteMeta(
    title: 'Settings',
    description: 'App settings',
    keywords: ['settings', 'preferences'],
    kind: NavKind.routePath,
    path: '/settings',
    roles: allRoles,
    icon: Icons.tune,
  ),
  RouteMeta(
    title: 'File Management',
    description: 'Manage files',
    keywords: ['files', 'documents'],
    kind: NavKind.routePath,
    path: '/file-management',
    roles: allRoles,
    icon: Icons.folder,
  ),
  RouteMeta(
    title: 'AI Configuration',
    description: 'Configure AI features',
    keywords: ['ai', 'config'],
    kind: NavKind.routePath,
    path: '/ai-configuration',
    roles: allRoles,
    icon: Icons.psychology,
  ),
  RouteMeta(
    title: 'Notetaker Configuration',
    description: 'Configure notetaker',
    keywords: ['notetaker', 'config'],
    kind: NavKind.routePath,
    path: '/notetaker-configuration',
    roles: staffRoles,
    icon: Icons.notes,
  ),

  RouteMeta(
    title: 'Notetaker Search',
    description: 'Search notes',
    keywords: ['notetaker', 'notes', 'search'],
    kind: NavKind.routePath,
    path: '/notetaker-search',
    roles: staffRoles,
    icon: Icons.search,
  ),

  // Calendar and check in
  RouteMeta(
    title: 'Calendar Assistant',
    description: 'Calendar assistant screen',
    keywords: ['calendar', 'schedule'],
    kind: NavKind.routePath,
    path: '/calendar',
    roles: allRoles,
    icon: Icons.calendar_today,
  ),
  RouteMeta(
    title: 'Virtual Check In',
    description: 'Patient virtual check in',
    keywords: ['checkin', 'virtual'],
    kind: NavKind.routePath,
    path: '/virtual-checkin',
    roles: allRoles,
    icon: Icons.how_to_reg,
  ),

  // Alexa and USPS informed delivery
  RouteMeta(
    title: 'Alexa Login',
    description: 'Login with Alexa',
    keywords: ['alexa', 'login'],
    kind: NavKind.routePath,
    path: '/alexaLogin',
    roles: allRoles,
    icon: Icons.speaker,
  ),
  RouteMeta(
    title: 'Informed Delivery',
    description: 'USPS informed delivery screen',
    keywords: ['mail', 'usps', 'delivery'],
    kind: NavKind.routePath,
    path: '/informed-delivery',
    roles: allRoles,
    icon: Icons.mark_email_read,
  ),

  RouteMeta(
    title: 'Invoice Dashboard',
    description: 'Invoices dashboard',
    keywords: ['invoice', 'billing', 'dashboard'],
    kind: NavKind.routeName,
    routeName: 'invoiceDashboard',
    roles: staffRoles,
    icon: Icons.receipt_long,
  ),

  RouteMeta(
    title: 'Fall Alert Lab',
    description: 'Mock fall alert page',
    keywords: ['alert', 'fall'],
    kind: NavKind.routePath,
    path: '/alertpage',
    roles: allRoles,
    icon: Icons.warning_amber,
  )
];
