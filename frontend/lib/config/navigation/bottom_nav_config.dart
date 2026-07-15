import 'package:care_connect_app/features/dashboard/caregiver-dashboard/pages/caregiver-dashboard.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/caregiver-patient-list.dart';
import 'package:care_connect_app/features/health/symptom-tracker/pages/symptom_allergies_tracker_screen.dart';
import 'package:care_connect_app/features/social/presentation/pages/chat_inbox_screen.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/shift_schedule_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/widgets/menu/menu_page.dart';
import 'package:flutter/material.dart';
import '../../features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart';
import '../../screens/tabs/patient_tabs.dart';
import '../../screens/tabs/caregiver_tabs.dart';

/// Represents a single item in the bottom navigation bar.
///
/// This class defines the structure for navigation items that appear in the
/// bottom navigation bar. Each item can either navigate to a screen or
/// execute a custom function when pressed.
///
/// Parameters:
/// * [label] - The text label displayed below the icon
/// * [icon] - The icon displayed when the item is not active
/// * [activeIcon] - Optional icon displayed when the item is active
/// * [routeName] - The route identifier for navigation purposes
/// * [screen] - Optional widget to display when the item is pressed
/// * [requiresPatientId] - Whether this item requires a patient ID to function
/// * [onPress] - Optional callback function executed when the item is pressed
///
/// Either [screen] or [onPress] must be provided, but not both.
class BottomNavItem {
  final String label;
  final String? labelKey;   // i18n key
  final IconData icon;
  final IconData? activeIcon;
  final String routeName;
  final Widget? screen;
  final bool requiresPatientId;
  final bool showCallFab;
  final void Function(BuildContext context, WidgetBuilder builder)? onPress;

  /// Creates a new BottomNavItem.
  ///
  /// Parameters:
  /// * [label] - The text label displayed below the icon
  /// * [icon] - The icon displayed when the item is not active
  /// * [activeIcon] - Optional icon displayed when the item is active
  /// * [routeName] - The route identifier for navigation purposes
  /// * [screen] - Optional widget to display when the item is pressed
  /// * [requiresPatientId] - Whether this item requires a patient ID to function (defaults to false)
  /// * [showCallFab] - Whether to show the global video call FAB on this tab (defaults to false)
  /// * [onPress] - Optional callback function executed when the item is pressed
  const BottomNavItem({
    required this.label,
    this.labelKey,
    required this.icon,
    this.activeIcon,
    required this.routeName,
    this.screen,
    this.requiresPatientId = false,
    this.showCallFab = false,
    this.onPress,
  }) : assert(
         screen != null || onPress != null,
         'Either screen or onPress must be provided',
       );

   String localizedLabel(AppLocalizations t) {
    switch (labelKey) {
      case 'nav_home': return t.navHome;
      case 'nav_symptoms': return t.navSymptoms;
      case 'nav_health': return t.navHealth;
      case 'nav_messages': return t.navMessages;
      case 'nav_menu': return t.navMenu;
      case 'nav_patientList': return t.navPatientList;
      case 'nav_analytics': return t.navAnalytics;
      case 'nav_more': return t.navMore;
      default: return label;
    }
  }
}

