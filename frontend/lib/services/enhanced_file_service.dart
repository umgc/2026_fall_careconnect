import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'api_service.dart';
import 'auth_token_manager.dart';

/// Enhanced User File DTO based on backend controller structure
class UserFileDTO {
  final int id;
  final String originalFilename;
  final String contentType;
  final int fileSize;
  final String fileCategory;
  final String? description;
  final int ownerId;
  final String ownerType;
  final int? patientId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? fileUrl;
  final String? downloadUrl;
  final List<String>? files;
  final String? category;
  final String? s3FullKey;
  final String fileName;

  UserFileDTO({
    required this.id,
    required this.originalFilename,
    required this.contentType,
    required this.fileSize,
    required this.fileCategory,
    this.description,
    required this.ownerId,
    required this.ownerType,
    this.patientId,
    required this.createdAt,
    required this.updatedAt,
    this.fileUrl,
    this.downloadUrl,
    this.files,
    this.category,
    this.s3FullKey,
    required this.fileName,
  });

  factory UserFileDTO.fromJson(Map<String, dynamic> json) {
    return UserFileDTO(
      id: json['id'] ?? 0,
      originalFilename: json['originalFilename'] ?? '',
      contentType: json['contentType'] ?? 'application/octet-stream',
      fileSize: json['fileSize'] ?? 0,
      fileCategory: json['fileCategory'] ?? 'documents',
      description: json['description'],
      ownerId: json['ownerId'] ?? 0,
      ownerType: json['ownerType'] ?? '',
      patientId: json['patientId'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      fileUrl: json['fileUrl'],
      downloadUrl: json['downloadUrl'],
      files: json['files'],
      category: json['category'] ?? '',
      s3FullKey: json['s3FullKey'],
      fileName: json['filename'] ?? '[Unnamed File]',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalFilename': originalFilename,
      'contentType': contentType,
      'fileSize': fileSize,
      'fileCategory': fileCategory,
      'description': description,
      'ownerId': ownerId,
      'ownerType': ownerType,
      'patientId': patientId,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'fileUrl': fileUrl,
      'downloadUrl': downloadUrl,
      'files': files,
      'category': category,
      's3FullyKey': s3FullKey,
    };
  }

  /// Get display name for category
  String get categoryDisplayName {
    return getCategoryDisplayName(fileCategory);
  }

  /// Get icon for file type
  String get fileIcon {
    if (contentType.startsWith('image/')) return '🖼️';
    if (contentType.contains('pdf')) return '📄';
    if (contentType.contains('word') || contentType.contains('document')) {
      return '📝';
    }
    if (contentType.contains('excel') || contentType.contains('spreadsheet')) {
      return '📊';
    }
    if (contentType.contains('powerpoint') ||
        contentType.contains('presentation')) {
      return '📈';
    }
    if (contentType.startsWith('video/')) return '🎥';
    if (contentType.startsWith('audio/')) return '🎵';
    return '📁';
  }

  /// Check if file is an image
  bool get isImage => contentType.startsWith('image/');

  /// Check if file is a document that can be previewed
  bool get isPreviewable =>
      contentType.contains('pdf') ||
      contentType.contains('word') ||
      contentType.contains('document') ||
      isImage;
}

/// File upload response from backend
class FileUploadResponse {
  final int fileId;
  final String originalFilename;
  final String fileUrl;
  final String downloadUrl;
  final String message;
  final String fileName;

  FileUploadResponse({
    required this.fileId,
    required this.originalFilename,
    required this.fileUrl,
    required this.downloadUrl,
    required this.message,
    required this.fileName,
  });

  factory FileUploadResponse.fromJson(Map<String, dynamic> json) {
    return FileUploadResponse(
      fileId: json['fileId'] ?? 0,
      originalFilename: json['originalFilename'] ?? '',
      fileUrl: json['fileUrl'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      message: json['message'] ?? '',
      fileName: json['fileName'] ?? '',
    );
  }
}

/// Enhanced File Management Service that integrates with the backend controller
class EnhancedFileService {
  /// Upload a file using the new database-first approach
  static Future<FileUploadResponse?> uploadFile({
    required File file,
    required String category,
    String? description,
    int? patientId,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      // Remove Content-Type as it will be set by multipart request
      headers.remove('Content-Type');

      // Use users endpoint for file uploads
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.files}/users/$patientId/upload'),
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
        filename: path.basename(file.path),
      );

      // Add form fields
      request.files.add(multipartFile);
      request.fields['category'] = category;

      // Send the request
      var streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
          );
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return FileUploadResponse.fromJson(responseData['data']);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to upload file');
      }
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  /// Upload a file using the new database-first approach
  static Future<FileUploadResponse?> uploadFileWeb({
    required Uint8List fileBytes,
    required String fileName,
    required String category,
    String? description,
    int? patientId,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      // Remove Content-Type as it will be set by multipart request
      headers.remove('Content-Type');

      // Use users endpoint for file uploads
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.files}/users/$patientId/upload'),
      );

      // Add headers
      request.headers.addAll(headers);

