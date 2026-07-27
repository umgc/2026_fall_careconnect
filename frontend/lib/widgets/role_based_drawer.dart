import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/auth_service.dart';

/// Navigation drawer that shows menu items based on user role
class RoleBasedDrawer extends StatelessWidget {
  const RoleBasedDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        final user = userProvider.userSession;
        
        if (user == null) {
          return const Drawer(
            child: Center(
              child: Text('Not logged in'),
            ),
          );
        }

        return Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // User header
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 40,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                accountName: Text(user.name),
                accountEmail: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(user.email),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getRoleColor(user.role),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getRoleDisplayName(user.role),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Dashboard (all users)
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/dashboard');
                },
              ),

              const Divider(),

              // Admin menu
              if (_isAdmin(user.role))
                ExpansionTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Administration'),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.people),
                      title: const Text('User Management'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/admin/users');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.security),
                      title: const Text('Role Management'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/admin/roles');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('Product Analytics'),
                      onTap: () {
                        Navigator.pop(context);
                        context.go('/admin/analytics');
                      },
                    ),
                  ],
                ),

              // Caregiver/Admin menu
              if (_isCaregiverOrAdmin(user.role))
                ExpansionTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Patient Management'),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_search),
                      title: const Text('My Patients'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/patients');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_add),
                      title: const Text('Add Patient'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/patients/add');
                      },
                    ),
                  ],
                ),

              // Tasks (all except family members)
              if (!_isFamilyMember(user.role))
                ListTile(
                  leading: const Icon(Icons.task),
                  title: const Text('Tasks'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/tasks');
                  },
                ),

              // Health Data (all users)
              ListTile(
                leading: const Icon(Icons.health_and_safety),
                title: const Text('Health Data'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/health');
                },
              ),

              // Analytics (caregiver/admin only)
              if (_isCaregiverOrAdmin(user.role))
                ListTile(
                  leading: const Icon(Icons.analytics),
                  title: const Text('Analytics'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/analytics');
                  },
                ),

              // Messages (all users)
              ListTile(
                leading: const Icon(Icons.message),
                title: const Text('Messages'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/messages');
                },
              ),

              const Divider(),

              // Settings
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/settings');
                },
              ),

              // Logout
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () => _handleLogout(context, userProvider),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return Colors.red.shade700;
      case 'CAREGIVER':
      case 'FAMILY_LINK':
        return Colors.blue.shade700;
      case 'PATIENT':
        return Colors.green.shade700;
      case 'FAMILY_MEMBER':
        return Colors.purple.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return 'Administrator';
      case 'CAREGIVER':
        return 'Caregiver';
      case 'FAMILY_LINK':
        return 'Family Link';
      case 'PATIENT':
        return 'Patient';
      case 'FAMILY_MEMBER':
        return 'Family Member';
      default:
        return role;
    }
  }

  bool _isAdmin(String role) {
    return role.toUpperCase() == 'ADMIN';
  }

  bool _isCaregiverOrAdmin(String role) {
    final r = role.toUpperCase();
    return r == 'ADMIN' || r == 'CAREGIVER' || r == 'FAMILY_LINK';
  }

  bool _isFamilyMember(String role) {
    return role.toUpperCase() == 'FAMILY_MEMBER';
  }

  Future<void> _handleLogout(
    BuildContext context,
    UserProvider userProvider,
  ) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && context.mounted) {
      // Call logout from AuthService
      await AuthService.logout();
      
      // Clear user provider
      await userProvider.logout();
      
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }
}