/// Configuration class for bottom navigation bar items.
///
/// This class provides static methods to generate navigation items
/// for different user roles within the application. Each role has
/// its own set of navigation items tailored to their functionality.
class BottomNavConfig {
  /// Returns the bottom navigation items for patient users.
  ///
  /// Creates a list of navigation items specifically designed for patients,
  /// including Home, Symptoms, Health, Messages, and More sections.
  /// The More section opens a bottom drawer with additional features.
  ///
  /// Returns:
  /// * List<BottomNavItem> - A list of navigation items for patient interface
  static List<BottomNavItem> getPatientNavItems() {
    return [
      BottomNavItem(
        label: 'Home',
        labelKey: 'nav_home',
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        routeName: 'home',
        screen: const PatientHomeTab(),
        showCallFab: true,
      ),
      BottomNavItem(
        label: 'Symptoms and Allergies',
        labelKey: 'nav_symptoms',
        icon: Icons.medical_information_outlined,
        activeIcon: Icons.medical_information,
        routeName: 'symptoms',
        screen: const SymptomsAllergiesPage(),
      ),
      BottomNavItem(
        label: 'Virtual Check-In',
        labelKey: 'nav_health',
        icon: Icons.health_and_safety_outlined,
        activeIcon: Icons.health_and_safety,
        routeName: 'check-in',
        screen: const PatientVirtualCheckIn(),
      ),
      BottomNavItem(
        label: 'Messages',
        labelKey: 'nav_messages',
        icon: Icons.message_outlined,
        activeIcon: Icons.message,
        routeName: 'messages',
        screen: const ChatInboxScreen(),
      ),
      BottomNavItem(
        label: 'Menu',
        labelKey: 'nav_more',
        icon: Icons.menu_outlined,
        activeIcon: Icons.menu,
        routeName: 'menupage',
        screen: const MenuPage(),
        onPress: (context, builder) {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const MenuPage(),
          );
        },
      ),
    ];
  }
  /// Returns the bottom navigation items for caregiver users.
  ///
  /// Creates a list of navigation items specifically designed for caregivers,
  /// including Home, Patient List, Analytics, Messages, and More sections.
  /// The More section opens a bottom drawer with additional features.
  ///
  /// Returns:
  /// * List<BottomNavItem> - A list of navigation items for caregiver interface
static List<BottomNavItem> getCaregiverNavItems() {
    return [
      BottomNavItem(
        label: 'Home',
        labelKey: 'nav_home',
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        routeName: 'home',
        screen: const CaregiverDashboard(),
        showCallFab: true,
      ),
      BottomNavItem(
        label: 'Patient List',
        labelKey: 'nav_patientList',
        icon: Icons.person_2_outlined,
        activeIcon: Icons.person_2,
        routeName: 'tasks',
        screen: const CaregiverPatientList(),
      ),
      BottomNavItem(
        label: 'Analytics',
        labelKey: 'nav_analytics',
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics,
        routeName: 'analytics',
        screen: const CaregiverAnalyticsTab(),
      ),
      BottomNavItem(
        label: 'Schedule',
        icon: Icons.calendar_month_outlined,
        activeIcon: Icons.calendar_month,
        routeName: 'schedule',
        screen: const CaregiverShiftSchedulingScreen(),
      ),
      BottomNavItem(
        label: 'Messages',
        labelKey: 'nav_messages',
        icon: Icons.message_outlined,
        activeIcon: Icons.message,
        routeName: 'messages',
        screen: const CaregiverMessagesTab(),
      ),
      BottomNavItem(
        label: 'Menu',
        icon: Icons.menu_open_outlined,
        activeIcon: Icons.menu_open,
        routeName: 'profile',
        onPress: (context, builder) {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const MenuPage(),
          );
        },
      ),
    ];
  }
  /// Returns navigation items based on the specified user role.
  ///
  /// This method acts as a factory that returns the appropriate navigation
  /// items based on the user's role. Supports PATIENT, CAREGIVER, FAMILY_LINK,
  /// and ADMIN roles, with patient navigation as the default fallback.
  ///
  /// Parameters:
  /// * [role] - The user's role as a string (case-insensitive)
  ///
  /// Returns:
  /// * List<BottomNavItem> - Navigation items appropriate for the specified role
  static List<BottomNavItem> getNavItemsForRole(String role) {
    switch (role.toUpperCase()) {
      case 'PATIENT':
        return getPatientNavItems();
      case 'CAREGIVER':
      case 'FAMILY_LINK':
      case 'ADMIN':
        return getCaregiverNavItems();
      default:
        // TODO - We should throw exception if the roles doesn't exist
        //        We don't want any data leakage.
        return getPatientNavItems();
    }
  }
}
