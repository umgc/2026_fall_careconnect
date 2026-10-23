import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../config/router/app_router.dart';
import '../../../../widgets/app_bar_helper.dart';
import '../../../../widgets/common_drawer.dart';
import '../../../../config/theme/app_theme.dart';
import '../../models/connection_request_model.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  _AddPatientScreenState createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final relationshipController = TextEditingController();
  final messageController = TextEditingController();

  bool _isLoading = false;
  bool _isCheckingEmail = false;
  String? _errorMessage;

  // Email check results
  bool? _emailExists;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    // Set up listeners for real-time validation
    emailController.addListener(() => setState(() {}));
    relationshipController.addListener(() => setState(() {}));
    messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    emailController.dispose();
    relationshipController.dispose();
    messageController.dispose();
    super.dispose();
  }

  Future<void> _checkEmail() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter an email address';
      });
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _errorMessage = null;
      _emailExists = null;
      _userRole = null;
    });

    try {
      final result = await ApiService.checkEmailExists(email);

      setState(() {
        _isCheckingEmail = false;
        _emailExists = result['exists'] as bool;
        _userRole = result['role'] as String?;

        if (_emailExists == true && _userRole != 'PATIENT') {
          _errorMessage =
              'This email belongs to a ${_userRole?.toLowerCase() ?? 'user'}, not a patient';
          _emailExists = false;
        }
      });
    } catch (e) {
      setState(() {
        _isCheckingEmail = false;
        _errorMessage = 'Error checking email: $e';
      });
    }
  }

  Future<void> _sendConnectionRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null || user.caregiverId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'User or caregiver ID not available';
      });
      return;
    }

    try {
      final response = await ApiService.sendConnectionRequest(
        caregiverId: user.caregiverId!,
        patientEmail: emailController.text.trim(),
        relationshipType: relationshipController.text.trim(),
        message: messageController.text.trim(),
      );

      if (response.statusCode == 200) {
        final result = ConnectionRequestResponse.fromJson(
          json.decode(response.body),
        );

        if (!mounted) return;

        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection request sent successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Navigate back to dashboard
          navigateToDashboard(context);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = result.error ?? 'Unknown error';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Server error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  Future<void> _registerNewPatient() async {
    if (!mounted) return;
    context.go('/register/patient');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const CommonDrawer(currentRoute: '/add-patient'),
      appBar: AppBarHelper.createAppBar(context, title: 'Add Patient'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 600,
              ), // Constrain width for better readability
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connect with a Patient',
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  const Text(
                    'Enter the email of an existing patient or register a new one',
                    style: TextStyle(fontSize: 14.0, color: Colors.grey),
                  ),
                  const SizedBox(height: 24.0),

                  // Email check section
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Step 1: Check if patient exists',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12.0),
                          TextFormField(
                            controller: emailController,
                            decoration: AppTheme.inputDecoration(
                              'Patient Email',
                              hint: 'Enter patient email address',
                            ).copyWith(
                              errorText: emailController.text.isNotEmpty &&
                                      !RegExp(
                                        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                                      ).hasMatch(emailController.text)
                                  ? 'Please enter a valid email'
                                  : null,
                              suffixIcon: IconButton(
                                icon: _isCheckingEmail
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(
                                            context,
                                          ).primaryColor,
                                        ),
                                      )
                                    : Icon(
                                        Icons.search,
                                        color: Theme.of(
                                          context,
                                        ).primaryColor,
                                      ),
                                onPressed:
                                    _isCheckingEmail ? null : _checkEmail,
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (_) => setState(() {}),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Email is required';
                              }
                              if (!RegExp(
                                r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                              ).hasMatch(value)) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16.0),
                          if (_errorMessage != null)
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: AppTheme.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 8.0),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_emailExists == false && _errorMessage == null)
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.amber.shade900,
                                      ),
                                      const SizedBox(width: 8.0),
                                      Expanded(
                                        child: Text(
                                          'No patient found with this email.',
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12.0),
                                  ElevatedButton.icon(
                                    onPressed: _registerNewPatient,
                                    style: AppTheme.primaryButtonStyle.copyWith(
                                      minimumSize: WidgetStateProperty.all(
                                        const Size(double.infinity, 45),
                                      ),
                                      shape: WidgetStateProperty.all(
                                        RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('Register New Patient'),
                                  ),
                                ],
                              ),
                            ),
                          if (_emailExists == true)
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 8.0),
                                  Expanded(
                                    child: Text(
                                      'Patient found! You can send a connection request.',
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24.0),

                  // Connection request form - only show when patient exists
                  if (_emailExists == true)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Step 2: Send connection request',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 16.0),
                              TextFormField(
                                controller: relationshipController,
                                decoration: AppTheme.inputDecoration(
                                  'Relationship to Patient',
                                  hint:
                                      'E.g., Caregiver, Family Member, Parent',
                                ).copyWith(
                                  errorText:
                                      relationshipController.text.isNotEmpty &&
                                              relationshipController.text
                                                      .trim()
                                                      .length <
                                                  3
                                          ? 'Please enter a valid relationship'
                                          : null,
                                ),
                                onChanged: (_) => setState(() {}),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please specify your relationship';
                                  }
                                  if (value.trim().length < 3) {
                                    return 'Please enter a valid relationship';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16.0),
                              TextFormField(
                                controller: messageController,
                                decoration: AppTheme.inputDecoration(
                                  'Message (Optional)',
                                  hint: 'Add a personal message',
                                ).copyWith(
                                  errorText: messageController
                                              .text.isNotEmpty &&
                                          messageController.text.length > 500
                                      ? 'Message too long (max 500 characters)'
                                      : null,
                                ),
                                maxLines: 3,
                                onChanged: (_) => setState(() {}),
                                validator: (value) {
                                  if (value != null && value.length > 500) {
                                    return 'Message too long (max 500 characters)';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24.0),
                              ElevatedButton(
                                onPressed:
                                    _isLoading ? null : _sendConnectionRequest,
                                style: AppTheme.primaryButtonStyle.copyWith(
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith<Color>(
                                    (states) => states.contains(
                                      WidgetState.disabled,
                                    )
                                        ? Colors.grey.shade400
                                        : Colors.blue.shade900,
                                  ),
                                  minimumSize: WidgetStateProperty.all(
                                    const Size(double.infinity, 50),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Send Connection Request',
                                        style: TextStyle(fontSize: 16),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24.0),

                  // New patient registration button
                  if (_emailExists != true)
                    Center(
                      child: Column(
                        children: [
                          const Text(
                            'Need to add a new patient?',
                            style: TextStyle(
                              fontSize: 14.0,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.blue.shade900),
                              foregroundColor: Colors.blue.shade900,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Register New Patient'),
                            onPressed: _registerNewPatient,
                          ),
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
}
