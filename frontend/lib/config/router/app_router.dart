import 'package:care_connect_app/features/dashboard/caregiver-dashboard/pages/caregiver-dashboard.dart';
import 'package:care_connect_app/features/fall_alert/pages/mock_alert_lab_page.dart';
import 'package:care_connect_app/features/fall_alert/pages/alert_details_page_patient.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/home_monitoring_screen.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/medication_management.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/smart_devices.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart';
import 'package:care_connect_app/features/notetaker/models/patient_note_model.dart';
import 'package:care_connect_app/features/notetaker/presentation/notetaker_detail_view.dart';
import 'package:care_connect_app/features/notetaker/presentation/notetaker_search.dart';
import 'package:care_connect_app/features/informed_delivery/informed_delivery_screen.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_tabbed_page.dart';
import 'package:care_connect_app/features/profile/presentation/pages/profile_settings_page.dart';
import 'package:care_connect_app/features/tasks/presentation/assign_task_screen.dart';
import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/tasks/presentation/custom_task_screen.dart';
import 'package:care_connect_app/features/tasks/presentation/pre_defined_task_screen.dart';
import 'package:care_connect_app/features/tasks/presentation/tasks_screen.dart';
import 'package:care_connect_app/pages/notetaker_configuration_page.dart';
import 'package:care_connect_app/pages/profile_page.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:care_connect_app/pages/ai_configuration_page.dart';
import 'package:care_connect_app/pages/file_management_page.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';
import 'package:care_connect_app/widgets/menu/menu_page.dart';
import 'package:care_connect_app/widgets/search/route_search_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../screens/main_screen.dart';
import '../../config/navigation/main_screen_config.dart';
import '../../config/navigation/navigation_helper.dart';
import '../../services/user_role_storage_service.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page_entry.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_detail_page.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/caregiver-patient-list.dart';
import '../../features/welcome/presentation/pages/welcome_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/oauth_callback_page.dart';
import '../../features/onboarding/presentation/pages/patient_registration.dart';
import '../../features/auth/presentation/pages/sign_up_screen.dart';
import '../../features/payments/presentation/pages/select_package_page.dart';
import '../../features/payments/presentation/pages/subscription_management_page.dart';
import '../../features/dashboard/presentation/pages/add_patient_screen.dart';
import '../../features/auth/presentation/pages/password_reset_page.dart';
import '../../features/auth/presentation/pages/reset_password_screen.dart'; // ADD THIS IMPORT
import '../../features/social/presentation/pages/main_feed_screen.dart';
import '../../features/gamification/presentation/pages/gamification_screen.dart';
import '../../features/payments/presentation/pages/native_billing_page.dart';
import '../../features/payments/presentation/pages/web_pay_page.dart';
import '../../features/payments/presentation/pages/subscription_tier_selection_page.dart';
import '../../features/analytics/analytics_page.dart';
import '../../features/payments/presentation/pages/payment_success_page.dart';
import '../../features/payments/presentation/pages/payment_cancel_page.dart';
import '../../features/dashboard/presentation/pages/patient_status_page.dart';
import '../../features/evv/presentation/pages/evv_corrections.dart';
import '../../features/evv/presentation/pages/evv_dashboard.dart';
import '../../features/evv/presentation/pages/evv_offline_sync.dart';
import '../../features/evv/presentation/pages/evv_record_review.dart';
import '../../features/evv/presentation/pages/evv_visit_history.dart';
import '../../features/evv/presentation/pages/patient_selection_page.dart';
import '../../features/evv/presentation/pages/start_visit_page.dart';
import '../../features/evv/presentation/pages/checkin_location_page.dart';
import '../../features/evv/presentation/pages/visit_in_progress_page.dart';
import '../../features/evv/presentation/pages/checkout_location_page.dart';
import '../../features/evv/presentation/pages/visit_complete_page.dart';
import '../../features/evv/presentation/pages/visit_completed_success_page.dart';
import '../../providers/user_provider.dart';
import 'package:care_connect_app/features/invoices/screens/invoice_detail_page.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/auth/presentation/pages/AlexaLoginPage.dart';
import '../../features/usps/presentation/usps_test_screen.dart';
import 'dart:convert';


