import 'dart:io';
import 'enhanced_file_service.dart';

/// Legacy Patient Note model for backward compatibility
class PatientNote {
  final int id;
  final String title;
  final String content;
  final String fileName;
  final String fileUrl;
  final String uploadedBy;
  final DateTime uploadDate;
  final String category;
  final String noteType;
  final int patientId;

  PatientNote({
    required this.id,
    required this.title,
    required this.content,
    required this.fileName,
    required this.fileUrl,
    required this.uploadedBy,
    required this.uploadDate,
    required this.category,
    required this.noteType,
    required this.patientId,
  });

  factory PatientNote.fromJson(Map<String, dynamic> json) {
    final category = json['category'] ?? 'generalNote';
    return PatientNote(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      fileName: json['fileName'] ?? json['originalFilename'] ?? '',
      fileUrl: json['fileUrl'] ?? json['downloadUrl'] ?? '',
      uploadedBy: json['uploadedBy'] ?? 'Unknown',
      uploadDate:
          DateTime.tryParse(json['uploadDate'] ?? json['createdAt'] ?? '') ??
              DateTime.now(),
      category: category,
      noteType: _getCategoryDisplayName(category),
      patientId: json['patientId'] ?? 0,
    );
  }

  /// Convert UserFileDTO to PatientNote for backward compatibility
  factory PatientNote.fromUserFileDTO(UserFileDTO fileDto) {
    return PatientNote(
      id: fileDto.id,
      title: fileDto.originalFilename,
      content: fileDto.description ?? '',
      fileName: fileDto.originalFilename,
      fileUrl: fileDto.downloadUrl ?? fileDto.fileUrl ?? '',
      uploadedBy: 'User ${fileDto.ownerId}',
      uploadDate: fileDto.createdAt ?? DateTime.now(),
      category: _mapCategoryToLegacy(fileDto.fileCategory),
      noteType: fileDto.categoryDisplayName,
      patientId: fileDto.patientId ?? 0,
    );
  }

  static String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'medicalNote':
      case 'MEDICAL_NOTE':
        return 'Medical Note';
      case 'labResult':
      case 'LAB_RESULT':
        return 'Lab Result';
      case 'appointment':
      case 'APPOINTMENT':
        return 'Appointment';
      case 'prescription':
      case 'PRESCRIPTION':
        return 'Prescription';
      case 'generalNote':
      case 'GENERAL_NOTE':
        return 'General Note';
      case 'careNote':
      case 'CARE_NOTE':
        return 'Care Note';
      default:
        return 'Note';
    }
  }

  static String _mapCategoryToLegacy(String newCategory) {
    switch (newCategory) {
      case 'MEDICAL_NOTE':
        return 'medicalNote';
      case 'LAB_RESULT':
        return 'labResult';
      case 'APPOINTMENT':
        return 'appointment';
      case 'PRESCRIPTION':
        return 'prescription';
      case 'GENERAL_NOTE':
        return 'generalNote';
      case 'CARE_NOTE':
        return 'careNote';
      default:
        return 'generalNote';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'uploadedBy': uploadedBy,
      'uploadDate': uploadDate.toIso8601String(),
      'category': category,
      'noteType': noteType,
      'patientId': patientId,
    };
  }
}

/// Enhanced Patient Notes Service that uses the new backend controller
/// while maintaining backward compatibility with existing code
class PatientNotesService {
  /// Get all notes for a patient, optionally filtered by category
  static Future<List<PatientNote>> getPatientNotes(
    int patientId, {
    String? category,
  }) async {
    try {
      // Map legacy category to new category format
      String? newCategory;
      if (category != null) {
        switch (category) {
          case 'medicalNote':
            newCategory = 'MEDICAL_NOTE';
            break;
          case 'labResult':
            newCategory = 'LAB_RESULT';
            break;
          case 'appointment':
            newCategory = 'APPOINTMENT';
            break;
          case 'prescription':
            newCategory = 'PRESCRIPTION';
            break;
          case 'generalNote':
            newCategory = 'GENERAL_NOTE';
            break;
          case 'careNote':
            newCategory = 'CARE_NOTE';
            break;
          default:
            newCategory = category.toUpperCase();
        }
      }

      // Use the enhanced file service
      final files = await EnhancedFileService.listPatientFiles(
        patientId,
        category: newCategory,
      );

      // Convert UserFileDTO to PatientNote for backward compatibility
      return files.map((file) => PatientNote.fromUserFileDTO(file)).toList();
    } catch (e) {
      print('Error getting patient notes: $e');
      return [];
    }
  }

