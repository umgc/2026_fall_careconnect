import 'package:care_connect_app/widgets/page_title.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

/// Dashboard App header
class DashboardAppHeader extends StatelessWidget
    implements PreferredSizeWidget {
  @override
  final Size preferredSize;
  final String userName;
  final String? timezone;
  final String? profileImageUrl;
  final String role;

  DashboardAppHeader({
    super.key,
    required BuildContext context,
    required this.userName,
    required this.role,
    this.timezone,
    this.profileImageUrl = "",
  }) : preferredSize = _sizeFor(context, userName, role);

  static String get _formattedTime {
    final time = DateTime.now();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(time.month)}/${twoDigits(time.day)}/${time.year} '
        '${twoDigits(time.hour)}:${twoDigits(time.minute)} ${time.timeZoneName}';
  }

  static String _greeting(AppLocalizations t, String role) => role == 'PATIENT'
      ? t.appheaderwidget_greetingPt
      : t.appheaderwidget_greetingNonPt;

  static Size _sizeFor(BuildContext context, String userName, String role) {
    // Scaffold needs the same text metrics as the header before laying out its
    // body. Include wrapping, rather than multiplying a fixed height by scale.
    final t = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final width = (media.size.width - media.padding.horizontal - 40 - 65)
        .clamp(1.0, double.infinity);
    // Measure with the style the header text inherits inside the AppBar's
    // Material (the theme's bodyMedium, including its line height), not the
    // DefaultTextStyle around the Scaffold, which may lack that height.
    final baseStyle = Theme.of(context).textTheme.bodyMedium ??
        DefaultTextStyle.of(context).style;
    double textHeight(String text, double size, {FontWeight? weight}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: baseStyle.merge(
            TextStyle(fontSize: size, fontWeight: weight),
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: media.textScaler,
        locale: Localizations.localeOf(context),
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final welcomeHeight = textHeight(
          '${t.appheaderwidget_welcomeBack} $userName',
          22,
          weight: FontWeight.w600,
        ) +
        3 +
        textHeight(_formattedTime, 13) +
        2 +
        textHeight(_greeting(t, role), 13);
    return Size.fromHeight(
      (30 + 50 + 10 + welcomeHeight.clamp(50.0, double.infinity))
          .clamp(210.0, double.infinity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AppBar(
      excludeHeaderSemantics: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: preferredSize.height,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(25),
            bottomRight: Radius.circular(25),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row with logo and icons
                SizedBox(
                  height: 50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo section
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 35,
                              height: 35,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.local_hospital,
                                color: theme.colorScheme.onPrimary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                                child: Text(
                              "CARECONNECT",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                letterSpacing: 1.0,
                              ),
                            )),
                          ],
                        ),
                      ),
                      // Right icons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Emergency QR Icon
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              // DEF-EMG-24: the only way to the passport needs a name for screen
                              // readers (and a hint on hover and long press).
                              tooltip: t.appheaderwidget_medicalPassport,
                              // Opens the patient's passport (CC-12), where they choose what a
                              // first responder sees and open their QR code.
                              onPressed: () {
                                if (role == "PATIENT") {
                                  context.push('/medical-passport');
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            t.appheaderwidget_missingPtData)),
                                  );
                                }
                              },
                              icon: Icon(
                                Icons.local_hospital,
                                color: Colors.red,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Settings Icon
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: t.settings,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  TitledMaterialPageRoute(
                                    title: 'Settings',
                                    builder: (context) => const SettingsPage(),
                                  ),
                                );
                              },
                              icon: Icon(
                                Icons.settings_outlined,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Profile and welcome section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile avatar with online indicator
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundImage: profileImageUrl!.isNotEmpty
                              ? NetworkImage(profileImageUrl!)
                              : null,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          child: profileImageUrl!.isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 30,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.cardColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 15),

                    // Welcome text section
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            headingLevel: 1,
                            child: Text(
                              "${t.appheaderwidget_welcomeBack} $userName",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formattedTime,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _greeting(t, role),
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