/// Helper function to navigate to the appropriate dashboard based on stored user role
Future<void> navigateToDashboard(BuildContext context, {int? tabIndex}) async {
  await NavigationHelper.navigateToMainScreen(
    context,
    tabIndex: tabIndex,
    clearHistory: true,
  );
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const WelcomePage()),
    GoRoute(
      path: '/login',
      builder: (context, state) {
        final extra = state.extra;
        String? userType;

        if (extra != null &&
            extra is Map<String, dynamic> &&
            extra.containsKey('userType')) {
          userType = extra['userType'];
        }

        return LoginPage(userType: userType);
      },
    ),
    GoRoute(
      path: '/usps-test',
      name: 'uspsTest',
      builder: (context, state) => const UspsTestScreen(),
    ),

    GoRoute(
      path: '/signup',
      builder: (context, state) {
        // We're now using a single caregiver sign up screen
        return const RegistrationPage();
      },
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) {
        return FutureBuilder<UserData?>(
          future: UserRoleStorageService.instance.getUserData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final userData = snapshot.data;
            if (userData == null || !userData.isLoggedIn || userData.userId <= 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.go('/login');
              });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // Parse tab index from URL if provided
            final tabIndex = state.uri.queryParameters['tab'];
            int? initialTabIndex;
            if (tabIndex != null) {
              initialTabIndex = NavigationHelper.getTabIndexFromName(
                userData.role,
                tabIndex,
              );
            }

            // Create configuration based on stored role
            MainScreenConfig config;
            switch (userData.role.toUpperCase()) {
              case 'PATIENT':
                config = MainScreenConfig.forPatient(
                  userId: userData.userId,
                  patientId: userData.patientId,
                );
                break;
              case 'CAREGIVER':
                config = MainScreenConfig.forCaregiver(
                  userId: userData.userId,
                  caregiverId: userData.caregiverId,
                  patientId: userData.patientId,
                );
                break;
              case 'FAMILY_LINK':
                config = MainScreenConfig.forFamilyMember(
                  userId: userData.userId,
                  patientId: userData.patientId,
                );
                break;
              case 'ADMIN':
                config = MainScreenConfig(
                  userRole: 'ADMIN',
                  userId: userData.userId,
                  showAppBar: true,
                  appBarTitle: 'Admin Dashboard',
                  primaryColor: Colors.red,
                );
                break;
              default:
                // Unknown role, redirect to login
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  context.go('/login');
                });
                return const Scaffold(
                  body: Center(
                    child: Text('Unknown user role. Redirecting to login...'),
                  ),
                );
            }

            return MainScreen(
              config: config,
              initialTabIndex: initialTabIndex,
            );
          },
        );
      },
    ),
    GoRoute(
      path: '/dashboard/patient',
      builder: (context, state) {
        final userIdStr = state.uri.queryParameters['userId'];
        final userId = userIdStr != null ? int.tryParse(userIdStr) : null;

        // Check if userId is valid
        if (userId == null || userId <= 0) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Invalid user ID'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Go to Login'),
                  ),
                ],
              ),
            ),
          );
        }

        // Redirect to new MainScreen with patient configuration
        final config = MainScreenConfig.forPatient(
          userId: userId,
          patientId: userId,
        );

        return MainScreen(config: config);
      },
    ),

    // Caregiver dashboard route (backend redirects)
    GoRoute(
      path: '/dashboard/caregiver',
      builder: (context, state) {
        final caregiverIdStr = state.uri.queryParameters['caregiverId'];
        final patientIdStr = state.uri.queryParameters['patientId'];

        final caregiverId = caregiverIdStr != null
            ? int.tryParse(caregiverIdStr)
            : null;
        final patientId = patientIdStr != null
            ? int.tryParse(patientIdStr)
            : null;

        // Check if caregiverId is valid
        if (caregiverId == null || caregiverId <= 0) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Invalid caregiver ID'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Go to Login'),
                  ),
                ],
              ),
            ),
          );
        }

        // Redirect to new MainScreen with caregiver configuration
        final config = MainScreenConfig.forCaregiver(
          userId: caregiverId,
          caregiverId: caregiverId,
          patientId: patientId,
        );

        return MainScreen(config: config);
      },
    ),
    // Direct caregiver dashboard route (for specific caregiver dashboard view)
    GoRoute(
      path: '/caregiver-dashboard',
      builder: (context, state) {
        final caregiverIdStr = state.uri.queryParameters['caregiverId'];
        final patientIdStr = state.uri.queryParameters['patientId'];

        final caregiverId = caregiverIdStr != null ? int.tryParse(caregiverIdStr) : null;
        final patientId = patientIdStr != null ? int.tryParse(patientIdStr) : null;

        if (caregiverId == null || caregiverId <= 0) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Invalid caregiver ID'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Go to Login'),
                  ),
                ],
              ),
            ),
          );
        }

        return const CaregiverDashboard();
      },
    ),
    // Add a redirect route for authenticated users going to root
    GoRoute(
      path: '/home',
      redirect: (context, state) async {
        final isLoggedIn = await UserRoleStorageService.instance.isLoggedIn();
        if (isLoggedIn) {
          return '/dashboard';
        }
        return '/';
      },
    ),
    GoRoute(
      path: '/register/caregiver',
      builder: (_, __) => const RegistrationPage(),
    ),
    // TODO - Update Subscription page
    // GoRoute(
    //   path: '/register/caregiver/payment',
    //   builder: (_, __) => const CaregiverRegistrationFlowPage(),
    // ),
    GoRoute(
      path: '/register/patient',
      builder: (_, __) => const PatientRegistrationPage(),
    ),
    GoRoute(path: '/add-patient', builder: (_, __) => const AddPatientScreen()),
    GoRoute(
      path: '/social-feed',
      builder: (context, state) {
        final userIdStr = state.uri.queryParameters['userId'];
        final userId = userIdStr != null ? int.tryParse(userIdStr) : 1;
        return MainFeedScreen(userId: userId ?? 1);
      },
    ),
    GoRoute(
      path: '/select-package',
      builder: (context, state) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final user = userProvider.user;
        final userId = state.uri.queryParameters['userId'];

        if (userId != null ||
            (user != null && user.role.toUpperCase() == 'PATIENT')) {
          return SelectPackagePage(userId: userId);
        } else {
          return const SubscriptionManagementPage();
        }
      },
    ),
    GoRoute(
      path: '/reset-password',
      builder: (_, __) => const ResetPasswordScreen(),
    ),
    GoRoute(
      path: '/subscription',
      builder: (_, __) => const SubscriptionManagementPage(),
    ),
    GoRoute(
      path: '/setup-password',
      builder: (context, state) {
        final token = state.uri.queryParameters['token'];
        // Add redirect if no token
        if (token == null || token.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Invalid or missing reset token'),
                  SizedBox(height: 16),
                  BackButton(color: Colors.blue),
                ],
              ),
            ),
          );
        }
        return PasswordResetPage(token: token);
      },
    ),
    // FIX: Remove duplicate, keep only one gamification route
    GoRoute(
      path: '/gamification',
      builder: (_, __) => const GamificationScreen(),
    ),
    GoRoute(
      path: '/stripe-checkout',
      redirect: (_, __) => '/select-package',
    ),
    GoRoute(
      path: '/native-billing',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final tierId = extra?['tierId'] as int? ?? 0;
        final tier = extra?['tier'] as String?;
        final userId = extra?['userId'] as int?;
        return NativeBillingPage(tierId: tierId, tier: tier, userId: userId);
      },
    ),
    GoRoute(
      path: '/select-subscription-tier',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final email = extra?['email'] as String?;
        final userState = extra?['state'] as String?;
        return SubscriptionTierSelectionPage(email: email, userState: userState);
      },
    ),
    GoRoute(
      path: '/web-pay',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final tierId = extra?['tierId'] as int?;
        final tier = extra?['tier'] as String?;
        final email = extra?['email'] as String?;
        final userId = extra?['userId'] as int?;
        final userState = extra?['state'] as String?;
        return WebPayPage(
          tierId: tierId ?? 0,
          tier: tier,
          email: email,
          userId: userId,
          state: userState,
        );
      },
    ),
    GoRoute(
      path: '/payment-success',
      builder: (context, state) {
        final sessionId = state.uri.queryParameters['session_id'];
        final isRegistration =
            state.uri.queryParameters['registration'] == 'complete';
        final fromPortal = state.uri.queryParameters['portal'] == 'update';
        return PaymentSuccessPage(
          sessionId: sessionId,
          isRegistration: isRegistration,
          fromPortal: fromPortal,
        );
      },
    ),
    GoRoute(
      path: '/payment-cancel',
      builder: (context, state) {
        final isRegistration =
            state.uri.queryParameters['registration'] == 'complete';
        return PaymentCancelPage(isRegistration: isRegistration);
      },
    ),
    GoRoute(
      path: '/patient/:id',
      builder: (context, state) {
        final idStr = state.pathParameters['id'];
        final patientId = int.tryParse(idStr ?? '');

        if (patientId == null) {
          // Instead of showing an error screen, redirect back to dashboard
          final userProvider = Provider.of<UserProvider>(
            context,
            listen: false,
          );
          final userRole = userProvider.user?.role;

          // Show error message but stay logged in
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Invalid patient ID')));

            // Redirect to appropriate dashboard based on role
            if (userRole != null) {
              Future.delayed(const Duration(milliseconds: 500), () {
                context.go('/dashboard');
              });
            }
          });

          return Scaffold(
            appBar: AppBar(
              title: const Text('Redirecting...'),
              backgroundColor: const Color(0xFF14366E),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return PatientStatusPage(patientId: patientId);
      },
    ),
    GoRoute(
      path: '/analytics',
      builder: (context, state) {
        final patientIdStr = state.uri.queryParameters['patientId'];
        if (patientIdStr == null || int.tryParse(patientIdStr) == null) {
          // Instead of showing an error screen, redirect back to dashboard
          final userProvider = Provider.of<UserProvider>(
            context,
            listen: false,
          );
          final userRole = userProvider.user?.role;

          // Show error message but stay logged in
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid or missing patient ID')),
            );

            // Redirect to appropriate dashboard based on role
            if (userRole != null) {
              Future.delayed(const Duration(milliseconds: 500), () {
                context.go('/dashboard');
              });
            }
          });

          return Scaffold(
            appBar: AppBar(
              title: const Text('Redirecting...'),
              backgroundColor: const Color(0xFF14366E),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final patientId = int.tryParse(patientIdStr);
        if (patientId == null) {
          return const Scaffold(
            body: Center(child: Text('Invalid patientId.')),
          );
        }
        return AnalyticsPage(patientId: patientId);
      },
    ),
    GoRoute(
      path: '/oauth/callback',
      builder: (context, state) {
        final token = state.uri.queryParameters['token'];
        final user = state.uri.queryParameters['user'];
        final error = state.uri.queryParameters['error'];
        return OAuthCallbackPage(token: token, user: user, error: error);
      },
    ),
    GoRoute(path: '/wearables', builder: (_, __) => const WearablesScreen()),
    GoRoute(
      path: '/home-monitoring',
      builder: (_, __) => const HomeMonitoringScreen(),
    ),
    GoRoute(
      path: '/smart-devices',
      builder: (_, __) => const SmartDevicesPage(),
    ),
    GoRoute(
      path: '/medication',
      builder: (_, __) => const MedicationManagementScreen(),
    ),
    
    // EVV Routes
    GoRoute(
      path: '/evv',
      builder: (_, __) => const EvvDashboard(),
    ),
    GoRoute(
      path: '/evv/select-patient',
      builder: (_, __) => const PatientSelectionPage(),
    ),
    GoRoute(
      path: '/evv/start-visit',
      builder: (context, state) {
        final patientId = int.tryParse(state.uri.queryParameters['patientId'] ?? '');
        if (patientId == null) {
          return const Scaffold(
            body: Center(child: Text('Invalid patient ID')),
          );
        }
        return StartVisitPage(patientId: patientId);
      },
    ),
    GoRoute(
      path: '/evv/checkin-location',
      builder: (context, state) {
        final patientId = int.tryParse(state.uri.queryParameters['patientId'] ?? '');
        final serviceType = state.uri.queryParameters['serviceType'] ?? '';
        if (patientId == null || serviceType.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Invalid parameters')),
          );
        }
        return CheckinLocationPage(
          patientId: patientId,
          serviceType: serviceType,
        );
      },
    ),
    GoRoute(
      path: '/evv/visit-progress',
      builder: (context, state) {
        final patientId = int.tryParse(state.uri.queryParameters['patientId'] ?? '');
        final serviceType = state.uri.queryParameters['serviceType'] ?? '';
        final locationType = state.uri.queryParameters['locationType'] ?? '';
        final latitude = double.tryParse(state.uri.queryParameters['latitude'] ?? '');
        final longitude = double.tryParse(state.uri.queryParameters['longitude'] ?? '');
        final noGpsReason = state.uri.queryParameters['noGpsReason'];
        final accuracyM = double.tryParse(state.uri.queryParameters['accuracyM'] ?? '');
        
        if (patientId == null || serviceType.isEmpty || locationType.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Invalid parameters')),
          );
        }
        
        return VisitInProgressPage(
          patientId: patientId,
          serviceType: serviceType,
          locationType: locationType,
          latitude: latitude,
          longitude: longitude,
          noGpsReason: noGpsReason,
          accuracyM: accuracyM,
        );
      },
    ),
    GoRoute(
      path: '/evv/checkout-location',
      builder: (context, state) {
        final patientId = int.tryParse(state.uri.queryParameters['patientId'] ?? '');
        final serviceType = state.uri.queryParameters['serviceType'] ?? '';
        final locationType = state.uri.queryParameters['locationType'] ?? '';
        final latitude = double.tryParse(state.uri.queryParameters['latitude'] ?? '');
        final longitude = double.tryParse(state.uri.queryParameters['longitude'] ?? '');
        final notes = state.uri.queryParameters['notes'] ?? '';
        final duration = int.tryParse(state.uri.queryParameters['duration'] ?? '0') ?? 0;
        final checkinNoGpsReason = state.uri.queryParameters['checkinNoGpsReason'];
        final checkinAccuracyM = double.tryParse(state.uri.queryParameters['checkinAccuracyM'] ?? '');
        final scheduledVisitId = int.tryParse(state.uri.queryParameters['scheduledVisitId'] ?? '');
        
        if (patientId == null || serviceType.isEmpty || locationType.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Invalid parameters')),
          );
        }
        
        return CheckoutLocationPage(
          patientId: patientId,
          serviceType: serviceType,
          locationType: locationType,
          latitude: latitude,
          longitude: longitude,
          notes: notes,
          duration: duration,
          checkinNoGpsReason: checkinNoGpsReason,
          checkinAccuracyM: checkinAccuracyM,
          scheduledVisitId: scheduledVisitId,
        );
      },
    ),
    GoRoute(
      path: '/evv/visit-complete',
      builder: (context, state) {
        final patientId = int.tryParse(state.uri.queryParameters['patientId'] ?? '');
        final serviceType = state.uri.queryParameters['serviceType'] ?? '';
        final checkinLocationType = state.uri.queryParameters['checkinLocationType'] ?? '';
        final checkoutLocationType = state.uri.queryParameters['checkoutLocationType'] ?? '';
        final checkinLatitude = double.tryParse(state.uri.queryParameters['checkinLatitude'] ?? '');
        final checkinLongitude = double.tryParse(state.uri.queryParameters['checkinLongitude'] ?? '');
        final checkoutLatitude = double.tryParse(state.uri.queryParameters['checkoutLatitude'] ?? '');
        final checkoutLongitude = double.tryParse(state.uri.queryParameters['checkoutLongitude'] ?? '');
        final notes = state.uri.queryParameters['notes'] ?? '';
        final duration = int.tryParse(state.uri.queryParameters['duration'] ?? '0') ?? 0;
        final checkinNoGpsReason = state.uri.queryParameters['checkinNoGpsReason'];
        final checkoutNoGpsReason = state.uri.queryParameters['checkoutNoGpsReason'];
        final checkinAccuracyM = double.tryParse(state.uri.queryParameters['checkinAccuracyM'] ?? '');
        final checkoutAccuracyM = double.tryParse(state.uri.queryParameters['checkoutAccuracyM'] ?? '');
        final scheduledVisitId = int.tryParse(state.uri.queryParameters['scheduledVisitId'] ?? '');
        
        if (patientId == null || serviceType.isEmpty || checkinLocationType.isEmpty || checkoutLocationType.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Invalid parameters')),
          );
        }
        
        return VisitCompletePage(
          patientId: patientId,
          serviceType: serviceType,
          checkinLocationType: checkinLocationType,
          checkoutLocationType: checkoutLocationType,
          checkinLatitude: checkinLatitude,
          checkinLongitude: checkinLongitude,
          checkoutLatitude: checkoutLatitude,
          checkoutLongitude: checkoutLongitude,
          notes: notes,
          duration: duration,
          checkinNoGpsReason: checkinNoGpsReason,
          checkoutNoGpsReason: checkoutNoGpsReason,
          checkinAccuracyM: checkinAccuracyM,
          checkoutAccuracyM: checkoutAccuracyM,
          scheduledVisitId: scheduledVisitId,
        );
      },
    ),
    GoRoute(
      path: '/evv/visit-completed-success',
      builder: (context, state) {
        final patientId = int.tryParse(state.uri.queryParameters['patientId'] ?? '');
        final serviceType = state.uri.queryParameters['serviceType'] ?? '';
        final checkinLocationType = state.uri.queryParameters['checkinLocationType'] ?? '';
        final checkoutLocationType = state.uri.queryParameters['checkoutLocationType'] ?? '';
        final checkinLatitude = double.tryParse(state.uri.queryParameters['checkinLatitude'] ?? '');
        final checkinLongitude = double.tryParse(state.uri.queryParameters['checkinLongitude'] ?? '');
        final checkoutLatitude = double.tryParse(state.uri.queryParameters['checkoutLatitude'] ?? '');
        final checkoutLongitude = double.tryParse(state.uri.queryParameters['checkoutLongitude'] ?? '');
        final notes = state.uri.queryParameters['notes'] ?? '';
        final duration = int.tryParse(state.uri.queryParameters['duration'] ?? '0') ?? 0;
        final checkinTimeStr = state.uri.queryParameters['checkinTime'] ?? '';
        final checkoutTimeStr = state.uri.queryParameters['checkoutTime'] ?? '';
        
        if (patientId == null || serviceType.isEmpty || checkinLocationType.isEmpty || checkoutLocationType.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Invalid parameters')),
          );
        }
        
        // Parse times - fallback to current time if parsing fails
        DateTime checkinTime;
        DateTime checkoutTime;
        try {
          checkinTime = DateTime.parse(checkinTimeStr);
        } catch (e) {
          checkinTime = DateTime.now().subtract(Duration(seconds: duration));
        }
        try {
          checkoutTime = DateTime.parse(checkoutTimeStr);
        } catch (e) {
          checkoutTime = DateTime.now();
        }
        
        return VisitCompletedSuccessPage(
          patientId: patientId,
          serviceType: serviceType,
          checkinLocationType: checkinLocationType,
          checkoutLocationType: checkoutLocationType,
          checkinLatitude: checkinLatitude,
          checkinLongitude: checkinLongitude,
          checkoutLatitude: checkoutLatitude,
          checkoutLongitude: checkoutLongitude,
          notes: notes,
          duration: duration,
          checkinTime: checkinTime,
          checkoutTime: checkoutTime,
        );
      },
    ),
    GoRoute(
      path: '/evv/review-records',
      builder: (_, __) => const EvvRecordReviewPage(),
    ),
    GoRoute(
      path: '/evv/visit-history',
      builder: (_, __) => const EvvVisitHistoryPage(),
    ),
    GoRoute(
      path: '/evv/corrections',
      builder: (_, __) => const EvvCorrectionsPage(),
    ),
    GoRoute(
      path: '/evv/offline-sync',
      builder: (_, __) => const EvvOfflineSyncPage(),
    ),
    GoRoute(
      path: '/profile-settings',
      builder: (_, __) => const ProfileSettingsPage(),
    ),
    GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
    GoRoute(
      path: '/file-management',
      builder: (_, __) => const FileManagementPage(),
    ),
    GoRoute(
      path: '/ai-configuration',
      builder: (_, __) => const AIConfigurationPage(),
    ),
    GoRoute(
      path: '/notetaker-configuration',
      builder: (_, __) => const NotetakerConfigurationPage(),
    ),
    GoRoute(
      path: "/notetaker-search",
      builder: (_, __) => const NotetakerSearchPage(),
    ),
    GoRoute(
      path: "/notetaker/detail/:noteId",
      builder: (context, state) {
        final noteId = state.pathParameters['noteId'];
        final extra = state.extra;
        if (noteId == null || extra == null || extra is! PatientNote) {
          return const Scaffold(
            body: Center(child: Text('Invalid note ID or missing note data')),
          );
        }
        final note = extra;
        return NotetakerDetailView();
      },
    ),

    // Team A Chime + Bedrock sentiment test route
    GoRoute(
      path: '/video-call-chime',
      builder: (context, state) {
        final userId = state.uri.queryParameters['userId'] ?? '1';
        final callId = state.uri.queryParameters['callId'] ??
            'chime_call_${DateTime.now().millisecondsSinceEpoch}';
        final recipientId = state.uri.queryParameters['recipientId'];
        final isVideoEnabled =
            (state.uri.queryParameters['video'] ?? 'true').toLowerCase() !=
                'false';
        final isAudioEnabled =
            (state.uri.queryParameters['audio'] ?? 'true').toLowerCase() !=
                'false';
        final isInitiator =
            (state.uri.queryParameters['initiator'] ?? 'false').toLowerCase() ==
                'true';

        return HybridVideoCallWidget(
          userId: userId,
          callId: callId,
          recipientId: recipientId,
          userRole: state.uri.queryParameters['userRole'],
          isVideoEnabled: isVideoEnabled,
          isAudioEnabled: isAudioEnabled,
          isInitiator: isInitiator,
          userName: state.uri.queryParameters['userName'],
          recipientName: state.uri.queryParameters['recipientName'],
          returnPatientDetailsId:
              state.uri.queryParameters['returnPatientDetailsId'],
          forcePatientDetailsOnExit:
              (state.uri.queryParameters['forcePatientDetailsOnExit'] ?? 'false')
                      .toLowerCase() ==
                  'true',
          returnAsCaregiver:
              (state.uri.queryParameters['returnAsCaregiver'] ?? 'false')
                      .toLowerCase() ==
                  'true',
        );
      },
    ),

    //Adding Calendar Assistant route
    GoRoute(
      path: '/calendar',
      builder: (_, __) => const CalendarAssistantScreen(),
    ),
    GoRoute(
      path: '/virtual-checkin',
      builder: (context, state) => const PatientVirtualCheckIn(),
    ),
    GoRoute(
      path: '/checkin-detail/:checkInId',
      builder: (context, state) {
        final checkInId = int.tryParse(state.pathParameters['checkInId'] ?? '');

        if (checkInId == null) {
          return const Scaffold(
            body: Center(child: Text('Invalid check-in ID')),
          );
        }

        // Prefer questions passed via state.extra (in-app navigation).
        // Fall back to query parameter for deep links / web URLs.
        List<BackendQuestionDto> questions = [];
        final extra = state.extra;
        if (extra is List<BackendQuestionDto>) {
          questions = extra;
        } else {
          final questionsJson = state.uri.queryParameters['questions'] ?? '[]';
          try {
            final decoded = jsonDecode(questionsJson);
            if (decoded is List) {
              questions = (decoded as List<dynamic>)
                  .map((q) => BackendQuestionDto.fromJson(q as Map<String, dynamic>))
                  .toList();
            }
          } catch (e) {
            // Failed to parse questions; continue with empty list
          }
        }

        return PatientCheckInDetailPage(
          checkInId: checkInId,
          questions: questions,
        );
      },
    ),
        //Adding Alexa login route
     GoRoute(
      path: '/alexaLogin',
      builder: (context, state){
        return const AlexaLoginPage();
      },
    ),
    GoRoute(
      path: '/alexaLogin/:redirectUri/:state',
      builder: (context, state) {
    final redirectUri = state.pathParameters['redirectUri'];
    final oauthState = state.pathParameters['state'];
    return AlexaLoginPage(
      key: ValueKey('alexaLoginPage'),
      // optionally pass them into your widget if you modify its constructor
    );
  },
),

    //Adding Informed Delivery route
    GoRoute(
      path: '/informed-delivery',
      builder: (_, __) => const InformedDeliveryScreen(),
    ),
    // Handle routes from legacy menus
    GoRoute(
      path: '/tasks',
      builder: (context, state) => const CaregiverPatientList(),
    ),
    GoRoute(
      path: '/taskscheduling',
      redirect: (context, state) async {
        final userData = await UserRoleStorageService.instance.getUserData();
        if (userData?.isLoggedIn == true) {
          // Redirect to tasks tab for caregivers, home for patients
          if (userData!.role.toUpperCase() == 'CAREGIVER') {
            return '/dashboard?tab=tasks';
          }
          return '/dashboard?tab=home';
        }
        return '/login';
      },
    ),
    GoRoute(
      path: '/chatandcalls',
      redirect: (context, state) async {
        final isLoggedIn = await UserRoleStorageService.instance.isLoggedIn();
        if (isLoggedIn) {
          return '/dashboard?tab=messages';
        }
        return '/login';
      },
    ),
    GoRoute(
      path: '/aiassistant',
      redirect: (context, state) async {
        final isLoggedIn = await UserRoleStorageService.instance.isLoggedIn();
        if (isLoggedIn) {
          return '/dashboard?tab=home';
        }
        return '/login';
      },
    ),
    GoRoute(
      path: '/fitbit',
      redirect: (context, state) {
        return '/wearables';
      },
    ),
    GoRoute(
      path: '/sos',
      redirect: (context, state) async {
        final isLoggedIn = await UserRoleStorageService.instance.isLoggedIn();
        if (isLoggedIn) {
          return '/dashboard?tab=home';
        }
        return '/login';
      },
    ),
    GoRoute(
      path: '/patient-tasks',
      builder: (context, state) {
        final patientIdStr = state.uri.queryParameters['patientId'];
        final patientId = int.tryParse(patientIdStr ?? '0') ?? 0;
        final patientName =
            state.uri.queryParameters['patientName'] ?? 'Name Not Found';
        // Return the Tasks widget with the patientId
        return TasksScreen(patientId: patientId, patientName: patientName);
      },
    ),
    GoRoute(
      path: '/assign-task',
      builder: (context, state) {
        final patientIdStr = state.uri.queryParameters['patientId'];
        final patientId = int.tryParse(patientIdStr ?? '0') ?? 0;
        final patientName =
            state.uri.queryParameters['patientName'] ?? 'Name Not Found';
        return AssignTaskScreen(patientId: patientId, patientName: patientName);
      },
    ),
    GoRoute(
      path: '/custom-task-scheduling',
      builder: (context, state) {
        final patientIdStr = state.uri.queryParameters['patientId'];
        final patientId = int.tryParse(patientIdStr ?? '0') ?? 0;
        final patientName =
            state.uri.queryParameters['patientName'] ?? 'Name Not Found';
        return CustomTaskScreen(patientId: patientId, patientName: patientName);
      },
    ),
    
    
    GoRoute(
      path: '/pre-defined-task',
      builder: (context, state) {
        final patientIdStr = state.uri.queryParameters['patientId'];
        final patientId = int.tryParse(patientIdStr ?? '0') ?? 0;
        final templateIdStr = state.uri.queryParameters['templateId'];
        final templateId = int.tryParse(templateIdStr ?? '0') ?? 0;
        final patientName =
            state.uri.queryParameters['patientName'] ?? 'Name Not Found';
        return PreDefinedTaskScreen(
          patientId: patientId,
          templateId: templateId,
          patientName: patientName,
        );
      },
    ),

    GoRoute(
      path: '/invoice-assistant',
      redirect: (context, state) {
        // redirect only if the path is exactly /invoice-assistant
        if (state.uri.toString() == '/invoice-assistant') {
          return '/invoice-assistant/upload';
        }
        return null;
      },
      routes: [ 
         GoRoute(
          path: 'dashboard',
          name: 'invoiceDashboard',
          builder: (context, state) => const InvoiceTabbedPage(initialTabIndex: 0),
        ),
        GoRoute(
          path: 'upload',
          name: 'invoiceUpload',
          builder: (context, state) => const InvoiceTabbedPage(initialTabIndex: 1),
        ),
        GoRoute(
          path: 'list',
          name: 'invoiceList',
          builder: (context, state) => const InvoiceTabbedPage(initialTabIndex: 2),
          routes: [
            GoRoute(
              path: ':filter',
              name: 'invoiceListFiltered',
              builder: (context, state) => InvoiceTabbedPage(
                initialTabIndex: 2,
                quickFilter: state.pathParameters['filter'],
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'detail/:id',
          name: 'invoiceDetail',
          builder: (context, state) {
            final invoice = state.extra as Invoice;
            return InvoiceDetailPage(invoice: invoice);
          },
        ),       
        
      ],
    ),
        GoRoute(
          path: 'menu',
          name: 'menupage',
          builder: (context, state) => const MenuPage(),
        ),
        GoRoute(
          path: '/alertpage',
          builder: (context, state) => const MockAlertLabPage(),
        ),
          GoRoute(
          path: '/alertpage-patient',
          builder: (context, state) => const PatientFallPromptPage(),
        ),
        GoRoute(path: '/search', builder: (_, __) => const RouteSearchPage()),

  ],
);
