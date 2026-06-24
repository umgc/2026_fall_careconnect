import 'dart:async';
import 'dart:convert';
import '../services/auth_token_manager.dart';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/user_provider.dart';
import '../config/navigation/bottom_nav_config.dart';
import '../config/navigation/main_screen_config.dart';
import '../services/api_service.dart';
import '../services/local_db/offline_sync_service.dart';
import '../features/telemetry/telemetry.dart';
import '../services/call_notification_service.dart';
import '../widgets/hybrid_video_call_widget.dart';

/// Main screen of the application. This is where the user is navigated to
/// after logging in. This contains the bottom nav bar and main screens
class MainScreen extends StatefulWidget {
  final int? initialTabIndex;
  final MainScreenConfig? config;

  const MainScreen({super.key, this.initialTabIndex, this.config});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  List<BottomNavItem> _navItems = [];
  late PageController _pageController;
  late MainScreenConfig _config;
  UserProvider? _observedUserProvider;
  bool _isOfflineSyncInProgress = false;
  bool? _lastKnownOnlineState;
  List<OfflineSyncQueueItem> _pendingSyncQueue = const [];
  String? _currentlySyncingRequestId;
  final Set<String> _failedRequestIds = <String>{};
  Timer? _syncStartDelayTimer;
  bool _showSyncCompleteBanner = false;
  Timer? _syncCompleteBannerHideTimer;
  int _unreadMessageCount = 0;
  Timer? _messageBadgeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeConfig();
    _pageController = PageController(initialPage: widget.initialTabIndex ?? 0);
    _selectedIndex = widget.initialTabIndex ?? 0;
    _initializeNavigation();
    // Keep both startup flows: offline queue recovery and realtime call notifications.
    _initializeConnectivitySyncBridge();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCallNotifications();
      _refreshUnreadMessageBadge();
      _startUnreadMessageBadgePolling();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observedUserProvider?.removeListener(_handleConnectivityTransition);
    _syncStartDelayTimer?.cancel();
    _syncCompleteBannerHideTimer?.cancel();
    _messageBadgeTimer?.cancel();
    CallNotificationService.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Connects global connectivity state to background sync.
  ///
  /// This listens to [UserProvider] network transitions and triggers a focused
  /// sync of offline API records once the device comes back online.
  void _initializeConnectivitySyncBridge() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final provider = Provider.of<UserProvider>(context, listen: false);
      _observedUserProvider = provider;
      _lastKnownOnlineState = provider.isDeviceOnline;
      provider.addListener(_handleConnectivityTransition);

