import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import '../../models/address_model.dart';
import 'dart:convert';
import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';

class PatientRegistrationPage extends StatefulWidget {
  final int? caregiverId;

  const PatientRegistrationPage({super.key, this.caregiverId});

  @override
  State<PatientRegistrationPage> createState() =>
      _PatientRegistrationPageState();
}

class _PatientRegistrationPageState extends State<PatientRegistrationPage> {
  final _formKeys = [
    GlobalKey<FormState>(), // Step 0: Personal Info
    GlobalKey<FormState>(), // Step 1: Address Info
    GlobalKey<FormState>(), // Step 2: Emergency Contact
  ];

  int _currentStep = 0;
  bool _isLoading = false;

  // Step 0: Personal Information
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  // final _passwordController = TextEditingController(); // Commented out - handled on backend
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _maNumberController = TextEditingController();
  String? _selectedGender; // Add gender field

  // Step 1: Address Information
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();
  final _addressPhoneController = TextEditingController();

  // Step 2: Emergency Contact & Relationship
  final _relationshipController = TextEditingController();
  final _passwordController =
      TextEditingController(); // Used for validation only, not sent to backend

  // Focus nodes for all fields
  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _dobFocus = FocusNode();
  final _maNumberFocus = FocusNode();
  final _addressLine1Focus = FocusNode();
  final _cityFocus = FocusNode();
  final _stateFocus = FocusNode();
  final _zipFocus = FocusNode();
  final _addressPhoneFocus = FocusNode();
  final _relationshipFocus = FocusNode();

  // Field validation status tracking
  final Map<String, bool> _fieldValidStatus = {
    // Personal Info
    'firstName': false,
    'lastName': false,
    'email': false,
    'phone': false,
    'dob': false,
    'maNumber': false,
    'gender': false, // Add gender validation
    // Address Info
    'addressLine1': false,
    'city': false,
    'state': false,
    'zip': false,
    'addressPhone': false,

    // Emergency Contact
    'relationship': false,
  };

  @override
  void initState() {
    super.initState();

    // Set up focus listeners to validate fields when focus changes
    _setupFocusListeners();
  }

