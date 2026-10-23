import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'html_stub.dart' if (dart.library.html) 'dart:html' as html;

class _Contact {
  final String name;
  final String role;
  final String phone;
  final bool isPrimary = false;

  const _Contact({
    required this.name,
    required this.role,
    required this.phone,
  });
}

class EmergencyInfo {
  final String firstName;
  final String lastName;
  final String bloodType;
  final DateTime dob;
  final int age;
  final String gender;
  final String id;
  final List<String> allergiesCritical;
  final List<_Contact> contacts;
  final String secureToken;

  const EmergencyInfo({
    required this.firstName,
    required this.lastName,
    required this.bloodType,
    required this.dob,
    required this.age,
    required this.gender,
    required this.id,
    required this.allergiesCritical,
    required this.contacts,
    required this.secureToken,
  });

  String qrPayload() {
    final primaryContact = contacts.firstWhere(
      (c) => c.isPrimary,
      orElse: () => contacts.isNotEmpty
          ? contacts.first
          : const _Contact(name: 'None', role: '', phone: ''),
    );

    // Generate PNG image data URI
    return _generateEmergencyCardPng(primaryContact);
  }

  String _generateEmergencyCardPng(_Contact primaryContact) {
    // Plain text with no special formatting that could trigger app redirects
    return '''*** EMERGENCY MEDICAL INFO ***

PATIENT: $firstName $lastName
BLOOD: $bloodType
BORN: ${dob.toIso8601String().substring(0, 10)} AGE $age
GENDER: $gender
ID: $id

*** CRITICAL ALLERGIES ***
${allergiesCritical.isEmpty ? 'NONE REPORTED' : allergiesCritical.join(' - ')}

*** EMERGENCY CONTACT ***
${primaryContact.name}
PHONE: ${primaryContact.phone}

CREATED: ${DateTime.now().toIso8601String().substring(0, 10)}
FOR EMERGENCY PERSONNEL ONLY''';
  }
}

class QrScreen extends StatelessWidget {
  final String payload;
  final String? emergencyId;
  final int? patientId;

  // The base URL is now configurable via the BASE_URL environment variable.
  // Set it at build time with: flutter run --dart-define=BASE_URL=https://yourdomain.com
  // For development, it defaults to http://localhost:8080 if BASE_URL is not set.
  static const String _baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:8080');

  const QrScreen(
      {super.key, required this.payload, this.emergencyId, this.patientId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Information'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 260,
                  gapless: false,
                  backgroundColor: theme.colorScheme.surface,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: theme.colorScheme.onSurface,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 6),
              const SizedBox(height: 12),

              // Action buttons
              if (emergencyId != null)
                Column(
                  children: [
                    // View PDF Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _viewPdf(context),
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        label: const Text('View Emergency PDF'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Row with Download and Share buttons
                    Row(
                      children: [
                        // Download PDF Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _downloadPdf(context),
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Download Emergency PDF'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: theme.colorScheme.secondary,
                              foregroundColor: theme.colorScheme.onSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Share Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _shareEmergencyInfo(context),
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('Share Emergency Info'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: theme.colorScheme.tertiary,
                              foregroundColor: theme.colorScheme.onTertiary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Print PDF Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _printPdf(context),
                            icon: const Icon(Icons.print, size: 18),
                            label: const Text('Print Emergency PDF'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Get the PDF URL for viewing (inline)
  String _getPdfUrl() {
    return '$_baseUrl/v1/api/emergency/$emergencyId.pdf';
  }

  // Get the PDF URL for downloading (attachment)
  String _getDownloadPdfUrl() {
    return '$_baseUrl/v1/api/emergency/download/$emergencyId.pdf';
  }

  // View PDF in browser or in-app
  void _viewPdf(BuildContext context) async {
    if (emergencyId == null) return;

    final url = _getPdfUrl();

    try {
      if (kIsWeb) {
        // For web: Open PDF in new tab
        html.window.open(url, '_blank');
      } else {
        // For mobile: Use url_launcher with external browser
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot open PDF viewer'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error viewing PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Download PDF to device
  void _downloadPdf(BuildContext context) async {
    if (emergencyId == null) return;

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Downloading PDF...'),
            ],
          ),
        ),
      );

      // Download the PDF using the download endpoint
      final url = _getDownloadPdfUrl();
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        if (kIsWeb) {
          // For web: Trigger browser download
          final blob = html.Blob([response.bodyBytes]);
          final url = html.Url.createObjectUrlFromBlob(blob);
          // ignore: unused_local_variable
          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', 'emergency-$emergencyId.pdf')
            ..click();
          html.Url.revokeObjectUrl(url);

          // Close loading dialog
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PDF download started'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          // For mobile: Save to documents directory
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/emergency_$emergencyId.pdf');
          await file.writeAsBytes(response.bodyBytes);

          // Close loading dialog
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('PDF downloaded to: ${file.path}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to download PDF'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Print Emergency PDF
  void _printPdf(BuildContext context) async {
    if (emergencyId == null) return;

    final url = _getPdfUrl();

    try {
      if (kIsWeb) {
        // Web: open print dialog directly in new tab
        html.window.open('$url?print=true', '_blank');
      } else {
        // Mobile & Desktop: open system print dialog using OS viewer
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot open print dialog'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Share emergency information
  void _shareEmergencyInfo(BuildContext context) async {
    try {
      String shareText = payload;

      if (emergencyId != null) {
        shareText += '\n\nEmergency PDF: ${_getPdfUrl()}';
      }

      await Share.share(
        shareText,
        subject: 'Emergency Medical Information - $emergencyId',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
