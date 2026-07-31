import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/hiring_form_models.dart';
import 'api_service.dart';
import 'auth_token_manager.dart';

/// Result of a hiring-form submission attempt.
class FormSubmitResult {
  final bool ok;
  final String message;

  /// Server-side validation errors (when the form failed validation).
  final List<String> errors;

  /// Submission id assigned by the backend, when successful.
  final int? submissionId;

  const FormSubmitResult({
    required this.ok,
    required this.message,
    this.errors = const [],
    this.submissionId,
  });
}

/// Sends completed hiring/onboarding form data to the backend, which validates
/// it against the form schema and persists a [FormSubmission] row.
class HiringFormSubmissionService {
  /// Submit captured [fieldValues] (keyed by "sectionId.fieldId") for [definition].
  ///
  /// [confirmed] must be true — callers set it only after the user explicitly
  /// confirms the submission in the UI.
  static Future<FormSubmitResult> submit({
    required FormDefinition definition,
    required Map<String, dynamic> fieldValues,
    int? patientId,
    bool confirmed = true,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      // ApiConstants.baseUrl already ends with "/v1/api/".
      final uri = Uri.parse('${ApiConstants.baseUrl}forms/submissions');
      final body = jsonEncode({
        'formType': definition.formType,
        'version': definition.version,
        'patientId': patientId,
        'fieldValues': fieldValues,
        'confirmed': confirmed,
      });

      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> decoded = {};
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) decoded = parsed;
      } catch (_) {/* non-JSON body */}

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = decoded['data'];
        final id = data is Map ? data['id'] as int? : null;
        return FormSubmitResult(
          ok: true,
          message: (decoded['message'] ?? 'Form submitted successfully').toString(),
          submissionId: id,
        );
      }

      // Validation failure -> surface the per-field error list.
      if (response.statusCode == 422) {
        final details = (decoded['details'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        return FormSubmitResult(
          ok: false,
          message: (decoded['error'] ?? 'Form has validation errors').toString(),
          errors: details,
        );
      }

      return FormSubmitResult(
        ok: false,
        message: (decoded['error'] ?? 'Submission failed (${response.statusCode})')
            .toString(),
      );
    } catch (e) {
      return FormSubmitResult(ok: false, message: 'Submission failed: $e');
    }
  }
}
