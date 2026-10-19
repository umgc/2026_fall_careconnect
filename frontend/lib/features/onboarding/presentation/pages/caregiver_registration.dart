import 'package:flutter/material.dart';
import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';

class CaregiverRegistrationPage extends StatefulWidget {
  const CaregiverRegistrationPage({super.key});

  @override
  State<CaregiverRegistrationPage> createState() =>
      _CaregiverRegistrationPageState();
}

class _CaregiverRegistrationPageState extends State<CaregiverRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _state = TextEditingController();
  // String _caregiverType = 'Family Member';
  bool _isProfessional = false;
  bool _isFamily = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Field validation status
  final Map<String, bool> _fieldValidStatus = {
    'name': false,
    'email': false,
    'phone': false,
    'city': false,
    'state': false,
    'password': false,
    'confirmPassword': false,
  };

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _city.dispose();
    _state.dispose();
    super.dispose();
  }

  // Add listeners to text controllers for real-time validation
  @override
  void initState() {
    super.initState();
    _name.addListener(() => _validateAndUpdate('name', _name.text));
    _email.addListener(() => _validateAndUpdate('email', _email.text));
    _phone.addListener(() => _validateAndUpdate('phone', _phone.text));
    _city.addListener(() => _validateAndUpdate('city', _city.text));
    _state.addListener(() => _validateAndUpdate('state', _state.text));
    _password.addListener(() => _validateAndUpdate('password', _password.text));
    _confirmPassword.addListener(
      () => _validateAndUpdate('confirmPassword', _confirmPassword.text),
    );
  }

  // Validate and update field status
  void _validateAndUpdate(String field, String value) {
    String? validationResult;

    switch (field) {
      case 'name':
        validationResult = _validateTextOnly(value, 'full name');
        break;
      case 'email':
        validationResult = _validateEmail(value);
        break;
      case 'phone':
        validationResult =
            value.isEmpty ? 'Please enter your phone number' : null;
        break;
      case 'city':
        validationResult = _validateTextOnly(value, 'city');
        break;
      case 'state':
        validationResult = _validateTextOnly(value, 'state');
        break;
      case 'password':
        validationResult = _validatePassword(value);
        // When password changes, also validate confirm password
        if (_confirmPassword.text.isNotEmpty) {
          _validateAndUpdate('confirmPassword', _confirmPassword.text);
        }
        break;
      case 'confirmPassword':
        validationResult = _validateConfirmPassword(value);
        break;
    }

    setState(() {
      _fieldValidStatus[field] = validationResult == null;
    });
  }

  // Validation helpers
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!value.contains('@')) {
      return 'Please enter a valid email address';
    }
    return null;
  }

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
    if (value != _password.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  String? _validateTextOnly(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return 'Please enter your $fieldName';
    }
    if (RegExp(r'[0-9]').hasMatch(value)) {
      return '$fieldName should not contain numbers';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // TODO: Handle registration logic
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver registration submitted!')),
      );
      navigateToDashboard(context);
    } else {
      // Display error message for invalid fields
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please check the form for errors and complete all required fields',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.error,
          duration: Duration(seconds: 3),
        ),
      );

      // Check each field and update its validation status
      _validateAndUpdate('name', _name.text);
      _validateAndUpdate('email', _email.text);
      _validateAndUpdate('phone', _phone.text);
      _validateAndUpdate('city', _city.text);
      _validateAndUpdate('state', _state.text);
      _validateAndUpdate('password', _password.text);
      _validateAndUpdate('confirmPassword', _confirmPassword.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Caregiver Registration',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // No drawer needed for registration page
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Register a Caregiver',
                      style: AppTheme.headingMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      decoration:
                          AppTheme.inputDecoration('Full Name').copyWith(
                        helperText: 'Enter your full name (letters only)',
                        errorText:
                            _name.text.isNotEmpty && !_fieldValidStatus['name']!
                                ? _validateTextOnly(_name.text, 'full name')
                                : null,
                      ),
                      validator: (value) =>
                          _validateTextOnly(value, 'full name'),
                      textCapitalization: TextCapitalization.words,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      decoration: AppTheme.inputDecoration('Email').copyWith(
                        helperText:
                            'Must contain @ symbol (e.g., name@example.com)',
                        errorText: _email.text.isNotEmpty &&
                                !_fieldValidStatus['email']!
                            ? _validateEmail(_email.text)
                            : null,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      decoration:
                          AppTheme.inputDecoration('Phone Number').copyWith(
                        helperText: 'Enter a valid phone number',
                        errorText: _phone.text.isNotEmpty &&
                                !_fieldValidStatus['phone']!
                            ? 'Please enter your phone number'
                            : null,
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Please enter your phone number'
                          : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _city,
                            decoration:
                                AppTheme.inputDecoration('City').copyWith(
                              helperText: 'Text only, no numbers',
                              errorText: _city.text.isNotEmpty &&
                                      !_fieldValidStatus['city']!
                                  ? _validateTextOnly(_city.text, 'city')
                                  : null,
                            ),
                            validator: (value) =>
                                _validateTextOnly(value, 'city'),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _state,
                            decoration:
                                AppTheme.inputDecoration('State').copyWith(
                              helperText: 'Text only, no numbers',
                              errorText: _state.text.isNotEmpty &&
                                      !_fieldValidStatus['state']!
                                  ? _validateTextOnly(_state.text, 'state')
                                  : null,
                            ),
                            validator: (value) =>
                                _validateTextOnly(value, 'state'),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: AppTheme.inputDecoration('Password').copyWith(
                        helperText:
                            'Min. 9 chars with uppercase, lowercase, number, and special char',
                        helperMaxLines: 2,
                        errorText: _password.text.isNotEmpty &&
                                !_fieldValidStatus['password']!
                            ? _validatePassword(_password.text)
                            : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.primary,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: _validatePassword,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPassword,
                      obscureText: _obscureConfirmPassword,
                      decoration:
                          AppTheme.inputDecoration('Confirm Password').copyWith(
                        helperText: 'Must match password above',
                        errorText: _confirmPassword.text.isNotEmpty &&
                                !_fieldValidStatus['confirmPassword']!
                            ? _validateConfirmPassword(
                                _confirmPassword.text,
                              )
                            : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.primary,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      validator: _validateConfirmPassword,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Caregiver Type',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                        fontSize: 16,
                      ),
                    ),
                    CheckboxListTile(
                      title: const Text(
                        'Family Member',
                        style: AppTheme.bodyMedium,
                      ),
                      value: _isFamily,
                      activeColor: AppTheme.primary,
                      onChanged: (val) {
                        setState(() {
                          _isFamily = val ?? false;
                          if (!_isFamily && !_isProfessional) {
                            _isProfessional = true;
                          }
                        });
                      },
                    ),
                    CheckboxListTile(
                      title: const Text(
                        'Professional',
                        style: AppTheme.bodyMedium,
                      ),
                      value: _isProfessional,
                      activeColor: AppTheme.primary,
                      onChanged: (val) {
                        setState(() {
                          _isProfessional = val ?? false;
                          if (!_isFamily && !_isProfessional) {
                            _isFamily = true;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _submit,
                        child: const Text('Register'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
