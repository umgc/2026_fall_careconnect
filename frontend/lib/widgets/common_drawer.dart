import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/router/app_router.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import 'theme_toggle_switch.dart';

class CommonDrawer extends StatefulWidget {
  final String currentRoute;

  const CommonDrawer({super.key, required this.currentRoute});

  @override
  State<CommonDrawer> createState() => _CommonDrawerState();
}

class _CommonDrawerState extends State<CommonDrawer> {
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _loadProfilePicture();
  }

  Future<void> _loadProfilePicture() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userId = userProvider.user?.id;

      if (userId != null) {
        final userRole = userProvider.user?.role;
        final imageUrl = await ApiService.getUserProfilePictureUrl(
          userId,
          userRole,
        );
        if (mounted) {
          setState(() {
            _profileImageUrl = imageUrl;
          });
        }
      }
    } catch (e) {
      print('Error loading profile picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    // Only show drawer for logged-in users
    if (user == null) {
      return Drawer(
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.login,
                  size: 64,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'Please log in',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You need to be logged in to access navigation',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/login');
                  },
                  child: const Text('Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isCaregiver = user.role.toUpperCase() == 'CAREGIVER' ||
        user.role.toUpperCase() == 'FAMILY_LINK' ||
        user.role.toUpperCase() == 'ADMIN';
    final isAdmin = user.role.toUpperCase() == 'ADMIN';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              context.go('/profile');
            },
            child: DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).appBarTheme.backgroundColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.onPrimary,
                    backgroundImage: _profileImageUrl != null
                        ? NetworkImage(_profileImageUrl!) as ImageProvider
                        : null,
                    child: _profileImageUrl == null
                        ? Icon(
                            Icons.person,
                            size: 30,
                            color: Theme.of(context).primaryColor,
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.name ?? 'User',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color:
                              Theme.of(context).appBarTheme.foregroundColor ??
                                  Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Row(
                    children: [
                      Text(
                        user.role,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: (Theme.of(context)
                                          .appBarTheme
                                          .foregroundColor ??
                                      Theme.of(context).colorScheme.onPrimary)
                                  .withOpacity(0.7),
                            ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.person,
                        size: 14,
                        color: (Theme.of(context).appBarTheme.foregroundColor ??
                                Theme.of(context).colorScheme.onPrimary)
                            .withOpacity(0.7),
                      ),
                      Text(
                        ' View Profile',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: (Theme.of(context)
                                          .appBarTheme
                                          .foregroundColor ??
                                      Theme.of(context).colorScheme.onPrimary)
                                  .withOpacity(0.9),
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Dashboard - always visible
          _buildDrawerItem(
            context,
            icon: Icons.dashboard,
            title: 'Dashboard',
            isActive: widget.currentRoute == '/dashboard',
            onTap: () {
              Navigator.pop(context);
              navigateToDashboard(context);
            },
          ),

          // Calendar Assistant - always visible
          _buildDrawerItem(
            context,
            icon: Icons.calendar_month,
            title: 'Calendar Assistant',
            route: '/calendar',
            isActive: widget.currentRoute == '/calendar',
          ),

          _buildDrawerItem(
            context,
            icon: Icons.calendar_month,
            title: 'Informed Delivery',
            route: '/calendar',
            isActive: widget.currentRoute == '/calendar',
          ),

          _buildDrawerItem(
            context,
            icon: Icons.note,
            title: 'Medical Notetaker',
            route: '/notetaker-search',
            isActive: widget.currentRoute == '/notetaker-search',
          ),

          // Core Features (reordered logically)
          _buildDrawerItem(
            context,
            icon: Icons.medication,
            title: 'Medication Management',
            route: '/medication',
            isActive: widget.currentRoute == '/medication',
          ),

          _buildDrawerItem(
            context,
            icon: Icons.people_alt,
            title: 'Social Feed',
            route: '/social-feed',
            isActive: widget.currentRoute == '/social-feed',
            onTap: () {
              Navigator.pop(context);
              final userId = user.id;
              context.go('/social-feed?userId=$userId');
            },
          ),

          _buildDrawerItem(
            context,
            icon: Icons.emoji_events,
            title: 'Gamification',
            route: '/gamification',
            isActive: widget.currentRoute == '/gamification',
          ),

          ExpansionTile(
            leading: Icon(
              Icons.receipt_long,
              color: widget.currentRoute.startsWith('/invoice-assistant')
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).iconTheme.color,
            ),
            title: Text(
              'Invoice Assistant',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: widget.currentRoute.startsWith('/invoice-assistant')
                        ? Theme.of(context).primaryColor
                        : Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight:
                        widget.currentRoute.startsWith('/invoice-assistant')
                            ? FontWeight.bold
                            : FontWeight.normal,
                  ),
            ),
            initiallyExpanded: widget.currentRoute.startsWith(
              '/invoice-assistant',
            ),
            children: [
              _buildDrawerItem(
                context,
                icon: Icons.dashboard_customize,
                title: 'Dashboard',
                route: '/invoice-assistant/dashboard',
                isActive: widget.currentRoute == '/invoice-assistant/dashboard',
              ),

              // _buildDrawerItem(
              //   context,
              //   icon: Icons.cloud_upload,
              //   title: 'Upload Invoice',
              //   route: '/invoice-assistant/upload',
              //   isActive: widget.currentRoute == '/invoice-assistant/upload',
              // ),
              _buildDrawerItem(
                context,
                icon: Icons.cloud_upload,
                title: 'Upload Invoice',
                route: '/invoice-assistant/upload',
                isActive: widget.currentRoute == '/invoice-assistant/upload',
              ),
              _buildDrawerItem(
                context,
                icon: Icons.list,
                title: 'Invoice List',
                route: '/invoice-assistant/list',
                isActive: widget.currentRoute == '/invoice-assistant/list',
              ),
              // _buildDrawerItem(
              //   context,
              //   icon: Icons.filter_alt,
              //   title: 'Pending',
              //   route: '/invoice-assistant/list/pending',
              //   isActive:
              //       widget.currentRoute == '/invoice-assistant/list/pending',
              // ),
              // _buildDrawerItem(
              //   context,
              //   icon: Icons.report,
              //   title: 'Overdue',
              //   route: '/invoice-assistant/list/overdue',
              //   isActive:
              //       widget.currentRoute == '/invoice-assistant/list/overdue',
              // ),
              // _buildDrawerItem(
              //   context,
              //   icon: Icons.block,
              //   title: 'Rejected Insurance',
              //   route: '/invoice-assistant/list/rejected',
              //   isActive:
              //       widget.currentRoute == '/invoice-assistant/list/rejected',
              // ),
            ],
          ),

          const Divider(),

          // Device Integration
          _buildDrawerItem(
            context,
            icon: Icons.watch,
            title: 'Wearables',
            route: '/wearables',
            isActive: widget.currentRoute == '/wearables',
          ),

          // EVV - visible to all roles
          _buildDrawerItem(
            context,
            icon: Icons.verified_user_outlined,
            title: 'EVV Visits',
            route: '/evv',
            isActive: widget.currentRoute.startsWith('/evv'),
          ),

          // Caregiver-specific menu items
          if (isCaregiver) ...[
            const Divider(),
            _buildDrawerItem(
              context,
              icon: Icons.person_add,
              title: 'Add Patient',
              route: '/add-patient',
              isActive: widget.currentRoute == '/add-patient',
            ),
          ],

          if (isAdmin) ...[
            const Divider(),
            _buildDrawerItem(
              context,
              icon: Icons.insights_outlined,
              title: 'Product Analytics',
              route: '/admin/analytics',
              isActive: widget.currentRoute == '/admin/analytics',
            ),
          ],

          const Divider(),

          // Settings
          _buildDrawerItem(
            context,
            icon: Icons.settings,
            title: 'Settings',
            route: '/settings',
            isActive: widget.currentRoute == '/settings',
          ),

          // File Management
          _buildDrawerItem(
            context,
            icon: Icons.folder,
            title: 'File Management',
            route: '/file-management',
            isActive: widget.currentRoute == '/file-management',
          ),

          // Theme Toggle
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.brightness_6,
                  color: Theme.of(context).iconTheme.color,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Dark Mode',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const ThemeToggleSwitch(showIcon: false, showLabel: false),
              ],
            ),
          ),

          const Divider(),

          _buildDrawerItem(
            context,
            icon: Icons.logout,
            title: 'Logout',
            iconColor: Theme.of(context).colorScheme.error,
            textColor: Theme.of(context).colorScheme.error,
            onTap: () async {
              Navigator.pop(context);
              // Logout action
              await userProvider.clearUser();
              if (context.mounted) {
                context.go('/');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? route,
    bool isActive = false,
    Color? iconColor,
    Color? textColor,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final color = isActive
        ? theme.primaryColor
        : (textColor ??
            theme.textTheme.bodyLarge?.color ??
            theme.colorScheme.onSurface);
    final bgColor = isActive ? theme.primaryColor.withOpacity(0.1) : null;

    return ListTile(
      leading: Icon(
        icon,
        color: isActive
            ? theme.primaryColor
            : (iconColor ?? theme.colorScheme.onSurface),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      tileColor: bgColor,
      onTap: onTap ??
          (route != null
              ? () {
                  Navigator.pop(context);
                  context.go(route);
                }
              : null),
    );
  }
}
