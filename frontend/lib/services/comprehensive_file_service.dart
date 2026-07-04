import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';
import 'auth_token_manager.dart';
import 'enhanced_file_service.dart';

/// File upload categories based on healthcare requirements.
///
/// The [value] of each entry is a backend-recognized token: either a canonical
/// `com.careconnect.model.UserFile.FileCategory` enum name, or one of its
/// accepted aliases (e.g. AI_CHAT_UPLOAD, HEALTH_DATA_IMPORT and BACKUP_FILE
/// intentionally resolve to OTHER_DOCUMENT on the backend). Unknown values are
/// rejected by the backend with a 400 rather than silently miscategorized, so
/// keeping this list aligned guarantees a file is stored under the category
/// the user selected.
enum FileCategory {
  // Core Healthcare
  medicalReport('MEDICAL_RECORD', 'Medical Report', '🏥'),
  labResult('LAB_RESULT', 'Lab Result', '🧪'),
  prescription('PRESCRIPTION', 'Prescription', '💊'),
  clinicalNotes('CLINICAL_NOTE', 'Clinical Notes', '📋'),

  // Personal
  profilePicture('PROFILE_IMAGE', 'Profile Picture', '👤'),
  emergencyContact('EMERGENCY_CONTACT', 'Emergency Contact', '🚨'),
  insuranceDoc('INSURANCE_DOCUMENT', 'Insurance Document', '🛡️'),

  // Employment & Onboarding (Home Care Document Digitization)
  employmentApplication('EMPLOYMENT_APPLICATION', 'Employment Application', '📝'),
  onboardingForm('ONBOARDING_FORM', 'Onboarding Form', '🗂️'),
  backgroundCheck('BACKGROUND_CHECK', 'Background Check', '🔎'),
  certification('CERTIFICATION', 'Certification / License', '📜'),
  reference('REFERENCE', 'Reference', '🧾'),
  employmentContract('EMPLOYMENT_CONTRACT', 'Employment Contract', '✍️'),
  taxForm('TAX_FORM', 'Tax Form (W-4)', '💵'),
  workAuthorization('WORK_AUTHORIZATION', 'Work Authorization (I-9)', '🆔'),

  // AI & Communication
  aiChatUpload('AI_CHAT_UPLOAD', 'AI Chat File', '🤖'),
  generalDocument('OTHER_DOCUMENT', 'General Document', '📄'),

  // Data Management
  healthDataImport('HEALTH_DATA_IMPORT', 'Health Data Import', '📊'),
  backupFile('BACKUP_FILE', 'Backup File', '💾');

  const FileCategory(this.value, this.displayName, this.icon);
  final String value;
  final String displayName;
  final String icon;

  /// Document types that belong to the employment / home-care intake workflow.
  /// Mirrors `UserFile.FileCategory.EMPLOYMENT_INTAKE` on the backend.
  static const List<FileCategory> employmentIntake = [
    employmentApplication,
    onboardingForm,
    backgroundCheck,
    certification,
    reference,
    employmentContract,
    taxForm,
    workAuthorization,
  ];

  /// Whether this category is a hiring / onboarding intake document type.
  bool get isEmploymentIntake => employmentIntake.contains(this);
}

class FileCategoryDropdown extends StatefulWidget {
  const FileCategoryDropdown({super.key, this.allowedCategories});

  final List<FileCategory>? allowedCategories;

  @override
  State<FileCategoryDropdown> createState() => _FileCategoryDropdownState();
}

class _FileCategoryDropdownState extends State<FileCategoryDropdown> {
  late List<FileCategory> _availableCategories;
  FileCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _availableCategories = widget.allowedCategories != null &&
        widget.allowedCategories!.isNotEmpty
        ? widget.allowedCategories!
        : FileCategory.values;

    // Initialize selectedCategory
    if (_availableCategories.isNotEmpty) {
      _selectedCategory = _availableCategories.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_availableCategories.isEmpty) {
      return const Text('No categories available.');
    }