  /// Upload a new patient note
  static Future<PatientNote?> uploadPatientNote({
    required int patientId,
    required File file,
    required String title,
    String content = '',
    String category = 'generalNote',
  }) async {
    try {
      // Map legacy category to new category format
      String newCategory;
      switch (category) {
        case 'medicalNote':
          newCategory = 'MEDICAL_NOTE';
          break;
        case 'labResult':
          newCategory = 'LAB_RESULT';
          break;
        case 'appointment':
          newCategory = 'APPOINTMENT';
          break;
        case 'prescription':
          newCategory = 'PRESCRIPTION';
          break;
        case 'generalNote':
          newCategory = 'GENERAL_NOTE';
          break;
        case 'careNote':
          newCategory = 'CARE_NOTE';
          break;
        default:
          newCategory = 'OTHER_DOCUMENT';
      }

      // Use the enhanced file service
      final response = await EnhancedFileService.uploadFile(
        file: file,
        category: newCategory,
        description: '$title${content.isNotEmpty ? '\n\n$content' : ''}',
        patientId: patientId,
      );

      if (response != null) {
        // Create a PatientNote from the response
        return PatientNote(
          id: response.fileId,
          title: title,
          content: content,
          fileName: response.originalFilename,
          fileUrl: response.fileUrl,
          uploadedBy: 'Current User',
          uploadDate: DateTime.now(),
          category: category,
          noteType: PatientNote._getCategoryDisplayName(category),
          patientId: patientId,
        );
      }
    } catch (e) {
      print('Error uploading patient note: $e');
    }
    return null;
  }

  /// Get patient note details
  static Future<PatientNote?> getPatientNote(int noteId) async {
    try {
      // This would need to be implemented if required
      // For now, we can return null as the enhanced service handles file details differently
      return null;
    } catch (e) {
      print('Error getting patient note: $e');
      return null;
    }
  }

  /// Update patient note
  static Future<PatientNote?> updatePatientNote({
    required int noteId,
    required String title,
    String content = '',
    String? category,
  }) async {
    try {
      // This would need to be implemented with backend support for file metadata updates
      // For now, we can return null as the enhanced service doesn't support file content updates
      return null;
    } catch (e) {
      print('Error updating patient note: $e');
      return null;
    }
  }

  /// Delete patient note
  static Future<bool> deletePatientNote(int noteId) async {
    try {
      return await EnhancedFileService.deleteFile(noteId);
    } catch (e) {
      print('Error deleting patient note: $e');
      return false;
    }
  }

  /// Download patient note file
  static Future<String?> downloadPatientNote(int noteId) async {
    try {
      final fileBytes = await EnhancedFileService.downloadFile(noteId);
      if (fileBytes != null) {
        // Return a base64 encoded string or handle download based on platform
        return 'downloaded'; // Simplified return for now
      }
    } catch (e) {
      print('Error downloading patient note: $e');
    }
    return null;
  }

  /// Get available note categories (legacy format)
  static List<String> getNoteCategories() {
    return [
      'generalNote',
      'medicalNote',
      'labResult',
      'appointment',
      'prescription',
      'careNote',
    ];
  }

  /// Get category display names (legacy format)
  static Map<String, String> getCategoryDisplayNames() {
    return {
      'generalNote': 'General Note',
      'medicalNote': 'Medical Note',
      'labResult': 'Lab Result',
      'appointment': 'Appointment',
      'prescription': 'Prescription',
      'careNote': 'Care Note',
    };
  }
}
