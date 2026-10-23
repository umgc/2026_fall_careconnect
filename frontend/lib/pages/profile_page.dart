/// TODO: ARCHITECTURAL DEBT NOTICE
/// Currently, the database uses a 'split-profile' strategy where core data is
/// fragmented across three tables: [users], [caregivers], and [patients].
///
/// ISSUE: This forces the frontend to perform multi-step fetches and complex
/// mapping logic because 'address' and 'contact' info live in role-specific
/// tables rather than a unified [address] table with a user_id foreign key.
library;

import 'dart:io';
import 'dart:convert'; // Added for jsonDecode
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../widgets/app_bar_helper.dart';
import '../widgets/common_drawer.dart';
import '../services/api_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  dynamic _userProfile;
  bool _isEditing = false;

  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _countryController = TextEditingController();

  // Role-specific controllers
  final _specializationController = TextEditingController();
  final _organizationController = TextEditingController();
  final _licenseController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _medicalNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
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
    _emergencyContactController.dispose();
    _medicalNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user != null) {
        Map<String, dynamic> profile = {
          'name': user.name,
          'email': user.email,
          'phone': '',
          'address': '',
          'city': '',
          'state': '',
          'zipCode': '',
          'country': 'USA',
          'specialization': '',
          'organization': '',
          'licenseNumber': '123456HARDCODED VALUE',
          'emergencyContact': '',
          'medicalNotes': '',
        };

        if (user.role.toUpperCase() == 'CAREGIVER' &&
            user.caregiverId != null) {
          final response = await ApiService.getCaregiverProfile(
            user.caregiverId!,
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final addr = data['address'] as Map<String, dynamic>?;
            // update the profile map with the API response
            profile['phone'] = data['phone'] ?? '';
            profile['address'] = addr?['line1'] ?? '';
            profile['city'] = addr?['city'] ?? '';
            profile['state'] = addr?['state'] ?? '';
            profile['zipCode'] = addr?['zip'] ?? '';
            profile['specialization'] = data['caregiverType'] ?? '';
          }
        } else if (user.role.toUpperCase() == 'PATIENT' &&
            user.patientId != null) {
          final response = await ApiService.getPatientProfile(user.patientId!);
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final addr = data['address'] as Map<String, dynamic>?;

            profile['phone'] = data['phone'] ?? '';
            profile['address'] = addr?['line1'] ?? '';
            profile['city'] = addr?['city'] ?? '';
            profile['state'] = addr?['state'] ?? '';
            profile['zipCode'] = addr?['zip'] ?? '';

            // Patient-specific fields (Mapping from your JSON keys)
            profile['emergencyContact'] = data['emergencyContact'] ?? '';
            profile['medicalNotes'] =
                data['medicalConditions'] ?? data['notes'] ?? '';
          }
        }

        if (mounted) {
          setState(() {
            _userProfile = profile;
            _populateControllers();
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'User not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load profile: $e';
        _isLoading = false;
      });
    }
  }

  void _populateControllers() {
    if (_userProfile != null) {
      _nameController.text = _userProfile['name'] ?? '';
      _emailController.text = _userProfile['email'] ?? '';
      _phoneController.text = _userProfile['phone'] ?? '';
      _addressController.text = _userProfile['address'] ?? '';
      _cityController.text = _userProfile['city'] ?? '';
      _stateController.text = _userProfile['state'] ?? '';
      _zipCodeController.text = _userProfile['zipCode'] ?? '';
      _countryController.text = _userProfile['country'] ?? '';
      _specializationController.text = _userProfile['specialization'] ?? '';
      _organizationController.text = _userProfile['organization'] ?? '';
      _licenseController.text = _userProfile['licenseNumber'] ?? '';
      _emergencyContactController.text = _userProfile['emergencyContact'] ?? '';
      _medicalNotesController.text = _userProfile['medicalNotes'] ?? '';
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user != null) {
        // Prepare the payload based on your API's nested address structure
        // TODO: the update call below is commented out, so this
        // payload is never sent and the success message is misleading.
        // ignore: unused_local_variable
        final profileData = {
          'firstName': _nameController.text.split(' ').first,
          'lastName': _nameController.text.contains(' ')
              ? _nameController.text.split(' ').last
              : '',
          'phone': _phoneController.text.trim(),
          'address': {
            'line1': _addressController.text.trim(),
            'city': _cityController.text.trim(),
            'state': _stateController.text.trim(),
            'zip': _zipCodeController.text.trim(),
          },
          if (user.role.toUpperCase() == 'CAREGIVER') ...{
            'caregiverType': _specializationController.text.trim(),
          },
        };

        // Call the update method (You'll likely need to add this to ApiService)
        // await ApiService.updateCaregiverProfile(user.caregiverId!, profileData);

        if (_imageFile != null) {
          // await ApiService.uploadProfileImage(user.id, _imageFile!);
        }

        setState(() {
          _isSaving = false;
          _isEditing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Profile updated successfully!')),
        );

        await _loadUserProfile();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to save profile: $e';
        _isSaving = false;
      });
    }
  }

  // ... rest of your build methods remain the same ...

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _imageFile = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Profile',
        additionalActions: [
          if (!_isLoading && !_isEditing)
            IconButton(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Profile',
            ),
          if (_isEditing) ...[
            IconButton(
              onPressed: () => setState(() => _isEditing = false),
              icon: const Icon(Icons.cancel),
              tooltip: 'Cancel',
            ),
            IconButton(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              tooltip: 'Save Profile',
            ),
          ],
        ],
      ),
      drawer: const CommonDrawer(currentRoute: '/profile'),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading profile...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadUserProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildProfilePictureSection(),
            const SizedBox(height: 24),
            _buildBasicInfoSection(),
            const SizedBox(height: 24),
            _buildContactInfoSection(),
            const SizedBox(height: 24),
            _buildAddressSection(),
            const SizedBox(height: 24),
            _buildRoleSpecificSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePictureSection() {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    // Fallback avatar logic: show image if picked, else first letter of name, else icon
    Widget avatarChild;
    if (_imageFile != null) {
      avatarChild = const SizedBox.shrink();
    } else if (user != null && user.name != null && user.name!.isNotEmpty) {
      avatarChild = Text(
        user.name![0].toUpperCase(),
        style: TextStyle(
          fontSize: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      avatarChild = Icon(
        Icons.person,
        size: 60,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      _imageFile != null ? FileImage(_imageFile!) : null,
                  child: avatarChild,
                ),
                if (_isEditing)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).shadowColor.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              (user != null && user.name != null && user.name!.isNotEmpty)
                  ? user.name!
                  : 'User',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Chip(
              label: Text(
                (user != null && user.role.isNotEmpty) ? user.role : 'USER',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basic Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              enabled: _isEditing,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              enabled: _isEditing,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Email is required';
                }
                if (!RegExp(
                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              enabled: _isEditing,
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Address', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Street Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.home),
              ),
              enabled: _isEditing,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(),
                    ),
                    enabled: _isEditing,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _stateController,
                    decoration: const InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(),
                    ),
                    enabled: _isEditing,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _zipCodeController,
                    decoration: const InputDecoration(
                      labelText: 'ZIP Code',
                      border: OutlineInputBorder(),
                    ),
                    enabled: _isEditing,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _countryController,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      border: OutlineInputBorder(),
                    ),
                    enabled: _isEditing,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSpecificSection() {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    if (user?.role.toUpperCase() == 'CAREGIVER') {
      return _buildCaregiverSpecificSection();
    } else if (user?.role.toUpperCase() == 'PATIENT') {
      return _buildPatientSpecificSection();
    }

    return const SizedBox.shrink();
  }

  Widget _buildCaregiverSpecificSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Professional Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _specializationController,
              decoration: const InputDecoration(
                labelText: 'Specialization',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.medical_services),
              ),
              enabled: _isEditing,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _organizationController,
              decoration: const InputDecoration(
                labelText: 'Organization',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
              enabled: _isEditing,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _licenseController,
              decoration: const InputDecoration(
                labelText: 'License Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.card_membership),
              ),
              enabled: _isEditing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientSpecificSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Medical Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emergencyContactController,
              decoration: const InputDecoration(
                labelText: 'Emergency Contact',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.emergency),
              ),
              enabled: _isEditing,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _medicalNotesController,
              decoration: const InputDecoration(
                labelText: 'Medical Notes',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note_add),
              ),
              enabled: _isEditing,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