  void _setupFocusListeners() {
    // Personal Info
    _firstNameFocus.addListener(() {
      if (!_firstNameFocus.hasFocus) {
        _validateAndUpdate('firstName', _firstNameController.text);
      }
    });

    _lastNameFocus.addListener(() {
      if (!_lastNameFocus.hasFocus) {
        _validateAndUpdate('lastName', _lastNameController.text);
      }
    });

    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) {
        _validateAndUpdate('email', _emailController.text);
      }
    });

    _phoneFocus.addListener(() {
      if (!_phoneFocus.hasFocus) {
        _validateAndUpdate('phone', _phoneController.text);
      }
    });

    _dobFocus.addListener(() {
      if (!_dobFocus.hasFocus) {
        _validateAndUpdate('dob', _dobController.text);
      }
    });

    _maNumberFocus.addListener(() {
      if (!_maNumberFocus.hasFocus) {
        _validateAndUpdate('maNumber', _maNumberController.text);
      }
    });

    // Address Info
    _addressLine1Focus.addListener(() {
      if (!_addressLine1Focus.hasFocus) {
        _validateAndUpdate('addressLine1', _addressLine1Controller.text);
      }
    });

    _cityFocus.addListener(() {
      if (!_cityFocus.hasFocus) {
        _validateAndUpdate('city', _cityController.text);
      }
    });

    _stateFocus.addListener(() {
      if (!_stateFocus.hasFocus) {
        _validateAndUpdate('state', _stateController.text);
      }
    });

    _zipFocus.addListener(() {
      if (!_zipFocus.hasFocus) {
        _validateAndUpdate('zip', _zipController.text);
      }
    });

    _addressPhoneFocus.addListener(() {
      if (!_addressPhoneFocus.hasFocus) {
        _validateAndUpdate('addressPhone', _addressPhoneController.text);
      }
    });

    // Emergency Contact
    _relationshipFocus.addListener(() {
      if (!_relationshipFocus.hasFocus) {
        _validateAndUpdate('relationship', _relationshipController.text);
      }
    });
  }

  // Validate and update field status
  void _validateAndUpdate(String field, String value) {
    String? validationResult;

    switch (field) {
      case 'firstName':
      case 'lastName':
        validationResult = _validateTextOnly(
          value,
          field.replaceAll('Name', ' name'),
        );
        break;
      case 'email':
        validationResult = _validateEmail(value);
        break;
      case 'phone':
      case 'addressPhone':
        validationResult = value.isEmpty ? 'Please enter a phone number' : null;
        break;
      case 'dob':
        validationResult = value.isEmpty ? 'Please enter date of birth' : null;
        break;
      case 'maNumber':
        validationResult = _validateMaNumber(value);
        break;
      case 'gender':
        validationResult =
            _selectedGender == null ? 'Please select gender' : null;
        break;
      case 'addressLine1':
        validationResult = value.isEmpty ? 'Please enter address line 1' : null;
        break;
      case 'city':
      case 'state':
        validationResult = _validateTextOnly(value, field);
        break;
      case 'zip':
        validationResult = value.isEmpty ? 'Please enter ZIP code' : null;
        break;
      case 'relationship':
        validationResult = value.isEmpty ? 'Please specify relationship' : null;
        break;
    }

    setState(() {
      _fieldValidStatus[field] = validationResult == null;
    });
  }

  // Validation helpers
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an email address';
    }
    if (!value.contains('@')) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validateMaNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter MA Number';
    }

    // Check if it starts with "MA"
    if (!value.toUpperCase().startsWith('MA')) {
      return 'MA Number must start with "MA"';
    }

    // Check if it has exactly 9 digits after "MA"
    final digitsOnly = value.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length != 9) {
      return 'MA Number must have exactly 9 digits after "MA" (e.g., MA123456789)';
    }

    return null;
  }

  // Password validation function kept for reference but not currently used
  // as password handling is done on the backend
  /*
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 9) {
      return 'Password must be at least 9 characters';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain a lowercase letter';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain an uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain a number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain a special character';
    }
    return null;
  }
  
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }
  */

  String? _validateTextOnly(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return 'Please enter $fieldName';
    }
    if (RegExp(r'[0-9]').hasMatch(value)) {
      return '$fieldName should not contain numbers';
    }
    return null;
  }

  @override
  void dispose() {
    // Personal info controllers
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _maNumberController.dispose();

    // Address controllers
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _addressPhoneController.dispose();

    // Relationship controller
    _relationshipController.dispose();

    // Dispose focus nodes
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _dobFocus.dispose();
    _maNumberFocus.dispose();
    _addressLine1Focus.dispose();
    _cityFocus.dispose();
    _stateFocus.dispose();
    _zipFocus.dispose();
    _addressPhoneFocus.dispose();
    _relationshipFocus.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Register New Patient',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => navigateToDashboard(context),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Stepper(
            currentStep: _currentStep,
            onStepTapped: (step) {
              if (step < _currentStep) {
                setState(() => _currentStep = step);
              }
            },
            controlsBuilder: (context, details) {
              return Row(
                children: [
                  if (details.stepIndex < 2)
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _nextStep(),
                      style:
                          Theme.of(context).elevatedButtonTheme.style?.copyWith(
                                backgroundColor: WidgetStateProperty.all(
                                  Theme.of(context).colorScheme.primary,
                                ),
                                foregroundColor: WidgetStateProperty.all(
                                  Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                      child: const Text('Next'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _registerPatient(),
                      style:
                          Theme.of(context).elevatedButtonTheme.style?.copyWith(
                                backgroundColor: WidgetStateProperty.all(
                                  Theme.of(context).colorScheme.secondary,
                                ),
                                foregroundColor: WidgetStateProperty.all(
                                  Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Register Patient'),
                    ),
                  const SizedBox(width: 8),
                  if (details.stepIndex > 0)
                    TextButton(
                      onPressed: _isLoading ? null : () => _previousStep(),
                      child: const Text('Back'),
                    ),
                ],
              );
            },
            steps: [
              Step(
                title: const Text('Personal Information'),
                content: _buildPersonalInfoStep(),
                isActive: _currentStep >= 0,
                state:
                    _currentStep > 0 ? StepState.complete : StepState.indexed,
              ),
              Step(
                title: const Text('Address Information'),
                content: _buildAddressStep(),
                isActive: _currentStep >= 1,
                state: _currentStep > 1
                    ? StepState.complete
                    : _currentStep == 1
                        ? StepState.indexed
                        : StepState.disabled,
              ),
              Step(
                title: const Text('Relationship'),
                content: _buildRelationshipStep(),
                isActive: _currentStep >= 2,
                state:
                    _currentStep == 2 ? StepState.indexed : StepState.disabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonalInfoStep() {
    return Form(
      key: _formKeys[0],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstNameController,
                  focusNode: _firstNameFocus,
                  decoration: AppTheme.inputDecoration('First Name *').copyWith(
                    errorText: _firstNameController.text.isNotEmpty &&
                            !_fieldValidStatus['firstName']!
                        ? 'Please enter valid first name (no numbers)'
                        : null,
                  ),
                  validator: (value) => _validateTextOnly(value, 'first name'),
                  // Only validate when form is submitted
                  autovalidateMode: AutovalidateMode.disabled,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _lastNameController,
                  focusNode: _lastNameFocus,
                  decoration: AppTheme.inputDecoration('Last Name *').copyWith(
                    errorText: _lastNameController.text.isNotEmpty &&
                            !_fieldValidStatus['lastName']!
                        ? 'Please enter valid last name (no numbers)'
                        : null,
                  ),
                  validator: (value) => _validateTextOnly(value, 'last name'),
                  autovalidateMode: AutovalidateMode.disabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            focusNode: _emailFocus,
            decoration: AppTheme.inputDecoration('Email Address *').copyWith(
              prefixIcon: const Icon(Icons.email),
              helperText: 'Must contain @ symbol (e.g., name@example.com)',
              errorText: _emailController.text.isNotEmpty &&
                      !_fieldValidStatus['email']!
                  ? _validateEmail(_emailController.text)
                  : null,
            ),
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
            autovalidateMode: AutovalidateMode.disabled,
          ),
          const SizedBox(height: 16),
          // Password field commented out - handled on backend
          // TextFormField(
          //   controller: _passwordController,
          //   decoration: InputDecoration(
          //     labelText: 'Password *',
          //     labelStyle: const TextStyle(color: Color(0xFF14366E)),
          //     border: OutlineInputBorder(
          //       borderRadius: BorderRadius.circular(8),
          //     ),
          //     focusedBorder: const OutlineInputBorder(
          //       borderSide: BorderSide(color: Color(0xFF14366E)),
          //     ),
          //     prefixIcon: const Icon(Icons.lock),
          //   ),
          //   obscureText: true,
          //   validator: (value) {
          //     if (value == null || value.isEmpty) {
          //       return 'Please enter password';
          //     }
          //     if (value.length < 6) {
          //       return 'Password must be at least 6 characters';
          //     }
          //     return null;
          //   },
          // ),
          // const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            decoration: AppTheme.inputDecoration('Phone Number *').copyWith(
              prefixIcon: const Icon(Icons.phone),
              helperText: 'Enter a valid phone number',
              errorText: _phoneController.text.isNotEmpty &&
                      !_fieldValidStatus['phone']!
                  ? 'Please enter a valid phone number'
                  : null,
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter phone number';
              }
              return null;
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _dobController,
            decoration: AppTheme.inputDecoration('Date of Birth *').copyWith(
              prefixIcon: const Icon(Icons.calendar_today),
              hintText: 'MM/DD/YYYY',
              errorText:
                  _dobController.text.isNotEmpty && !_fieldValidStatus['dob']!
                      ? 'Please enter a valid date of birth'
                      : null,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter date of birth';
              }
              return null;
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime(1990),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                // Format as MM/DD/YYYY to match API expectation
                _dobController.text =
                    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
              }
            },
            readOnly: true,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _maNumberController,
            focusNode: _maNumberFocus,
            decoration: AppTheme.inputDecoration('MA Number *').copyWith(
              prefixIcon: const Icon(Icons.badge),
              helperText: 'Format: MA followed by 9 digits (e.g., MA123456789)',
              errorText: _maNumberController.text.isNotEmpty &&
                      !_fieldValidStatus['maNumber']!
                  ? _validateMaNumber(_maNumberController.text)
                  : null,
            ),
            textCapitalization: TextCapitalization.characters,
            validator: _validateMaNumber,
            autovalidateMode: AutovalidateMode.disabled,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedGender,
            decoration: AppTheme.inputDecoration('Gender *').copyWith(
              prefixIcon: const Icon(Icons.person),
              errorText:
                  _selectedGender == null && !_fieldValidStatus['gender']!
                      ? 'Please select gender'
                      : null,
            ),
            items: const [
              DropdownMenuItem(value: 'MALE', child: Text('Male')),
              DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
              DropdownMenuItem(value: 'OTHER', child: Text('Other')),
              DropdownMenuItem(
                value: 'prefer_not_to_say',
                child: Text('Prefer not to say'),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedGender = value;
                _fieldValidStatus['gender'] = value != null;
              });
            },
            validator: (value) {
              if (value == null) {
                return 'Please select gender';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAddressStep() {
    return Form(
      key: _formKeys[1],
      child: Column(
        children: [
          TextFormField(
            controller: _addressLine1Controller,
            decoration: AppTheme.inputDecoration(
              'Address Line 1 *',
            ).copyWith(hintText: 'Street address, P.O. box'),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter address line 1';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressLine2Controller,
            decoration: AppTheme.inputDecoration('Address Line 2').copyWith(
              hintText: 'Apartment, suite, unit, building, floor, etc.',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _cityController,
                  decoration: AppTheme.inputDecoration(
                    'City *',
                  ).copyWith(helperText: 'Text only, no numbers'),
                  validator: (value) => _validateTextOnly(value, 'city'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _stateController,
                  decoration: AppTheme.inputDecoration('State *').copyWith(
                    helperText: 'Text only, no numbers',
                    hintText: 'VA',
                  ),
                  validator: (value) => _validateTextOnly(value, 'state'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _zipController,
                  decoration: AppTheme.inputDecoration('ZIP Code *'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter ZIP code';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _addressPhoneController,
                  decoration: AppTheme.inputDecoration(
                    'Address Phone *',
                  ).copyWith(hintText: 'Home/Work phone'),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter address phone';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRelationshipStep() {
    return Form(
      key: _formKeys[2],
      child: Column(
        children: [
          TextFormField(
            controller: _relationshipController,
            decoration:
                AppTheme.inputDecoration('Relationship to Patient *').copyWith(
              hintText: 'e.g., Parent, Spouse, Child, Daughter, Son, etc.',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter relationship to patient';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Registration Summary',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Patient: ${_firstNameController.text} ${_lastNameController.text}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Email: ${_emailController.text}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Phone: ${_phoneController.text}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Date of Birth: ${_dobController.text}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Address: ${_addressLine1Controller.text}, ${_cityController.text}, ${_stateController.text} ${_zipController.text}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _nextStep() {
    if (_formKeys[_currentStep].currentState!.validate()) {
      if (_currentStep < 2) {
        setState(() => _currentStep++);
      }
    } else {
      // Display error message and mark validation fields
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete all required fields correctly before continuing',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.error,
          duration: Duration(seconds: 3),
        ),
      );

      // For each step, validate the appropriate fields
      if (_currentStep == 0) {
        _validateAndUpdate('firstName', _firstNameController.text);
        _validateAndUpdate('lastName', _lastNameController.text);
        _validateAndUpdate('email', _emailController.text);
        _validateAndUpdate('phone', _phoneController.text);
        _validateAndUpdate('dob', _dobController.text);
      } else if (_currentStep == 1) {
        _validateAndUpdate('addressLine1', _addressLine1Controller.text);
        _validateAndUpdate('city', _cityController.text);
        _validateAndUpdate('state', _stateController.text);
        _validateAndUpdate('zip', _zipController.text);
        _validateAndUpdate('addressPhone', _addressPhoneController.text);
      } else if (_currentStep == 2) {
        _validateAndUpdate('relationship', _relationshipController.text);
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _registerPatient() async {
    if (!_formKeys[_currentStep].currentState!.validate() ||
        _selectedGender == null) {
      // Display error message and validate relationship and gender field
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete all required fields correctly before registering, including gender selection.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.error,
          duration: Duration(seconds: 3),
        ),
      );

      _validateAndUpdate('relationship', _relationshipController.text);
      _validateAndUpdate('gender', _selectedGender ?? '');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      final caregiverId = widget.caregiverId ?? user?.caregiverId;

      if (caregiverId == null) {
        throw Exception('Caregiver ID is required for patient registration');
      }

      // Create Address object using the model
      final address = Address(
        line1: _addressLine1Controller.text.trim(),
        line2: _addressLine2Controller.text.trim().isNotEmpty
            ? _addressLine2Controller.text.trim()
            : null,
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        zip: _zipController.text.trim(),
        phone: _addressPhoneController.text.trim(),
      );

      // Structure the request body - password field removed (handled on backend)
      final requestBody = {
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'dob': _dobController.text.trim(), // Already in MM/DD/YYYY format
        'email': _emailController.text.trim(),
        // 'password': _passwordController.text.trim(), // Removed - handled on backend
        'phone': _phoneController.text.trim(),
        'maNumber': _maNumberController.text.trim().toUpperCase(),
        'gender': _selectedGender?.toUpperCase(), // Add gender field
        'address': address.toJson(), // Use the Address model's toJson method
        'caregiverId': caregiverId,
        'relationship': _relationshipController.text.trim(),
      };

      print('🔍 Patient registration request body: ${jsonEncode(requestBody)}');

      // Use caregiver-specific API endpoint
      final response = await ApiService.registerPatientForCaregiver(
        caregiverId: caregiverId,
        patientData: requestBody,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Patient registered successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          navigateToDashboard(context);
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
          errorData['message'] ?? errorData['error'] ?? 'Registration failed',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