      // On cold start, also recover and schedule any existing queue.
      if (provider.isDeviceOnline) {
        unawaited(_prepareQueuedSync());
      }
    });
  }

  Future<void> _handleConnectivityTransition() async {
    final provider = _observedUserProvider;
    if (provider == null) {
      return;
    }

    final isOnlineNow = provider.isDeviceOnline;
    final transitionedToOnline =
        _lastKnownOnlineState == false && isOnlineNow == true;
    _lastKnownOnlineState = isOnlineNow;

    if (isOnlineNow == false) {
      _syncStartDelayTimer?.cancel();
      setState(() {
        _currentlySyncingRequestId = null;
        _isOfflineSyncInProgress = false;
      });
      return;
    }

    if (!transitionedToOnline) {
      return;
    }

    await _prepareQueuedSync();
  }

  /// Loads queued offline API calls and schedules delayed sync after reconnect.
  ///
  /// UX behavior:
  /// 1. Show a blue banner with pending queue state.
  /// 2. Wait 10 seconds before first sync.
  /// 3. Process one item every 10 seconds until queue is empty.
  Future<void> _prepareQueuedSync() async {
    _syncStartDelayTimer?.cancel();
    final queue = await ApiService.getOfflineSyncQueue();
    if (!mounted) {
      return;
    }
    if (queue.isEmpty) {
      setState(() {
        _pendingSyncQueue = const [];
        _failedRequestIds.clear();
        _currentlySyncingRequestId = null;
      });
      return;
    }

    setState(() {
      _pendingSyncQueue = queue;
      _failedRequestIds.clear();
      _currentlySyncingRequestId = null;
      _showSyncCompleteBanner = false;
    });

    _syncStartDelayTimer = Timer(const Duration(seconds: 10), () {
      unawaited(_runQueuedSyncCycle());
    });
  }

  /// Processes queued API calls sequentially with a 15-second pacing interval.
  Future<void> _runQueuedSyncCycle() async {
    if (_isOfflineSyncInProgress) {
      return;
    }
    _isOfflineSyncInProgress = true;

    try {
      while (mounted && _pendingSyncQueue.isNotEmpty) {
        final provider = _observedUserProvider;
        if (provider == null || !provider.isDeviceOnline) {
          break;
        }

        final item = _pendingSyncQueue.first;
        setState(() {
          _currentlySyncingRequestId = item.id;
          _failedRequestIds.remove(item.id);
        });

        final synced = await ApiService.syncOfflineQueuedRequestById(item.id);

        if (!mounted) {
          break;
        }

        setState(() {
          _currentlySyncingRequestId = null;
          if (synced) {
            _pendingSyncQueue = _pendingSyncQueue
                .where((queued) => queued.id != item.id)
                .toList();
          } else {
            _failedRequestIds.add(item.id);
            // Keep failed item visible and move it to the end for later retry.
            if (_pendingSyncQueue.length > 1) {
              final nextQueue =
                  List<OfflineSyncQueueItem>.from(_pendingSyncQueue);
              nextQueue.removeAt(0);
              nextQueue.add(item);
              _pendingSyncQueue = nextQueue;
            }
          }
        });

        if (_pendingSyncQueue.isEmpty) {
          _showSyncCompleteToastBanner();
          break;
        }

        await Future<void>.delayed(const Duration(seconds: 10));
      }
    } catch (_) {
      // Best-effort sync remains non-fatal to app flow.
    } finally {
      _isOfflineSyncInProgress = false;
    }
  }

  void _showSyncCompleteToastBanner() {
    _syncCompleteBannerHideTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _showSyncCompleteBanner = true;
    });
    _syncCompleteBannerHideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showSyncCompleteBanner = false;
      });
    });
  }

  Future<void> _initializeCallNotifications() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

    final role = user.role.toUpperCase();
    if (role != 'CAREGIVER' && role != 'PATIENT') return;

    await CallNotificationService.initialize(
      userId: user.id.toString(),
      userRole: role,
      userDisplayName: user.name,
      context: context,
    );
  }

  /// Initialize the MainScreenConfig object.
  void _initializeConfig() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (widget.config != null) {
      _config = widget.config!;
    } else {
      final user = userProvider.user;

      // Check if user data is missing or invalid
      if (user == null || user.role.isEmpty || user.id <= 0) {
        _redirectToLoginWithMessage('Please log in again');
        return;
      }

      final role = user.role;
      final userId = user.id;
      final patientId = user.patientId;
      final caregiverId = user.caregiverId;

      _config = MainScreenConfig(
        userRole: role,
        userId: userId,
        patientId: patientId,
        caregiverId: caregiverId,
      );
    }
  }

  /// Redirect to login screen with a message.
  void _redirectToLoginWithMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Clear user data
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider.clearUser();

      // Show message
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));

        // Navigate to login
        context.go('/login');
      }
    });
  }

  /// Initialize the navigation items.
  void _initializeNavigation() {
    setState(() {
      _navItems = _config.getNavItems();
      // Ensure selected index is within bounds
      if (_selectedIndex >= _navItems.length) {
        _selectedIndex = 0;
      }
    });
  }

  String _normalizeTelemetryValue(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String? _telemetryScreenForNavItem(BottomNavItem item) {
    final routeName = item.routeName.trim();
    if (routeName.isNotEmpty) {
      return _normalizeTelemetryValue(routeName);
    }

    final labelKey = item.labelKey?.trim();
    if (labelKey != null && labelKey.isNotEmpty) {
      final cleaned = labelKey.replaceFirst(RegExp(r'^nav_'), '');
      return _normalizeTelemetryValue(cleaned);
    }

    return null;
  }

  /// Handle bottom nav bar item tap.
  void _onItemTapped(int index) {
    final navItem = _navItems[index];
    final screenName = _telemetryScreenForNavItem(navItem);

    if (screenName != null && index != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await Telemetry.event('button_tap', {
            'screen': 'bottom_nav',
            'button_name': screenName,
          });

          await Telemetry.event('screen_view', {
            'screen': screenName,
          });
        } catch (_) {}
      });
    }

    // Check if onPress callback exists and call it
    if (navItem.onPress != null) {
      navItem.onPress!(context, (context) => Container());
      return;
    }

    // Only change screen if there's an actual screen to navigate to
    if (navItem.screen != null) {
      setState(() {
        _selectedIndex = index;
        if (navItem.routeName == 'messages') {
          _unreadMessageCount = 0;
        }
      });
      _refreshUnreadMessageBadge();

      if (_config.enablePageAnimation) {
        _pageController.animateToPage(
          index,
          duration: _config.animationDuration,
          curve: _config.animationCurve,
        );
      } else {
        _pageController.jumpToPage(index);
      }
    }
  }

  void _startUnreadMessageBadgePolling() {
    _messageBadgeTimer?.cancel();
    _messageBadgeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshUnreadMessageBadge();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshUnreadMessageBadge();
    } else if (state == AppLifecycleState.detached) {
      AuthTokenManager.clearAuthData();
    }
  }

  Future<void> _refreshUnreadMessageBadge() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    final hasMessagesTab = _navItems.any((item) => item.routeName == 'messages');
    if (!hasMessagesTab) return;

    try {
      final inbox = await ApiService.getInbox(user.id);
      final unreadCount = inbox
          .whereType<Map<String, dynamic>>()
          .where((item) => item['hasUnread'] == true)
          .length;
      if (!mounted) return;
      setState(() {
        final currentTab = _navItems[_selectedIndex].routeName;
        _unreadMessageCount = currentTab == 'messages' ? 0 : unreadCount;
      });
    } catch (_) {
      // Keep badge best-effort only.
    }
  }

  Widget _buildNavIcon(BottomNavItem item, {required bool active}) {
    final iconData = active ? (item.activeIcon ?? item.icon) : item.icon;
    final icon = Icon(iconData);
    final showBadge = item.routeName == 'messages' && _unreadMessageCount > 0;
    if (!showBadge) {
      return icon;
    }

    final label = _unreadMessageCount > 99 ? '99+' : '$_unreadMessageCount';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -10,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
      if (_navItems[index].routeName == 'messages') {
        _unreadMessageCount = 0;
      }
    });
    _refreshUnreadMessageBadge();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _trimmed(dynamic value) => (value ?? '').toString().trim();

  String _fullName(String first, String last, String fallback) {
    final name = [first.trim(), last.trim()].where((e) => e.isNotEmpty).join(' ').trim();
    if (name.isNotEmpty) return name;
    return fallback;
  }

  bool _isRoleSupportedForGlobalCall(String role) {
    final normalized = role.trim().toUpperCase();
    return normalized == 'PATIENT' || normalized == 'CAREGIVER';
  }

  Future<List<_QuickCallTarget>> _loadQuickCallTargets(UserSession user) async {
    final role = user.role.trim().toUpperCase();
    if (role == 'PATIENT') {
      final links = await ApiService.getPatientLinkedCaregiverLinks(user.id);
      return links.where((link) {
        final enabledRaw = link['patientVideoCallsEnabled'];
        return enabledRaw is bool ? enabledRaw : '$enabledRaw'.toLowerCase() != 'false';
      }).map((link) {
        final caregiverUserId = _toInt(link['caregiverUserId']);
        if (caregiverUserId == null || caregiverUserId <= 0) {
          return null;
        }
        final caregiverName = _trimmed(link['caregiverName']);
        final caregiverEmail = _trimmed(link['caregiverEmail']);
        return _QuickCallTarget(
          userId: caregiverUserId,
          role: 'CAREGIVER',
          title: caregiverName.isNotEmpty ? caregiverName : 'Caregiver $caregiverUserId',
          subtitle: 'Caregiver - Patient calls enabled',
          email: caregiverEmail,
          phone: null,
        );
      }).whereType<_QuickCallTarget>().toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }

    if (role != 'CAREGIVER') {
      return const [];
    }

    final caregiverId = user.caregiverId;
    if (caregiverId == null || caregiverId <= 0) {
      return const [];
    }

    final patientsResponse = await ApiService.getCaregiverPatients(caregiverId);
    if (patientsResponse.statusCode != 200) {
      return const [];
    }

    final decoded = jsonDecode(patientsResponse.body);
    if (decoded is! List) {
      return const [];
    }

    final patientTargets = <_QuickCallTarget>[];
    final patientUserIds = <int>{};
    final careTeamByUserId = <int, _CareTeamAggregate>{};
    final currentUserId = user.id;

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final link = item['link'];
      final patient = item['patient'];
      final linkMap = link is Map<String, dynamic> ? link : const <String, dynamic>{};
      final patientMap = patient is Map<String, dynamic> ? patient : const <String, dynamic>{};

      final patientUserId = _toInt(linkMap['patientUserId']) ?? _toInt(patientMap['userId']);
      if (patientUserId == null || patientUserId <= 0 || patientUserIds.contains(patientUserId)) {
        continue;
      }
      patientUserIds.add(patientUserId);

      final patientName = _fullName(
        _trimmed(patientMap['firstName']),
        _trimmed(patientMap['lastName']),
        _trimmed(linkMap['patientName']).isNotEmpty
            ? _trimmed(linkMap['patientName'])
            : 'Patient $patientUserId',
      );
      final patientEmail = _trimmed(patientMap['email']).isNotEmpty
          ? _trimmed(patientMap['email'])
          : _trimmed(linkMap['patientEmail']);
      final patientPhone = _trimmed(patientMap['phone']);

      patientTargets.add(
        _QuickCallTarget(
          userId: patientUserId,
          role: 'PATIENT',
          title: patientName,
          subtitle: 'Assigned patient',
          email: patientEmail.isNotEmpty ? patientEmail : null,
          phone: patientPhone.isNotEmpty ? patientPhone : null,
        ),
      );
    }

    for (final patientTarget in patientTargets) {
      final links = await ApiService.getPatientLinkedCaregiverLinks(patientTarget.userId);
      for (final link in links) {
        final caregiverUserId = _toInt(link['caregiverUserId']);
        if (caregiverUserId == null || caregiverUserId <= 0 || caregiverUserId == currentUserId) {
          continue;
        }
        final caregiverName = _trimmed(link['caregiverName']);
        final caregiverEmail = _trimmed(link['caregiverEmail']);
        final aggregate = careTeamByUserId.putIfAbsent(
          caregiverUserId,
          () => _CareTeamAggregate(
            userId: caregiverUserId,
            name: caregiverName.isNotEmpty ? caregiverName : 'Caregiver $caregiverUserId',
            email: caregiverEmail.isNotEmpty ? caregiverEmail : null,
          ),
        );
        aggregate.patientNames.add(patientTarget.title);
        aggregate.patientUserIds.add(patientTarget.userId);
        if (aggregate.email == null && caregiverEmail.isNotEmpty) {
          aggregate.email = caregiverEmail;
        }
      }
    }

    final careTeamTargets = careTeamByUserId.values.map((entry) {
      final context = entry.patientNames.toList()..sort();
      final summary = context.isEmpty ? 'Care team caregiver' : 'Care team for: ${context.join(', ')}';
      return _QuickCallTarget(
        userId: entry.userId,
        role: 'CAREGIVER',
        title: entry.name,
        subtitle: summary,
        email: entry.email,
        phone: null,
        contextPatientUserIds: entry.patientUserIds.toList()..sort(),
      );
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    patientTargets.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return [...patientTargets, ...careTeamTargets];
  }

  Future<void> _startQuickVideoCall({
    required UserSession currentUser,
    required _QuickCallTarget target,
  }) async {
    final role = currentUser.role.trim().toUpperCase();
    final allowed = await ApiService.canInitiateVideoCall(
      currentUserId: currentUser.id,
      currentUserRole: role,
      targetUserId: target.userId,
      caregiverId: currentUser.caregiverId,
    );

    if (!allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You are not allowed to call ${target.title}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final callId = 'chime_call_${DateTime.now().millisecondsSinceEpoch}';
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HybridVideoCallWidget(
          userId: currentUser.id.toString(),
          userRole: role,
          callId: callId,
          recipientId: target.userId.toString(),
          recipientRole: target.role,
          isInitiator: true,
          isVideoEnabled: true,
          userName: (currentUser.name ?? '').trim().isNotEmpty
              ? currentUser.name!.trim()
              : currentUser.email,
          userEmail: currentUser.email,
          recipientName: target.title,
          recipientEmail: target.email,
          recipientPhone: target.phone,
          callKind: target.isCareTeamCall ? 'CARE_TEAM' : 'GENERAL',
          contextPatientUserIds: target.contextPatientUserIds,
        ),
      ),
    );
  }

  Future<void> _showQuickCallPicker() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;
    if (!_isRoleSupportedForGlobalCall(user.role)) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FutureBuilder<List<_QuickCallTarget>>(
              future: _loadQuickCallTargets(user),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return SizedBox(
                    height: 260,
                    child: Center(
                      child: Text(
                        'Unable to load call contacts.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final targets = snapshot.data ?? const <_QuickCallTarget>[];
                if (targets.isEmpty) {
                  final role = user.role.trim().toUpperCase();
                  final emptyText = role == 'PATIENT'
                      ? 'No caregivers are available for patient-initiated calls.'
                      : 'No assigned patients or care-team caregivers are available.';
                  return SizedBox(
                    height: 220,
                    child: Center(
                      child: Text(
                        emptyText,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Video Call',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: targets.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final target = targets[index];
                          final roleBadge = target.role == 'PATIENT' ? 'PATIENT' : 'CAREGIVER';
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                target.title.isNotEmpty
                                    ? target.title.substring(0, 1).toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(target.title),
                            subtitle: Text('${target.subtitle} - $roleBadge'),
                            trailing: const Icon(Icons.video_call_outlined),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await _startQuickVideoCall(
                                currentUser: user,
                                target: target,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Global voice control entry point, available across all logged-in tabs.
  /// Opens the full (non-singleShot) voice command page for navigation commands.
  Widget _buildGlobalVoiceFab() {
    return FloatingActionButton(
      heroTag: 'globalVoiceFab',
      tooltip: 'Voice commands',
      onPressed: () => context.push('/voice'),
      child: const Icon(Icons.mic),
    );
  }

  /// Combines the global voice FAB with the optional call FAB into a stacked
  /// column so both can be shown without overlapping.
  Widget _buildGlobalFabs() {
    final callFab = _buildGlobalCallFab();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (callFab != null) ...[
          callFab,
          const SizedBox(height: 12),
        ],
        _buildGlobalVoiceFab(),
      ],
    );
  }

  Widget? _buildGlobalCallFab() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null || !_isRoleSupportedForGlobalCall(user.role)) {
      return null;
    }
    if (_navItems.isEmpty || !_navItems[_selectedIndex].showCallFab) {
      return null;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 78),
      child: FloatingActionButton(
        heroTag: 'globalCallFab',
        tooltip: 'Start video call',
        onPressed: _showQuickCallPicker,
        child: const Icon(Icons.video_call),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        // Check if user data is missing or invalid
        final currentUser = userProvider.user;
        if (widget.config == null &&
            (currentUser == null ||
                currentUser.role.isEmpty ||
                currentUser.id <= 0)) {
          // Return a loading screen while redirecting
          _redirectToLoginWithMessage('Please log in again');
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Update configuration if user changes
        final currentRole = currentUser?.role ?? '';
        final currentUserId = currentUser?.id ?? 0;

        if (widget.config == null &&
            (_config.userRole != currentRole ||
                _config.userId != currentUserId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeConfig();
            _initializeNavigation();
          });
        }
        return Scaffold(
          backgroundColor: _config.backgroundColor,
          appBar: _config.showAppBar
              ? AppBar(
                  title: Text(_config.appBarTitle ?? 'CareConnect'),
                  backgroundColor:
                      _config.primaryColor ?? Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  actions: _config.appBarActions,
                )
              : null,
          // BNS 5: Global Banners (No Internet & Offline Mode)
          body: Column(
            children: [
              // Hardware Connection Lost
              if (!userProvider.isDeviceOnline)
                _buildGlobalNoInternetBanner(theme)
              else if (_showSyncCompleteBanner)
                _buildSyncCompleteBanner(theme)
              else if (_pendingSyncQueue.isNotEmpty)
                _buildQueuedSyncBanner(theme)
              // BNS 5 offline mode Banner
              else if (!userProvider.offlineModeEnabled)
                _buildGlobalOfflineBanner(context),

              // The actual tab content
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _navItems.length,
                  itemBuilder: (context, index) {
                    return _navItems[index].screen;
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: _buildGlobalFabs(),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: _buildBottomNavigationBar(),
        );
      },
    );
  }

  Widget _buildGlobalNoInternetBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.error, // Use a solid error color (usually Red)
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No Internet Connection.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCompleteBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: Colors.green.shade600,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sync complete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueuedSyncBanner(ThemeData theme) {
    return Material(
      color: Colors.blue.shade600,
      child: InkWell(
        onTap: () async {
          try {
            await Telemetry.event('button_tap', {
              'screen': 'queued_sync_banner',
              'button_name': 'open_queue_sheet',
            });
          } catch (_) {}

          _openQueuedSyncSheet();
        },
        child: const SizedBox(
          height: 44,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: _SpinningSyncIcon(
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openQueuedSyncSheet() {
    if (!mounted) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StreamBuilder<int>(
          stream: Stream<int>.periodic(const Duration(seconds: 1), (x) => x),
          builder: (context, _) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Queued Sync Items',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Human-readable, non-sensitive queue preview. Tap the trash icon to remove queued items you do not want to sync. Only the item currently syncing is locked.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _pendingSyncQueue.isEmpty
                          ? const Center(child: Text('No queued items'))
                          : ListView.separated(
                              itemCount: _pendingSyncQueue.length,
                              separatorBuilder: (_, i) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _pendingSyncQueue[index];
                                final isSyncing =
                                    item.id == _currentlySyncingRequestId;
                                final isFailed = _failedRequestIds.contains(
                                  item.id,
                                );
                                final status = isSyncing
                                    ? 'Syncing now'
                                    : isFailed
                                        ? 'Failed (will retry)'
                                        : 'Queued';

                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(item.displayTitle),
                                  subtitle: Text(
                                    '${item.displayDetails.join('\n')}\nQueued: ${_formatQueueTimestamp(item.createdAt)}\nStatus: $status${item.retryCount > 0 ? ' (${item.retryCount} retries)' : ''}',
                                  ),
                                  isThreeLine: false,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: isSyncing
                                        ? null
                                        : () => _deleteQueuedRequest(item),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteQueuedRequest(OfflineSyncQueueItem item) async {
    if (_currentlySyncingRequestId == item.id) {
      return;
    }
    final removed = await ApiService.deleteOfflineQueuedRequestById(
      item.id,
    );
    if (!mounted || !removed) {
      return;
    }
    setState(() {
      _pendingSyncQueue =
          _pendingSyncQueue.where((queued) => queued.id != item.id).toList();
      _failedRequestIds.remove(item.id);
    });
  }

  String _formatQueueTimestamp(DateTime value) {
    final local = value.toLocal();
    final twoDigitMonth = local.month.toString().padLeft(2, '0');
    final twoDigitDay = local.day.toString().padLeft(2, '0');
    final twoDigitHour = local.hour.toString().padLeft(2, '0');
    final twoDigitMinute = local.minute.toString().padLeft(2, '0');
    return '$twoDigitMonth/$twoDigitDay ${local.year} $twoDigitHour:$twoDigitMinute';
  }

  /// Build the global offline mode warning banner
  Widget _buildGlobalOfflineBanner(BuildContext context) {
    return MaterialBanner(
      elevation: 0,
      backgroundColor: Colors.amber.shade50,
      leading: Icon(Icons.cloud_off, color: Colors.amber.shade900),
      content: Text(
        'Offline Mode Disabled',
        style: TextStyle(
          color: Colors.amber.shade900,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            try {
              await Telemetry.event('button_tap', {
                'screen': 'offline_banner',
                'button_name': 'open_settings',
              });
            } catch (_) {}

            _onItemTapped(_navItems.length - 1);
          },
          child: Icon(
            Icons.settings,
            color: Colors.amber.shade900,
            size: 24, // Matches the standard emoji scale
          ),
        ),
      ],
    );
  }

  /// Build the bottom navigation bar
  Widget _buildBottomNavigationBar() {
    final t = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        selectedItemColor:
            _config.primaryColor ?? Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey[600],
        selectedFontSize: 12,
        unselectedFontSize: 12,
        iconSize: 24,
        items: _navItems.map((item) {
          return BottomNavigationBarItem(
            icon: _buildNavIcon(item, active: false),
            activeIcon: _buildNavIcon(item, active: true),
            label: item.localizedLabel(t),
          );
        }).toList(),
      ),
    );
  }
}

class _SpinningSyncIcon extends StatefulWidget {
  const _SpinningSyncIcon({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  State<_SpinningSyncIcon> createState() => _SpinningSyncIconState();
}

class _SpinningSyncIconState extends State<_SpinningSyncIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(
        Icons.sync,
        color: widget.color,
        size: widget.size,
      ),
    );
  }
}

/// Extension to provide easy navigation to specific tabs
extension MainScreenNavigation on BuildContext {
  void navigateToMainScreen({int? tabIndex, MainScreenConfig? config}) {
    Navigator.of(this).pushReplacement(
      MaterialPageRoute(
        builder: (context) =>
            MainScreen(initialTabIndex: tabIndex, config: config),
      ),
    );
  }

  void navigateToMainScreenWithConfig(
    MainScreenConfig config, {
    int? tabIndex,
  }) {
    Navigator.of(this).pushReplacement(
      MaterialPageRoute(
        builder: (context) =>
            MainScreen(initialTabIndex: tabIndex, config: config),
      ),
    );
  }
}

class _QuickCallTarget {
  final int userId;
  final String role;
  final String title;
  final String subtitle;
  final String? email;
  final String? phone;
  final List<int>? contextPatientUserIds;

  const _QuickCallTarget({
    required this.userId,
    required this.role,
    required this.title,
    required this.subtitle,
    this.email,
    this.phone,
    this.contextPatientUserIds,
  });

  bool get isCareTeamCall =>
      role.toUpperCase() == 'CAREGIVER' &&
      contextPatientUserIds != null &&
      contextPatientUserIds!.isNotEmpty;
}

class _CareTeamAggregate {
  final int userId;
  final String name;
  String? email;
  final Set<String> patientNames = <String>{};
  final Set<int> patientUserIds = <int>{};

  _CareTeamAggregate({
    required this.userId,
    required this.name,
    this.email,
  });
}