    return DropdownButtonFormField<FileCategory>(
      items: _availableCategories.map((category) {
        return DropdownMenuItem<FileCategory>(
          value: category,
          child: Text('${category.icon} ${category.displayName}'),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedCategory = value;
        });
      },
      initialValue: _selectedCategory,
      decoration: const InputDecoration(labelText: 'Select Category'),
    );
  }
}


/// Document-type selector for the employment / home-care intake workflow.
///
/// Shows only hiring and onboarding document types (see
/// [FileCategory.employmentIntake]) and reports the current selection back to
/// the parent via [onChanged] so it can be submitted with the upload.
class EmploymentDocumentTypeDropdown extends StatefulWidget {
  const EmploymentDocumentTypeDropdown({
    super.key,
    this.initialType,
    this.onChanged,
  });

  final FileCategory? initialType;
  final ValueChanged<FileCategory>? onChanged;

  @override
  State<EmploymentDocumentTypeDropdown> createState() =>
      _EmploymentDocumentTypeDropdownState();
}

class _EmploymentDocumentTypeDropdownState
    extends State<EmploymentDocumentTypeDropdown> {
  late FileCategory _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType =
        (widget.initialType != null && widget.initialType!.isEmploymentIntake)
            ? widget.initialType!
            : FileCategory.employmentIntake.first;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<FileCategory>(
      initialValue: _selectedType,
      decoration: const InputDecoration(
        labelText: 'Document Type',
        hintText: 'Select a hiring or onboarding document',
      ),
      items: FileCategory.employmentIntake.map((category) {
        return DropdownMenuItem<FileCategory>(
          value: category,
          child: Text('${category.icon} ${category.displayName}'),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedType = value);
        widget.onChanged?.call(value);
      },
    );
  }
}


/// File query parameters for advanced filtering
class FileQueryParams {
  final int? page;
  final int? size;
  final String? sort;
  final String? category;
  final List<String>? categories;
  final String? startDate;
  final String? endDate;
  final String? query;

  FileQueryParams({
    this.page,
    this.size,
    this.sort,
    this.category,
    this.categories,
    this.startDate,
    this.endDate,
    this.query,
  });

  String toQueryString() {
    final params = <String>[];

    if (page != null) params.add('page=$page');
    if (size != null) params.add('size=$size');
    if (sort != null) params.add('sort=$sort');
    if (category != null) params.add('category=$category');
    if (categories != null && categories!.isNotEmpty) {
      params.add('categories=${categories!.join(',')}');
    }
    if (startDate != null) params.add('startDate=$startDate');
    if (endDate != null) params.add('endDate=$endDate');
    if (query != null) params.add('query=${Uri.encodeComponent(query!)}');

    return params.isEmpty ? '' : '?${params.join('&')}';
  }
}

/// Comprehensive file management service for CareConnect
class ComprehensiveFileService {
  // ========== FILE UPLOAD METHODS ==========

