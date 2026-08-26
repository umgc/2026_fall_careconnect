import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/health/medication-tracker/pages/medication-tracker.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/screens/tabs/patient_tabs.dart';
import 'package:care_connect_app/widgets/language/language_picker.dart';
import 'package:care_connect_app/widgets/theme_toggle_switch.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_tabbed_page.dart';
import 'package:care_connect_app/features/telemetry/telemetry.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    Telemetry.event('screen_view', {
      'screen': 'menu_page',
    });
    _loadProfilePicture();
  }

  Future<void> _loadProfilePicture() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userId = userProvider.user?.id;
      if (userId != null) {
        final role = userProvider.user?.role;
        final url = await ApiService.getUserProfilePictureUrl(userId, role);
        if (!mounted) return;
        setState(() => _profileImageUrl = url);
      }
    } catch (_) {
      // Keep avatar fallback
    }
  }

  String _translateRole(String role, AppLocalizations t) {
    switch (role) {
      case ('PATIENT'):
        return t.roles_Patient;
      case ('CAREGIVER'):
        return t.roles_Caregiver;
      case ('ADMIN'):
        return t.roles_Admin;
      default:
        return role;
    }
  }

  void _trackMenuTap(_MenuItem item) {
    Telemetry.event('button_tap', {
      'screen': 'menu_page',
      'target': item.label,
      if (item.route != null) 'route': item.route,
    });
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;

    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(local.menuTitle)),
        body: _LoggedOutPrompt(onLogin: () => context.push('/login')),
      );
    }

    final role = user.role.toUpperCase();

    final items = <_MenuItem>[
      _MenuItem(
        icon: Icons.auto_awesome,
        label: 'New UI (preview)',
        route: '/ui-preview',
        visibleFor: const {'PATIENT', 'CAREGIVER', 'ADMIN', 'FAMILY_LINK'},
      ),
      _MenuItem(
        icon: Icons.receipt_long,
        label: local.invoiceAssistant,
        route: '/invoice-assistant/dashboard',
        visibleFor: const {'CAREGIVER', 'ADMIN', 'PATIENT'},
        onTap: () {
          //Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const InvoiceTabbedPage()),
          );
        },
      ),
      _MenuItem(
          icon: Icons.report,
          label: local.menupage_patientReportItem,
          route: '/patient-report',
          visibleFor: const {'PATIENT'},
          onTap: () {
            //Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PatientReportsTab()));
          }),
      _MenuItem(
        icon: Icons.verified_user,
        label: local.evv,
        route: '/evv',
        visibleFor: const {'CAREGIVER', 'ADMIN'},
      ),
      _MenuItem(
        icon: Icons.calendar_month,
        label: local.calendarAssistant,
        route: '/calendar',
      ),
      _MenuItem(
          icon: Icons.medication,
          label: local.menupage_medicationTrackerItem,
          onTap: () {
            //Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const MedicationsTrackerPage()),
            );
          },
          visibleFor: {"PATIENT"}),
      _MenuItem(
        icon: Icons.public,
        label: local.socialFeed,
        onTap: () => context.push('/social-feed?userId=${user.id}'),
      ),
      _MenuItem(
        icon: Icons.emoji_events,
        label: local.gamification,
        route: '/gamification',
      ),
      _MenuItem(icon: Icons.watch, label: local.wearables, route: '/wearables'),
      _MenuItem(
        icon: Icons.folder,
        label: local.notetakerAssistant,
        route: '/notetaker-search',
      ),
      // _MenuItem(
      //   icon: Icons.person_add,
      //   label: local.addPatient,
      //   route: '/add-patient',
      //   visibleFor: const {'CAREGIVER'},
      // ),
      _MenuItem(
        icon: Icons.mail,
        label: local.informedDelivery,
        route: '/informed-delivery',
      ),
      // _MenuItem(
      //   icon: Icons.settings,
      //   label: local.settings,
      //   route: '/settings',
      //   section: _Section.settings,
      // ),
      _MenuItem(
        icon: Icons.devices,
        label: local.smartDevices,
        route: '/smart-devices',
      ),
      _MenuItem(
        icon: Icons.folder,
        label: local.fileManagement,
        route: '/file-management',
      ),
      _MenuItem(
        icon: Icons.mic,
        label: local.voiceCommands,
        route: '/voice',
      ),
      _MenuItem(
        icon: Icons.wb_sunny_outlined,
        label: local.dailyBrief,
        route: '/stml/brief',
        visibleFor: const {'PATIENT'},
      ),
      _MenuItem(
        icon: Icons.manage_search,
        label: local.stmlSearch,
        route: '/stml/search',
        visibleFor: const {'PATIENT'},
      ),
      _MenuItem(
        icon: Icons.fact_check_outlined,
        label: local.stmlCheckIn,
        route: '/stml/checkin',
        visibleFor: const {'CAREGIVER'},
      ),
      _MenuItem(
        icon: Icons.sensors,
        label: local.fallDetection,
        route: '/alertpage',
      ),
      _MenuItem(
          icon: Icons.mail,
          label: 'USPS ${local.menupage_mailDigestItem}',
          route: '/usps-test'),
      _MenuItem(
        icon: Icons.person_add,
        label: local.menupage_addPatientItem,
        route: '/add-patient',
        visibleFor: const {'CAREGIVER', 'ADMIN'},
      ),
      _MenuItem(
        icon: Icons.insights_outlined,
        label: 'Product Analytics',
        route: '/admin/analytics',
        visibleFor: const {'ADMIN'},
        onTap: () {
          //Navigator.pop(context);
          context.push('/admin/analytics');
        },
      ),
      _MenuItem(
        icon: Icons.people,
        label: 'User Management',
        route: '/admin/users',
        visibleFor: const {'ADMIN'},
        onTap: () {
          //Navigator.pop(context);
          context.push('/admin/users');
        },
      ),
      _MenuItem(
        icon: Icons.settings,
        label: local.menupage_settingsItem,
        route: '/settings',
        section: _Section.settings,
      ),
    ].where((m) => m.isVisibleFor(role)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(local.menuTitle),
      ),
      body: CustomScrollView(
        slivers: [
          // Profile header
          SliverToBoxAdapter(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.onPrimary,
                backgroundImage: _profileImageUrl != null
                    ? NetworkImage(_profileImageUrl!)
                    : null,
                child: _profileImageUrl == null
                    ? Icon(Icons.person, color: Theme.of(context).primaryColor)
                    : null,
              ),
              title: Text(
                user.name ?? local.fallbackUser,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _translateRole(role, local),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  Telemetry.event('button_tap', {
                    'screen': 'menu_page',
                    'target': 'profile',
                    'route': '/profile',
                  });
                  context.push('/profile');
                },
              ),
              onTap: () {
                Telemetry.event('button_tap', {
                  'screen': 'menu_page',
                  'target': 'profile',
                  'route': '/profile',
                });
                context.push('/profile');
              },
            ),
          ),

          // Tools
          SliverToBoxAdapter(child: _SectionHeader(title: local.tools)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 64,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ToolTile(
                  item: items[index],
                  onTrackTap: _trackMenuTap,
                ),
                childCount: items.length,
              ),
            ),
          ),

          // Preferences
          SliverToBoxAdapter(child: _SectionHeader(title: local.preferences)),
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 520;
                  final divider = VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor,
                  );

                  final localeProvider = context.watch<LocaleProvider>();
                  final currentLabel = localeProvider.locale == null
                      ? local.systemDefault
                      : LanguagePicker.labelFor(localeProvider.locale!, local);

                  final darkTile = ListTile(
                    leading: const Icon(Icons.brightness_6),
                    title: Text(local.darkMode),
                    trailing: const ThemeToggleSwitch(
                      showIcon: false,
                      showLabel: false,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  );

                  final langTile = ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(local.language),
                    subtitle: Text(currentLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Telemetry.event('button_tap', {
                        'screen': 'menu_page',
                        'target': 'language_picker',
                      });
                      LanguagePicker.show(context);
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  );

                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: darkTile),
                        divider,
                        Expanded(child: langTile),
                      ],
                    );
                  } else {
                    return Column(
                      children: [darkTile, const Divider(height: 1), langTile],
                    );
                  }
                },
              ),
            ),
          ),

          // Logout
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  local.logout,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  Telemetry.event('button_tap', {
                    'screen': 'menu_page',
                    'target': 'logout',
                  });
                  await userProvider.clearUser();
                  if (context.mounted) context.go('/');
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/* ---------- Small components ---------- */

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

enum _Section { tools, settings }

class _MenuItem {
  final IconData icon;
  final String label;
  final String? route;
  final VoidCallback? onTap;
  final _Section section;
  final Set<String>? visibleFor;

  _MenuItem({
    required this.icon,
    required this.label,
    this.route,
    this.onTap,
    this.section = _Section.tools,
    this.visibleFor,
  });

  bool isVisibleFor(String roleUpper) {
    if (visibleFor == null || visibleFor!.isEmpty) return true;
    return visibleFor!.contains(roleUpper);
  }
}

class _ToolTile extends StatelessWidget {
  final _MenuItem item;
  final void Function(_MenuItem item) onTrackTap;

  const _ToolTile({
    required this.item,
    required this.onTrackTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          onTrackTap(item);

          if (item.onTap != null) {
            item.onTap!();
          } else if (item.route != null) {
            context.push(item.route!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(item.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoggedOutPrompt extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoggedOutPrompt({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.login, size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(t.pleaseLogIn, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              t.loginRequiredMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Telemetry.event('button_tap', {
                  'screen': 'menu_page_logged_out',
                  'target': 'login',
                });
                onLogin();
              },
              child: Text(t.login),
            ),
          ],
        ),
      ),
    );
  }
}
