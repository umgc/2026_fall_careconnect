import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:care_connect_app/widgets/language/language_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; 
import '../../../../config/env_constant.dart';
import 'package:provider/provider.dart';


class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _isLoading = true;
  bool _isBackendHealthy = true;

  @override
  void initState() {
    super.initState();
    _checkBackendHealth();
  }

  Future<void> _checkBackendHealth() async {
  try {
    final String baseUrl = getBackendBaseUrl();

    print('BASE URL: $baseUrl');

    final response = await http
        .get(Uri.parse('$baseUrl/v1/api/test/health'))
        .timeout(const Duration(seconds: 5));

    print('STATUS CODE: ${response.statusCode}');
    print('BODY: ${response.body}');

    if (mounted) {
      setState(() {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('PARSED STATUS: ${data['status']}');

          _isBackendHealthy = data['status'] == 'healthy';
        } else {
          _isBackendHealthy = false;
        }
      });
    }
  } catch (e) {
    print('ERROR: $e');

    if (mounted) {
      setState(() {
        _isBackendHealthy = false;
      });
    }
  } finally {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final t = AppLocalizations.of(context)!;
    final currentLocale = context.watch<LocaleProvider>().locale;
    final currentLangLabel = currentLocale == null
    ? t.systemDefault 
    : LanguagePicker.labelFor(currentLocale, t);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4A5FBF),
              Color(0xFF3B4DBF),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 24 : 48,
              vertical: isMobile ? 32 : 48,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => LanguagePicker.show(context),
                        icon: const Icon(Icons.language, color: Colors.white),
                        label: Text(
                          currentLangLabel,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: isMobile ? 12 : 14,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 10 : 12,
                            vertical: isMobile ? 6 : 8,
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 32 : 48),

                // Logo container
                Container(
                  width: isMobile ? 100 : 200,
                  height: isMobile ? 100 : 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/CareConnectLogo.png',
                          width: isMobile ? 90 : 190,
                          fit: BoxFit.contain,
                          color: Colors.white,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: isMobile ? 40 : 48),

                // Main title (brand name can stay as-is)
                Text(
                  'CareConnect',
                  style: TextStyle(
                    fontSize: isMobile ? 36 : 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: isMobile ? 12 : 16),
 
            // Subtitle
            Text(
              AppLocalizations.of(context)!.welcome_subtitle,
              style: TextStyle(
                fontSize: isMobile ? 18 : 20,
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: isMobile ? 32 : 40),

            // Description text
            Text(
              AppLocalizations.of(context)!.welcome_description,
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: isMobile ? 8 : 12),

            // Tagline
            Text(
              AppLocalizations.of(context)!.welcome_tagline,
              style: TextStyle(
                fontSize: isMobile ? 18 : 20,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),


                SizedBox(height: isMobile ? 40 : 48),

                // Loading state or ready message
                if (_isLoading) ...[
                  Text(
                    t.welcomeInitializingHealthcare,
                    style: TextStyle(
                      fontSize: isMobile ? 16 : 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isMobile ? 24 : 32),
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ] else ...[
                  Text(
                    t.welcomeReadyToConnect,
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isMobile ? 24 : 32),

                  // Backend health warning
                  if (!_isBackendHealthy) ...[
                    Container(
                      margin: EdgeInsets.only(bottom: isMobile ? 16 : 20),
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            color: Colors.orange[100],
                            size: isMobile ? 20 : 24,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              t.welcomeBackendNotHealthyWarning,
                              style: TextStyle(
                                fontSize: isMobile ? 14 : 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Continue button
                  ElevatedButton(
                    onPressed: () {
                      context.go('/dashboard');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4A5FBF),
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 32 : 40,
                        vertical: isMobile ? 16 : 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.welcomeContinue,
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  ],

                  SizedBox(height: isMobile ? 32 : 48),

                  // Compliance badges at bottom
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        _buildComplianceBadge(t.welcomeComplianceBadgeHipaa, isMobile),
                        _buildComplianceBadge(t.welcomeComplianceBadgeWcag, isMobile),
                        _buildComplianceBadge(t.welcomeComplianceBadgeSecure, isMobile),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComplianceBadge(String text, bool isMobile) {
    return Flexible(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 6 : 8,
          vertical: isMobile ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: isMobile ? 10 : 12,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
