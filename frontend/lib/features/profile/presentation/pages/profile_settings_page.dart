import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/widgets/profile_picture_widget.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/services/profile_service.dart';
import 'package:go_router/go_router.dart';
import '../../models/profile_model.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  _ProfileSettingsPageState createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  dynamic _userProfile;
  bool _isPatient = false;
  bool _isCaregiver = false;

  final _formKey = GlobalKey<FormState>();

  // Common text controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _countryController = TextEditingController();

  // Caregiver specific controllers
  final _specializationController = TextEditingController();
  final _organizationController = TextEditingController();
  final _licenseController = TextEditingController();

  // Patient specific controllers
  final _dateOfBirthController = TextEditingController();
  final _genderController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _medicalConditionsController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _medicationsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    // Dispose all controllers
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    _countryController.dispose();

    _specializationController.dispose();
    _organizationController.dispose();
    _licenseController.dispose();

    _dateOfBirthController.dispose();
    _genderController.dispose();
    _emergencyContactController.dispose();
    _medicalConditionsController.dispose();
    _allergiesController.dispose();
    _medicationsController.dispose();

    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userSession = await AuthTokenManager.getUserSession();
      if (userSession == null || userSession['id'] == null) {
        throw Exception('User session not found');
      }

      final userRole = userSession['role'] as String? ?? '';

      setState(() {
        _isPatient = userRole.toUpperCase() == 'PATIENT';
        _isCaregiver =
            userRole.toUpperCase() == 'CAREGIVER' ||
            userRole.toUpperCase() == 'FAMILY_LINK' ||
            userRole.toUpperCase() == 'ADMIN';
      });

      // Use the new ProfileService to get complete profile data
      Map<String, dynamic>? profileData;

      if (_isCaregiver) {
        final caregiverId = userSession['caregiverId'] as int?;
        if (caregiverId == null) {
          throw Exception('Caregiver ID not found in user session');
        }
        profileData = await ProfileService.getCaregiverProfile(caregiverId);
      } else if (_isPatient) {
        final patientId = userSession['patientId'] as int?;
        if (patientId == null) {
          throw Exception('Patient ID not found in user session');
        }
        profileData = await ProfileService.getPatientProfile(patientId);
      } else {
        throw Exception('Unknown user role: $userRole');
      }

      if (profileData != null) {
        final parsedData = await _parseResponse(profileData);
        setState(() {
          if (_isCaregiver) {
            _userProfile = CaregiverProfile.fromJson(parsedData);
            _populateCaregiverFields();
          } else {
            _userProfile = PatientProfile.fromJson(parsedData);
            _populatePatientFields();
          }
        });
      } else {
        throw Exception('Failed to load profile data');
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load profile: $e';
      });
      print('Error in _loadUserProfile: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper to parse the API response
  dynamic _parseResponse(dynamic data) {
    try {
      if (data == null || data.isEmpty) {
        return {};
      }

      // If data is already a Map, it's from ProfileService
      if (data is Map<String, dynamic>) {
        final rawData = data;

        // Transform the API response structure to match our model expectations
        if (_isCaregiver) {
          // Defensive extraction of professional info fields
          final professional = rawData['professional'] ?? {};
          return {
            'id': rawData['id'] ?? 0,
            'name': '${rawData['firstName'] ?? ''} ${rawData['lastName'] ?? ''}'
                .trim(),
            'email': rawData['email'] ?? '',
            'phoneNumber': rawData['phone'] ?? '',
            'address': rawData['address']?['line1'] ?? '',
            'city': rawData['address']?['city'] ?? '',
            'state': rawData['address']?['state'] ?? '',
            'zipCode': rawData['address']?['zip'] ?? '',
            'country': '', // Default to empty as it's not in the response
            // Professional info fields
            'specialization':
                professional['specialization'] ??
                professional['specialty'] ??
                professional['yearsExperience']?.toString() ??
                '',
            'organization':
                rawData['caregiverType'] ?? professional['organization'] ?? '',
            'license':
                professional['licenseNumber'] ?? professional['license'] ?? '',
            'dateOfBirth': rawData['dob'] ?? '',
            'profilePictureUrl':
                rawData['profileImageUrl'] ?? rawData['profilePictureUrl'],
          };
        } else if (_isPatient) {
          return {
            'id': rawData['id'] ?? 0,
            'name': '${rawData['firstName'] ?? ''} ${rawData['lastName'] ?? ''}'
                .trim(),
            'email': rawData['email'] ?? '',
            'phoneNumber': rawData['phone'] ?? '',
            'address': rawData['address']?['line1'] ?? '',
            'city': rawData['address']?['city'] ?? '',
            'state': rawData['address']?['state'] ?? '',
            'zipCode': rawData['address']?['zip'] ?? '',
            'country': '', // Default to empty as it's not in the response
            'dateOfBirth': rawData['dob'] ?? '',
            'gender': rawData['gender'] ?? '',
            'emergencyContact': rawData['emergencyContact'] ?? '',
            'medicalConditions': rawData['medicalConditions'] ?? '',
            'allergies': rawData['allergies'] ?? '',
            'medications': rawData['medications'] ?? '',
            'profilePictureUrl':
                rawData['profileImageUrl'] ?? rawData['profilePictureUrl'],
          };
        }
      }

      return data;
    } catch (e) {
      print('Error parsing response: $e');
      return {};
    }
  }

  void _populateCaregiverFields() {
    if (_userProfile == null) return;

    final profile = _userProfile as CaregiverProfile;
    _nameController.text = profile.name;
    _emailController.text = profile.email ?? '';
    _phoneController.text = profile.phoneNumber ?? '';
    _addressController.text = profile.address ?? '';
    _cityController.text = profile.city ?? '';
    _stateController.text = profile.state ?? '';
    _zipCodeController.text = profile.zipCode ?? '';
    _countryController.text = profile.country ?? '';

    _specializationController.text = (profile.specialization ?? '').trim();
    _organizationController.text = (profile.organization ?? '').trim();
    _licenseController.text = (profile.license ?? '').trim();
    _dateOfBirthController.text = (profile.dateOfBirth ?? '').trim();
  }

  void _populatePatientFields() {
    if (_userProfile == null) return;

    final profile = _userProfile as PatientProfile;
    _nameController.text = profile.name;
    _emailController.text = profile.email ?? '';
    _phoneController.text = profile.phoneNumber ?? '';
    _addressController.text = profile.address ?? '';
    _cityController.text = profile.city ?? '';
    _stateController.text = profile.state ?? '';
    _zipCodeController.text = profile.zipCode ?? '';
    _countryController.text = profile.country ?? '';

    _dateOfBirthController.text = profile.dateOfBirth ?? '';
    _genderController.text = profile.gender ?? '';
    _emergencyContactController.text = profile.emergencyContact ?? '';
    _medicalConditionsController.text = profile.medicalConditions ?? '';
    _allergiesController.text = profile.allergies ?? '';
    _medicationsController.text = profile.medications ?? '';
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Get the user session to retrieve the correct ID based on role
      final userSession = await AuthTokenManager.getUserSession();

      // Add role-specific fields
      if (_isCaregiver) {
        // Build caregiver profile data based on the expected backend structure
        final Map<String, dynamic> profileData = {
          'firstName': _nameController.text.split(' ').first,
          'lastName': _nameController.text.contains(' ')
              ? _nameController.text.split(' ').last
              : '',
          'dob': _dateOfBirthController.text,
          'email': _emailController.text,
          'phone': _phoneController.text,
          // Professional info
          'professional': {
            'licenseNumber': _licenseController.text,
            'issuingState':
                _stateController.text, // Using state as issuing state
            'yearsExperience':
                int.tryParse(_specializationController.text) ??
                1, // Using specialization field for years of experience
          },
          // Address info
          'address': {
            'line1': _addressController.text,
            'line2': '', // No separate field for line2 in the form
            'city': _cityController.text,
            'state': _stateController.text,
            'zip': _zipCodeController.text,
            'phone': _phoneController.text,
          },
          // Organization can be included as caregiverType
          'caregiverType': _organizationController.text,
          // Add credentials for update operation
          'credentials': {
            'email': _emailController.text,
            // No password needed for update
          },
        };

        final caregiverId = userSession?['caregiverId'] as int?;
        if (caregiverId == null) {
          throw Exception('Caregiver ID not found in user session');
        }

        // Debug the request payload
        print('🔍 Caregiver update payload: ${jsonEncode(profileData)}');

        final response = await ApiService.updateCaregiverProfile(
          caregiverId,
          profileData,
        );

        if (response.statusCode == 200) {
          final data = await _parseResponse(response);
          setState(() {
            _userProfile = CaregiverProfile.fromJson(data);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );

          // Update name in user provider
          final userProvider = Provider.of<UserProvider>(
            context,
            listen: false,
          );
          userProvider.updateUserName(_nameController.text);
        } else {
          print('❌ Caregiver profile update failed: ${response.statusCode}');
          print('❌ Error response: ${response.body}');
          throw Exception(
            'Failed to update caregiver profile: ${response.statusCode} - ${response.body}',
          );
        }
      } else if (_isPatient) {
        // Build patient profile data based on the expected backend structure
        final Map<String, dynamic> patientData = {
          'firstName': _nameController.text.split(' ').first,
          'lastName': _nameController.text.contains(' ')
              ? _nameController.text.split(' ').last
              : '',
          'dob': _dateOfBirthController.text,
          'email': _emailController.text,
          'phone': _phoneController.text,
          'gender': _genderController.text,
          'emergencyContact': _emergencyContactController.text,
          // Medical information
          'medicalInfo': {
            'conditions': _medicalConditionsController.text,
            'allergies': _allergiesController.text,
            'medications': _medicationsController.text,
          },
          // Address info
          'address': {
            'line1': _addressController.text,
            'line2': '', // No separate field for line2 in the form
            'city': _cityController.text,
            'state': _stateController.text,
            'zip': _zipCodeController.text,
            'phone': _phoneController.text,
          },
          // Add credentials for update operation
          'credentials': {
            'email': _emailController.text,
            // No password needed for update
          },
        };

        final patientId = userSession?['patientId'] as int?;
        if (patientId == null) {
          throw Exception('Patient ID not found in user session');
        }

        // Debug the request payload
        print('🔍 Patient update payload: ${jsonEncode(patientData)}');

        final response = await ApiService.updatePatientProfile(
          patientId,
          patientData,
        );

        if (response.statusCode == 200) {
          final data = await _parseResponse(response);
          setState(() {
            _userProfile = PatientProfile.fromJson(data);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );

          // Update name in user provider
          final userProvider = Provider.of<UserProvider>(
            context,
            listen: false,
          );
          userProvider.updateUserName(_nameController.text);
        } else {
          print('❌ Patient profile update failed: ${response.statusCode}');
          print('❌ Error response: ${response.body}');
          throw Exception(
            'Failed to update patient profile: ${response.statusCode} - ${response.body}',
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _showCurrentPlanDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current Plan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Basic Plan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Up to 5 patients'),
            const Text('• Basic analytics'),
            const Text('• Standard support'),
            const SizedBox(height: 16),
            Text(
              'Upgrade to Premium for advanced features!',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/select-package');
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Profile Settings',
        centerTitle: true,
      ),
      drawer: const CommonDrawer(currentRoute: '/profile-settings'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorWidget()
          : _buildProfileForm(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(
              'Error Loading Profile',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadUserProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfilePictureSection(),
                const SizedBox(height: 24),

                // Common fields
                _buildSectionHeader('Personal Information'),
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  prefixIcon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _emailController,
                  label: 'Email',
                  prefixIcon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  prefixIcon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),

                const SizedBox(height: 16),
                _buildSectionHeader('Address Information'),
                _buildTextField(
                  controller: _addressController,
                  label: 'Address',
                  prefixIcon: Icons.location_on,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _cityController,
                        label: 'City',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _stateController,
                        label: 'State/Province',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _zipCodeController,
                        label: 'ZIP/Postal Code',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _countryController,
                        label: 'Country',
                      ),
                    ),
                  ],
                ),

                // Role-specific fields
                if (_isCaregiver) ...[
                  const SizedBox(height: 16),
                  _buildSectionHeader('Professional Information'),
                  _buildTextField(
                    controller: _specializationController,
                    label: 'Specialization',
                    prefixIcon: Icons.medical_services,
                  ),
                  _buildTextField(
                    controller: _organizationController,
                    label: 'Organization',
                    prefixIcon: Icons.business,
                  ),
                  _buildTextField(
                    controller: _licenseController,
                    label: 'License Number',
                    prefixIcon: Icons.card_membership,
                  ),
                ],

                if (_isPatient) ...[
                  const SizedBox(height: 16),
                  _buildSectionHeader('Care Circle'),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.groups_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Manage Care Circle'),
                      subtitle: const Text(
                        'See linked caregivers, share your profile, and control access.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/care-circle'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('Medical Information'),
                  _buildTextField(
                    controller: _dateOfBirthController,
                    label: 'Date of Birth',
                    prefixIcon: Icons.cake,
                    hintText: 'YYYY-MM-DD',
                  ),
                  _buildTextField(
                    controller: _genderController,
                    label: 'Gender',
                    prefixIcon: Icons.person_outline,
                  ),
                  _buildTextField(
                    controller: _emergencyContactController,
                    label: 'Emergency Contact',
                    prefixIcon: Icons.contacts,
                  ),
                  _buildTextField(
                    controller: _medicalConditionsController,
                    label: 'Medical Conditions',
                    prefixIcon: Icons.medical_information,
                    maxLines: 3,
                  ),
                  _buildTextField(
                    controller: _allergiesController,
                    label: 'Allergies',
                    prefixIcon: Icons.error_outline,
                    maxLines: 2,
                  ),
                  _buildTextField(
                    controller: _medicationsController,
                    label: 'Current Medications',
                    prefixIcon: Icons.medication,
                    maxLines: 3,
                  ),
                ],

                // Subscription Management Section - Only for caregivers
                if (_isCaregiver) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildSectionHeader('Subscription Management'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.payment,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Manage Your Subscription',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Upgrade your plan to access premium features like advanced analytics, unlimited patients, and priority support.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(
                                      context,
                                    ).pushNamed('/select-package');
                                  },
                                  icon: const Icon(Icons.upgrade),
                                  label: const Text('Upgrade Plan'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    // Navigate to billing history or current plan details
                                    _showCurrentPlanDialog();
                                  },
                                  icon: const Icon(Icons.receipt_long),
                                  label: const Text('View Plan'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator()
                        : const Text(
                            'SAVE CHANGES',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePictureSection() {
    return Center(
      child: Column(
        children: [
          ProfilePictureWidget(
            size: 120,
            canEdit: true,
            existingImageUrl: _userProfile?.profilePictureUrl,
            onImageUpdated: (UserFileDTO updatedImage) {
              // Handle profile picture update
              setState(() {
                if (updatedImage.id == -1) {
                  // Image was deleted
                  if (_isCaregiver) {
                    _userProfile = (_userProfile as CaregiverProfile).copyWith(
                      profilePictureUrl: null,
                    );
                  } else {
                    _userProfile = (_userProfile as PatientProfile).copyWith(
                      profilePictureUrl: null,
                    );
                  }
                } else {
                  // Image was updated
                  final newUrl =
                      updatedImage.downloadUrl ?? updatedImage.fileUrl;
                  if (_isCaregiver) {
                    _userProfile = (_userProfile as CaregiverProfile).copyWith(
                      profilePictureUrl: newUrl,
                    );
                  } else {
                    _userProfile = (_userProfile as PatientProfile).copyWith(
                      profilePictureUrl: newUrl,
                    );
                  }
                }
              });
            },
            placeholderText: 'Add Photo',
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to change profile picture',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
      ),
    );
  }
}
