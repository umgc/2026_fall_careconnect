import 'package:care_connect_app/widgets/page_title.dart';
import 'dart:convert';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../../../providers/user_provider.dart';
import 'chat_room_screen.dart';

/// A contact entry resolved from caregiver-patient links.
class _Contact {
  final int userId;
  final String name;
  final String email;
  final String role; // 'Patient' or 'Caregiver'

  _Contact({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
  });
}

class MyFriendsScreen extends StatefulWidget {
  const MyFriendsScreen({super.key});

  @override
  State<MyFriendsScreen> createState() => _MyFriendsScreenState();
}

class _MyFriendsScreenState extends State<MyFriendsScreen> {
  List<_Contact> _contacts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in')),
        );
        setState(() => isLoading = false);
        return;
      }
      _fetchContacts(user);
    });
  }

  Future<void> _fetchContacts(UserSession user) async {
    setState(() => isLoading = true);
    final headers = await ApiService.getAuthHeaders();

    try {
      if (user.role == 'CAREGIVER') {
        await _fetchPatientsForCaregiver(user, headers);
      } else {
        await _fetchCaregiversForPatient(user, headers);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load contacts: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// CAREGIVER path: GET /v1/api/caregivers/{caregiverId}/patients
  Future<void> _fetchPatientsForCaregiver(
    UserSession user,
    Map<String, String> headers,
  ) async {
    final caregiverId = user.caregiverId ?? user.id;
    final url = Uri.parse(
      '${getBackendBaseUrl()}/v1/api/caregivers/$caregiverId/patients',
    );
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      setState(() {
        _contacts = data
            .map((item) {
              // PatientWithLinkDto: { patient: {...}, link: {...} }
              final link = item['link'] as Map<String, dynamic>?;
              final patient = item['patient'] as Map<String, dynamic>?;
              if (link == null || patient == null) return null;

              final userId = (link['patientUserId'] as num?)?.toInt();
              if (userId == null) return null;

              final firstName = patient['firstName'] as String? ?? '';
              final lastName = patient['lastName'] as String? ?? '';
              final email = patient['email'] as String? ?? '';

              return _Contact(
                userId: userId,
                name: '$firstName $lastName'.trim(),
                email: email,
                role: 'Patient',
              );
            })
            .whereType<_Contact>()
            .toList();
      });
    } else {
      throw Exception('Status ${response.statusCode}');
    }
  }

  /// PATIENT path: GET /v1/api/caregiver-patient-links/patients/{userId}/caregivers
  Future<void> _fetchCaregiversForPatient(
    UserSession user,
    Map<String, String> headers,
  ) async {
    final url = Uri.parse(
      '${getBackendBaseUrl()}/v1/api/caregiver-patient-links/patients/${user.id}/caregivers',
    );
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      setState(() {
        _contacts = data
            .map((item) {
              // CaregiverPatientLinkResponse — only show if messaging is enabled
              final messagingEnabled =
                  item['patientMessagingEnabled'] as bool? ?? true;
              if (!messagingEnabled) return null;

              final userId = (item['caregiverUserId'] as num?)?.toInt();
              if (userId == null) return null;

              return _Contact(
                userId: userId,
                name: item['caregiverName'] as String? ?? 'Caregiver',
                email: item['caregiverEmail'] as String? ?? '',
                role: 'Caregiver',
              );
            })
            .whereType<_Contact>()
            .toList();
      });
    } else {
      throw Exception('Status ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? const Center(
                  child: Text(
                    'No contacts found.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: contact.role == 'Caregiver'
                            ? const Color(0xFF14366E)
                            : Colors.teal,
                        child: Text(
                          contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(contact.name),
                      subtitle: Text('${contact.role} · ${contact.email}'),
                      trailing: const Icon(Icons.chat_bubble_outline),
                      onTap: () {
                        Navigator.push(
                          context,
                          TitledMaterialPageRoute(
                            title: 'Conversation',
                            builder: (_) => ChatRoomScreen(
                              peerUserId: contact.userId,
                              peerName: contact.name,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
