import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/user_role_storage_service.dart';
import '../../providers/user_provider.dart';
import 'main_screen_config.dart';
import 'bottom_nav_config.dart';

/// Navigation helper that works with stored user data instead of URL parameters
class NavigationHelper {
  /// Navigate to the main screen using stored user data
  static Future<void> navigateToMainScreen(
    BuildContext context, {
    int? tabIndex,
    bool clearHistory = false,
  }) async {
    final userData = await UserRoleStorageService.instance.getUserData();

    if (userData == null || !userData.isLoggedIn) {
      if (context.mounted) {
        context.go('/login');
      }
      return;
    }

    // Build the dashboard URL without role parameter
    String dashboardUrl = '/dashboard';

    if (tabIndex != null) {
      // Convert tab index to tab name based on role
      String? tabName = _getTabNameFromIndex(userData.role, tabIndex);
      if (tabName != null) {
        dashboardUrl += '?tab=$tabName';
      }
    }

    if (context.mounted) {
      if (clearHistory) {
        context.go(dashboardUrl);
      } else {
        context.push(dashboardUrl);
      }
    }
  }

  /// Navigate to a specific tab in the main screen
  static Future<void> navigateToTab(
    BuildContext context,
    String tabName,
  ) async {
    final userData = await UserRoleStorageService.instance.getUserData();

    if (userData == null || !userData.isLoggedIn) {
      if (context.mounted) {
        context.go('/login');
      }
      return;
    }

    if (context.mounted) {
      context.go('/dashboard?tab=$tabName');
    }
  }

  /// Get MainScreenConfig based on stored user data
  static Future<MainScreenConfig?> getMainScreenConfig() async {
    final userData = await UserRoleStorageService.instance.getUserData();

    if (userData == null || !userData.isLoggedIn || userData.userId <= 0) {
      return null;
    }

    switch (userData.role.toUpperCase()) {
      case 'PATIENT':
        return MainScreenConfig.forPatient(
          userId: userData.userId,
          patientId: userData.patientId,
        );
      case 'CAREGIVER':
        return MainScreenConfig.forCaregiver(
          userId: userData.userId,
          caregiverId: userData.caregiverId,
          patientId: userData.patientId,
        );
      case 'FAMILY_LINK':
        return MainScreenConfig.forFamilyMember(
          userId: userData.userId,
          patientId: userData.patientId,
        );
      case 'ADMIN':
        return MainScreenConfig(
          userRole: 'ADMIN',
          userId: userData.userId,
          showAppBar: true,
          appBarTitle: 'Admin Dashboard',
          primaryColor: Colors.red,
        );
      default:
        return null;
    }
  }

  /// Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    return await UserRoleStorageService.instance.isLoggedIn();
  }

  /// Logout and clear stored data
  static Future<void> logout(BuildContext context) async {
    await UserRoleStorageService.instance.clearUserData();

    // Clear provider data as well
    if (context.mounted) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider.clearUser();

      context.go('/login');
    }
  }

  /// Helper method to convert tab index to tab name based on role
  static String? _getTabNameFromIndex(String role, int tabIndex) {
    final items = BottomNavConfig.getNavItemsForRole(role);
    if (tabIndex < 0 || tabIndex >= items.length) return null;
    return items[tabIndex].routeName;
  }

  /// Get tab index from tab name
  static int? getTabIndexFromName(String role, String tabName) {
    // Use the rendered navigation order; Schedule shifted caregiver Messages
    // to index 4. Separate hard-coded lists silently opened the wrong tab.
    final items = BottomNavConfig.getNavItemsForRole(role);
    var name = tabName.toLowerCase();
    // Keep existing dashboard links usable after the navigation labels changed.
    if (role.toUpperCase() == 'PATIENT') {
      if (name == 'health') name = 'check-in';
      if (name == 'profile') name = 'menupage';
    } else if (name == 'patients') {
      name = 'home';
    }
    final index = items.indexWhere(
      (item) => item.routeName.toLowerCase() == name,
    );
    return index < 0 ? null : index;
  }
}

/// Extension methods for BuildContext to make navigation easier
extension NavigationContextExtension on BuildContext {
  /// Navigate to main screen using stored user data
  Future<void> navigateToMainScreen({
    int? tabIndex,
    bool clearHistory = false,
  }) async {
    await NavigationHelper.navigateToMainScreen(
      this,
      tabIndex: tabIndex,
      clearHistory: clearHistory,
    );
  }

  /// Navigate to a specific tab
  Future<void> navigateToTab(String tabName) async {
    await NavigationHelper.navigateToTab(this, tabName);
  }

  /// Logout user
  Future<void> logoutUser() async {
    await NavigationHelper.logout(this);
  }
}