  /// 1. Profile Image Upload
  static Future<FileUploadResponse?> uploadProfileImage({
    required int userId,
    File? imageFile,
    XFile? pickedFile,
  }) async {
    try {
      File? fileToUpload;

      if (imageFile != null) {
        fileToUpload = imageFile;
      } else if (pickedFile != null) {
        fileToUpload = File(pickedFile.path);
      } else {
        // Open image picker
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 85,
        );
        if (image == null) return null;
        fileToUpload = File(image.path);
      }

      return await _uploadToEndpoint(
        endpoint: '/users/$userId/profile-image',
        file: fileToUpload,
        category: FileCategory.profilePicture.value,
        description: 'Profile picture for user $userId',
      );
    } catch (e) {
      debugPrint('❌ Error uploading profile image: $e');
      return null;
    }
  }

  /// 2. Medical Document Upload
  static Future<FileUploadResponse?> uploadMedicalDocument({
    required int patientId,
    File? documentFile,
    FileCategory category = FileCategory.medicalReport,
    String? description,
  }) async {
    try {
      File? fileToUpload = documentFile;

      if (fileToUpload == null) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return null;
        fileToUpload = File(result.files.first.path!);
      }

      return await _uploadToEndpoint(
        endpoint: '/patients/$patientId/documents',
        file: fileToUpload,
        category: category.value,
        description: description ?? 'Medical document for patient $patientId',
        additionalFields: {'patientId': patientId.toString()},
      );
    } catch (e) {
      debugPrint('❌ Error uploading medical document: $e');
      return null;
    }
  }

  /// 3. Clinical Notes Attachments
  static Future<FileUploadResponse?> uploadClinicalNotesAttachment({
    required int patientId,
    required File attachmentFile,
    String? description,
  }) async {
    try {
      return await _uploadToEndpoint(
        endpoint: '/clinical-notes/attachments',
        file: attachmentFile,
        category: FileCategory.clinicalNotes.value,
        description: description ?? 'Clinical notes attachment',
        additionalFields: {'patientId': patientId.toString()},
      );
    } catch (e) {
      debugPrint('❌ Error uploading clinical notes attachment: $e');
      return null;
    }
  }

  /// 4. Chat File Upload (for AI assistance with documents)
  static Future<FileUploadResponse?> uploadChatFile({
    required File chatFile,
    String? description,
    Map<String, String>? aiContext,
  }) async {
    try {
      final additionalFields = <String, String>{
        if (aiContext != null) ...aiContext,
      };

      return await _uploadToEndpoint(
        endpoint: '/ai-chat/upload',
        file: chatFile,
        category: FileCategory.aiChatUpload.value,
        description: description ?? 'File for AI chat analysis',
        additionalFields: additionalFields,
      );
    } catch (e) {
      debugPrint('❌ Error uploading chat file: $e');
      return null;
    }
  }

  /// 5. Prescription Upload
  static Future<FileUploadResponse?> uploadPrescription({
    required int patientId,
    File? prescriptionFile,
    String? description,
  }) async {
    try {
      File? fileToUpload = prescriptionFile;

      if (fileToUpload == null) {
        // Allow camera or gallery for prescription images
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.camera, // Default to camera for prescriptions
          imageQuality: 90,
        );
        if (image == null) return null;
        fileToUpload = File(image.path);
      }

      return await _uploadToEndpoint(
        endpoint: '/medications/prescriptions/upload',
        file: fileToUpload,
        category: FileCategory.prescription.value,
        description: description ?? 'Prescription for patient $patientId',
        additionalFields: {'patientId': patientId.toString()},
      );
    } catch (e) {
      debugPrint('❌ Error uploading prescription: $e');
      return null;
    }
  }

  /// 6. Emergency Contact Documents
  static Future<FileUploadResponse?> uploadEmergencyContactDocument({
    required int userId,
    required File documentFile,
    String? description,
  }) async {
    try {
      return await _uploadToEndpoint(
        endpoint: '/users/$userId/emergency-documents',
        file: documentFile,
        category: FileCategory.emergencyContact.value,
        description: description ?? 'Emergency contact document',
      );
    } catch (e) {
      debugPrint('❌ Error uploading emergency contact document: $e');
      return null;
    }
  }

  /// 7. Insurance Documents
  static Future<FileUploadResponse?> uploadInsuranceDocument({
    required int patientId,
    required File insuranceFile,
    String? description,
  }) async {
    try {
      return await _uploadToEndpoint(
        endpoint: '/patients/$patientId/insurance',
        file: insuranceFile,
        category: FileCategory.insuranceDoc.value,
        description: description ?? 'Insurance document',
        additionalFields: {'patientId': patientId.toString()},
      );
    } catch (e) {
      debugPrint('❌ Error uploading insurance document: $e');
      return null;
    }
  }

  /// 7b. Employment / Home-Care Intake Document Upload
  ///
  /// Dedicated intake flow for hiring and onboarding forms. The selected
  /// [documentType] must be an employment intake category; the file is linked
  /// to the uploading owner and, when supplied, to the [patientId] /
  /// [careCircleId] it pertains to (care-circle context).
  ///
  /// Returns `null` (without a network call) when [documentType] is not an
  /// employment intake type, so callers get a clear, early rejection.
  static Future<FileUploadResponse?> uploadEmploymentDocument({
    required File documentFile,
    required FileCategory documentType,
    int? patientId,
    int? careCircleId,
    String? description,
  }) async {
    if (!documentType.isEmploymentIntake) {
      debugPrint('❌ Invalid intake document type: ${documentType.value}. '
          'Expected one of: '
          '${FileCategory.employmentIntake.map((c) => c.value).join(', ')}');
      return null;
    }

    try {
      final additionalFields = <String, String>{
        'documentType': documentType.value,
        if (patientId != null) 'patientId': patientId.toString(),
        if (careCircleId != null) 'careCircleId': careCircleId.toString(),
      };

      return await _uploadToEndpoint(
        endpoint: '/intake',
        file: documentFile,
        category: documentType.value,
        description:
            description ?? '${documentType.displayName} (intake document)',
        additionalFields: additionalFields,
      );
    } catch (e) {
      debugPrint('❌ Error uploading intake document: $e');
      return null;
    }
  }

  /// 8. Export Data with Files
  static Future<Uint8List?> exportUserDataWithFiles({
    required int userId,
    String format = 'zip',
    bool includeFiles = true,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final queryParams = FileQueryParams(
        category: includeFiles ? null : 'EXCLUDE_FILES',
      ).toQueryString();

      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.files}/users/$userId/export$queryParams&format=$format',
            ),
            headers: headers,
          )
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to export data');
      }
    } catch (e) {
      debugPrint('❌ Error exporting user data: $e');
      return null;
    }
  }

  /// 9. Bulk Data Import
  static Future<Map<String, dynamic>?> importBulkHealthData({
    required File dataFile,
    String importType = 'health_data',
    bool validateOnly = false,
  }) async {
    try {
      final response = await _uploadToEndpoint(
        endpoint: '/import/health-data',
        file: dataFile,
        category: FileCategory.healthDataImport.value,
        description: 'Bulk health data import',
        additionalFields: {
          'importType': importType,
          'validateOnly': validateOnly.toString(),
        },
      );

      // Convert FileUploadResponse to Map<String, dynamic>
      if (response != null) {
        return {
          'fileId': response.fileId,
          'originalFilename': response.originalFilename,
          'fileUrl': response.fileUrl,
          'downloadUrl': response.downloadUrl,
          'success': true,
        };
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error importing bulk data: $e');
      return null;
    }
  }

  /// 10. Backup/Restore Files
  static Future<FileUploadResponse?> uploadBackupFile({
    required File backupFile,
    String? backupType,
    String? description,
  }) async {
    try {
      return await _uploadToEndpoint(
        endpoint: '/backup/upload',
        file: backupFile,
        category: FileCategory.backupFile.value,
        description: description ?? 'Backup file restore',
        additionalFields: {if (backupType != null) 'backupType': backupType},
      );
    } catch (e) {
      debugPrint('❌ Error uploading backup file: $e');
      return null;
    }
  }

  // ========== FILE RETRIEVAL METHODS ==========

  /// Get All Files for a User
  static Future<List<UserFileDTO>> getAllUserFiles(
    int userId, {
    FileQueryParams? params,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final queryString = params?.toQueryString() ?? '';

      final response = await http
          .get(
            Uri.parse('${ApiConstants.files}/users/$userId/list$queryString'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> files =
            responseData['files'] ?? responseData['content'] ?? [];
        return files.map((json) => UserFileDTO.fromJson(json)).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to get user files');
      }
    } catch (e) {
      debugPrint('❌ Error getting user files: $e');
      return [];
    }
  }

  /// Get All Files for a User
  static Future<UserFileDTO?> getAllUserFiles1(
      int userId, {
        FileQueryParams? params,
      }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final queryString = params?.toQueryString() ?? '';

      final response = await http
          .get(
        Uri.parse('${ApiConstants.files}/users/$userId/list$queryString'),
        headers: headers,
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint('Response data returned: $responseData');
        return UserFileDTO.fromJson(responseData);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to get user files');
      }
    } catch (e) {
      debugPrint('❌ Error getting user files: $e');
      return null;
    }
  }

  /// Get Files by Category
  static Future<List<UserFileDTO>> getUserFilesByCategory(
    int userId,
    FileCategory category, {
    FileQueryParams? params,
  }) async {
    final updatedParams = FileQueryParams(
      page: params?.page,
      size: params?.size,
      sort: params?.sort,
      category: category.value,
      startDate: params?.startDate,
      endDate: params?.endDate,
      query: params?.query,
    );
    return getAllUserFiles(userId, params: updatedParams);
  }

  /// Get Patient's Medical Documents
  static Future<List<UserFileDTO>> getPatientMedicalDocuments(
    int patientId, {
    FileQueryParams? params,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final queryString = params?.toQueryString() ?? '';

      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.files}/patients/$patientId/documents$queryString',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> files =
            responseData['data'] ?? responseData['content'] ?? [];
        return files.map((json) => UserFileDTO.fromJson(json)).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          errorData['error'] ?? 'Failed to get patient documents',
        );
      }
    } catch (e) {
      debugPrint('❌ Error getting patient documents: $e');
      return [];
    }
  }

  /// Search Files by Name/Description
  static Future<List<UserFileDTO>> searchFiles({
    required String searchQuery,
    required int userId,
    FileQueryParams? params,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final searchParams = FileQueryParams(
        query: searchQuery,
        page: params?.page,
        size: params?.size,
        sort: params?.sort,
        category: params?.category,
        categories: params?.categories,
        startDate: params?.startDate,
        endDate: params?.endDate,
      );

      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.files}/search${searchParams.toQueryString()}&userId=$userId',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> files =
            responseData['data'] ?? responseData['content'] ?? [];
        return files.map((json) => UserFileDTO.fromJson(json)).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to search files');
      }
    } catch (e) {
      debugPrint('❌ Error searching files: $e');
      return [];
    }
  }

  /// Get Files by Date Range
  static Future<List<UserFileDTO>> getFilesByDateRange(
    int userId, {
    required DateTime startDate,
    required DateTime endDate,
    FileQueryParams? params,
  }) async {
    final dateParams = FileQueryParams(
      startDate: startDate.toIso8601String().split('T')[0],
      endDate: endDate.toIso8601String().split('T')[0],
      page: params?.page,
      size: params?.size,
      sort: params?.sort,
      category: params?.category,
      categories: params?.categories,
      query: params?.query,
    );
    return getAllUserFiles(userId, params: dateParams);
  }

  /// Get Files by Multiple Categories
  static Future<List<UserFileDTO>> getFilesByMultipleCategories(
    int userId, {
    required List<FileCategory> categories,
    FileQueryParams? params,
  }) async {
    final categoryParams = FileQueryParams(
      categories: categories.map((c) => c.value).toList(),
      page: params?.page,
      size: params?.size,
      sort: params?.sort,
      startDate: params?.startDate,
      endDate: params?.endDate,
      query: params?.query,
    );
    return getAllUserFiles(userId, params: categoryParams);
  }

  // ========== UTILITY METHODS ==========

  /// Generic upload method for all endpoints
  static Future<FileUploadResponse?> _uploadToEndpoint({
    required String endpoint,
    required File file,
    required String category,
    String? description,
    Map<String, String>? additionalFields,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      // Remove Content-Type as it will be set by multipart request
      headers.remove('Content-Type');

      // Use users endpoint for file uploads
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.files}$endpoint'),
      );

      // Add headers
      request.headers.addAll(headers);

      // Add file
      var fileStream = http.ByteStream(file.openRead());
      var fileLength = await file.length();
      var multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: file.path.split('/').last,
      );

      // Add form fields
      request.files.add(multipartFile);
      request.fields['category'] = category;
      if (description != null) {
        request.fields['description'] = description;
      }
      // Include any context fields (e.g. documentType, patientId, careCircleId)
      // so uploads are linked to the correct owner / patient / care circle.
      if (additionalFields != null) {
        request.fields.addAll(additionalFields);
      }

      debugPrint('📤 Uploading to: ${request.url}');
      debugPrint('📤 Category: $category');
      debugPrint('📤 File: ${file.path.split('/').last}');

      // Send the request
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return FileUploadResponse.fromJson(responseData['data']);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to upload file');
      }
    } catch (e) {
      debugPrint('❌ Error uploading to $endpoint: $e');
      return null;
    }
  }

  /// Get file picker for specific category
  static Future<File?> pickFileForCategory(FileCategory category) async {
    try {
      switch (category) {
        case FileCategory.profilePicture:
          final ImagePicker picker = ImagePicker();
          final XFile? image = await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 800,
            maxHeight: 800,
            imageQuality: 85,
          );
          return image != null ? File(image.path) : null;

        case FileCategory.prescription:
          final ImagePicker picker = ImagePicker();
          final XFile? image = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 90,
          );
          return image != null ? File(image.path) : null;

        case FileCategory.medicalReport:
        case FileCategory.labResult:
        case FileCategory.clinicalNotes:
        case FileCategory.insuranceDoc:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'txt'],
            allowMultiple: false,
          );

          if (result == null || result.files.isEmpty) return null;

          if (kIsWeb) {
            // On Web version: Use bytes and filename
            Uint8List? fileBytes = result.files.single.bytes;

            if (fileBytes != null) {
              return File(result.files.first.path!);
            } else {
              debugPrint('No file bytes found.');
              return null;
            }
          }

        default:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: false,
          );
          if (result == null || result.files.isEmpty) return null;
          if (kIsWeb) {
            // On Web: Use bytes and filename
            Uint8List? fileBytes = result.files.single.bytes;

            if (fileBytes != null) {
              return File(result.files.first.path!);
            } else {
              debugPrint('No file bytes found.');
              return null;
            }
          }
      }
    } catch (e) {
      debugPrint('❌ Error picking file for category ${category.displayName}: $e');
      return null;
    }
    return null;
  }

  /// Get file picker for specific category
  static Future<(Uint8List, String)?> pickFileForCategoryWeb(FileCategory category) async {
    try {
      switch (category) {
        case FileCategory.profilePicture:
        case FileCategory.prescription:
        case FileCategory.medicalReport:
        case FileCategory.labResult:
        case FileCategory.clinicalNotes:
        case FileCategory.insuranceDoc:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'txt'],
            allowMultiple: false,
          );

          if (result == null || result.files.isEmpty) return null;

          if (kIsWeb) {
            // On Web: Use bytes and filename
            Uint8List? fileBytes = result.files.single.bytes;
            String fileName = result.files.single.name;

            if (fileBytes != null) {
              return (fileBytes, fileName);
            } else {
              debugPrint('No file bytes found.');
              return null;
            }
          }

        default:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: false,
          );
          if (result == null || result.files.isEmpty) return null;
          if (kIsWeb) {
            // On Web: Use bytes and filename
            Uint8List? fileBytes = result.files.single.bytes;
            String fileName = result.files.single.name;

            if (fileBytes != null) {
              return (fileBytes, fileName);
            } else {
              debugPrint('No file bytes found.');
              return null;
            }
          }
      }
    } catch (e) {
      debugPrint('❌ Error picking file for category ${category.displayName}: $e');
      return null;
    }
    return null;
  }

  /// Validate file for category
  static bool validateFileForCategory(File file, FileCategory category) {
    final fileName = file.path.toLowerCase();
    final fileSize = file.lengthSync();

    // General size limit: 50MB
    if (fileSize > 50 * 1024 * 1024) {
      debugPrint('❌ File too large: ${fileSize / 1024 / 1024}MB');
      return false;
    }

    switch (category) {
      case FileCategory.profilePicture:
        return fileName.endsWith('.jpg') ||
            fileName.endsWith('.jpeg') ||
            fileName.endsWith('.png');

      case FileCategory.prescription:
        return fileName.endsWith('.jpg') ||
            fileName.endsWith('.jpeg') ||
            fileName.endsWith('.png') ||
            fileName.endsWith('.pdf') ||
            fileName.endsWith('.txt');

      case FileCategory.medicalReport:
      case FileCategory.labResult:
      case FileCategory.insuranceDoc:
        return fileName.endsWith('.pdf') ||
            fileName.endsWith('.doc') ||
            fileName.endsWith('.docx') ||
            fileName.endsWith('.jpg') ||
            fileName.endsWith('.jpeg') ||
            fileName.endsWith('.png') ||
            fileName.endsWith('.txt');

      default:
        return true; // Allow any file type for other categories
    }
  }
}