      // Add file
      var fileStream = http.ByteStream(Stream.fromIterable([fileBytes]));
      var fileLength = await fileStream.length;
      var multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: path.basename(fileName),
      );

      // Add form fields
      request.files.add(multipartFile);
      request.fields['category'] = category;

      // Send the request
      var streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
          );
      print('Trying to upload file now.');
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return FileUploadResponse.fromJson(responseData);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to upload file');
      }
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  /// Download file content by file ID
  static Future<Uint8List?> downloadFile(int userId) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await http
          .get(
            Uri.parse('${ApiConstants.files}/users/$userId/download'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to download file');
      }
    } catch (e) {
      print('Error downloading file: $e');
      return null;
    }
  }

  /// Download file with legacy endpoint with user ID and file path
  static Future<Uint8List?> downloadFileLegacy(
      int userId, String filePath) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();

      // Build URL with userId path and filePath query param
      final uri =
          Uri.parse('${ApiConstants.files}/users/$userId/download').replace(
        queryParameters: {'filePath': filePath},
      );

      final response = await http
          .get(
            uri,
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to download file');
      }
    } catch (e) {
      print('Error downloading file: $e');
      return null;
    }
  }

  /// List files for current user
  static Future<List<UserFileDTO>> listMyFiles({String? category}) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final categoryParam = category != null ? '?category=$category' : '';
      final response = await http
          .get(
            Uri.parse('${ApiConstants.files}/my-files$categoryParam'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> files = responseData['data'];
        return files.map((json) => UserFileDTO.fromJson(json)).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to list files');
      }
    } catch (e) {
      print('Error listing my files: $e');
      return [];
    }
  }

  /// List files for a specific patient
  static Future<List<UserFileDTO>> listPatientFiles(
    int patientId, {
    String? category,
  }) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final categoryParam = category != null ? '?category=$category' : '';
      final response = await http
          .get(
            Uri.parse('${ApiConstants.files}/patient/$patientId$categoryParam'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> files = responseData['data'];
        return files.map((json) => UserFileDTO.fromJson(json)).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to list patient files');
      }
    } catch (e) {
      print('Error listing patient files: $e');
      return [];
    }
  }

  /// Delete a file by ID
  static Future<bool> deleteFile(int fileId) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await http
          .delete(Uri.parse('${ApiConstants.files}/$fileId'), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return true;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to delete file');
      }
    } catch (e) {
      print('Error deleting file: $e');
      return false;
    }
  }

  /// Get user's profile image
  static Future<UserFileDTO?> getProfileImage() async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final response = await http
          .get(
            Uri.parse('${ApiConstants.files}/profile-image'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return UserFileDTO.fromJson(responseData['data']);
      } else if (response.statusCode == 404) {
        // No profile image found is not an error
        return null;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to get profile image');
      }
    } catch (e) {
      print('Error getting profile image: $e');
      return null;
    }
  }

  /// Upload profile image
  static Future<FileUploadResponse?> uploadProfileImage(File imageFile) async {
    return uploadFile(
      file: imageFile,
      category: 'PROFILE_PICTURE',
      description: 'Profile picture',
    );
  }

  /// Get file categories for different user types
  static List<String> getValidCategories(String userType) {
    switch (userType.toUpperCase()) {
      case 'PATIENT':
        return [
          'PROFILE_PICTURE',
          'OTHER_DOCUMENT',
          'MEDICAL_RECORD',
          'PRESCRIPTION',
          'INSURANCE',
          'REPORT',
          'CONSENT_FORM',
          'EMERGENCY_CONTACT',
        ];
      case 'CAREGIVER':
        return [
          'PROFILE_PICTURE',
          'CERTIFICATION',
          'OTHER_DOCUMENT',
          'TRAINING',
          'BACKGROUND_CHECK',
          'REFERENCE',
          'CONTRACT',
        ];
      case 'FAMILY_MEMBER':
        return ['PROFILE_PICTURE', 'OTHER_DOCUMENT', 'AUTHORIZATION'];
      default:
        return ['OTHER_DOCUMENT'];
    }
  }

  /// Get display names for categories
  static Map<String, String> getCategoryDisplayNames() {
    return {
      'PROFILE_PICTURE': 'Profile Picture',
      'OTHER_DOCUMENT': 'Other Document',
      'MEDICAL_RECORD': 'Medical Record',
      'PRESCRIPTION': 'Prescription',
      'INSURANCE': 'Insurance',
      'REPORT': 'Report',
      'CONSENT_FORM': 'Consent Form',
      'EMERGENCY_CONTACT': 'Emergency Contact',
      'CERTIFICATION': 'Certification',
      'TRAINING': 'Training',
      'BACKGROUND_CHECK': 'Background Check',
      'REFERENCE': 'Reference',
      'CONTRACT': 'Contract',
      'AUTHORIZATION': 'Authorization',
      'MEDICAL_NOTE': 'Medical Note',
      'GENERAL_NOTE': 'General Note',
      'LAB_RESULT': 'Lab Result',
      'APPOINTMENT': 'Appointment',
      'CARE_NOTE': 'Care Note',
      'documents': 'General Document'
    };
  }
}

/// Helper function to get display name for category
String getCategoryDisplayName(String category) {
  final displayNames = EnhancedFileService.getCategoryDisplayNames();
  return displayNames[category] ?? category.replaceAll('_', ' ').toLowerCase();
}
