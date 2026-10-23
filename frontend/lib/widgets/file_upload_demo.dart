import 'package:flutter/material.dart';
import '../services/comprehensive_file_service.dart';
import '../services/enhanced_file_service.dart';
import '../widgets/file_upload_widget.dart';

/// Demo widget showing how to use the comprehensive file upload system
class FileUploadDemo extends StatefulWidget {
  const FileUploadDemo({super.key});

  @override
  State<FileUploadDemo> createState() => _FileUploadDemoState();
}

class _FileUploadDemoState extends State<FileUploadDemo> {
  List<UserFileDTO> _uploadedFiles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user files
      final files = await ComprehensiveFileService.getAllUserFiles(
        1, // Replace with actual user ID
        params: FileQueryParams(size: 20, sort: 'createdAt,desc'),
      );

      setState(() {
        _uploadedFiles = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Error loading files: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File Upload Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Demo of comprehensive file upload widget
            Text(
              'Comprehensive File Upload',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            FileUploadWidget(
              onUploadSuccess: (response) {
                _showSnackBar('File uploaded: ${response.originalFilename}');
                _loadFiles(); // Refresh the list
              },
              onUploadError: (error) {
                _showSnackBar(error, isError: true);
              },
            ),
            const SizedBox(height: 24),

            // Demo of quick upload buttons
            Text(
              'Quick Upload Examples',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickUploadButton(
                  'Profile Photo',
                  Icons.person,
                  FileCategory.profilePicture,
                ),
                _buildQuickUploadButton(
                  'Medical Report',
                  Icons.medical_services,
                  FileCategory.medicalReport,
                ),
                _buildQuickUploadButton(
                  'Prescription',
                  Icons.medication,
                  FileCategory.prescription,
                ),
                _buildQuickUploadButton(
                  'Lab Result',
                  Icons.science,
                  FileCategory.labResult,
                ),
                _buildQuickUploadButton(
                  'Insurance Doc',
                  Icons.security,
                  FileCategory.insuranceDoc,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Demo of API integration examples
            Text(
              'API Integration Examples',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available API Endpoints',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildApiExample(
                      'GET',
                      '/v1/api/files/users/{id}',
                      'Get all user files',
                    ),
                    _buildApiExample(
                      'GET',
                      '/v1/api/files/users/{id}?category=MEDICAL_REPORT',
                      'Get files by category',
                    ),
                    _buildApiExample(
                      'GET',
                      '/v1/api/files/patients/{id}/documents',
                      'Get patient medical documents',
                    ),
                    _buildApiExample(
                      'GET',
                      '/v1/api/files/search?query={term}&userId={id}',
                      'Search files',
                    ),
                    _buildApiExample(
                      'POST',
                      '/v1/api/files/upload',
                      'Upload file',
                    ),
                    _buildApiExample(
                      'DELETE',
                      '/v1/api/files/{id}',
                      'Delete file',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Display uploaded files
            Text(
              'Recently Uploaded Files',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _uploadedFiles.isEmpty
                    ? Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.folder_open,
                                  size: 48,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.5),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No files uploaded yet',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: _uploadedFiles
                            .map((file) => _buildFileCard(file))
                            .toList(),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickUploadButton(
    String label,
    IconData icon,
    FileCategory category,
  ) {
    return ElevatedButton.icon(
      onPressed: () => _quickUpload(category),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildApiExample(String method, String endpoint, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getMethodColor(method),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              method,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  endpoint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return Colors.green;
      case 'POST':
        return Colors.blue;
      case 'PUT':
        return Colors.orange;
      case 'DELETE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildFileCard(UserFileDTO file) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withOpacity(0.1),
          child: Text(file.fileIcon, style: const TextStyle(fontSize: 16)),
        ),
        title: Text(
          file.originalFilename,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${file.categoryDisplayName} • ${_formatFileSize(file.fileSize)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleFileAction(action, file),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download, size: 16),
                  SizedBox(width: 8),
                  Text('Download'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 16, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickUpload(FileCategory category) async {
    try {
      final file = await ComprehensiveFileService.pickFileForCategory(category);
      if (file == null) return;

      if (!ComprehensiveFileService.validateFileForCategory(file, category)) {
        _showSnackBar(
          'Invalid file type for ${category.displayName}',
          isError: true,
        );
        return;
      }

      // Show loading
      _showSnackBar('Uploading ${category.displayName}...');

      FileUploadResponse? response;

      switch (category) {
        case FileCategory.profilePicture:
          response = await ComprehensiveFileService.uploadProfileImage(
            userId: 1, // Replace with actual user ID
            imageFile: file,
          );
          break;
        case FileCategory.medicalReport:
        case FileCategory.labResult:
          response = await ComprehensiveFileService.uploadMedicalDocument(
            patientId: 1, // Replace with actual patient ID
            documentFile: file,
            category: category,
          );
          break;
        case FileCategory.prescription:
          response = await ComprehensiveFileService.uploadPrescription(
            patientId: 1, // Replace with actual patient ID
            prescriptionFile: file,
          );
          break;
        case FileCategory.insuranceDoc:
          response = await ComprehensiveFileService.uploadInsuranceDocument(
            patientId: 1, // Replace with actual patient ID
            insuranceFile: file,
          );
          break;
        default:
          // Use enhanced file service for other types
          response = await EnhancedFileService.uploadFile(
            file: file,
            category: category.value,
          );
          break;
      }

      if (response != null) {
        _showSnackBar('${category.displayName} uploaded successfully!');
        _loadFiles(); // Refresh the list
      } else {
        _showSnackBar(
          'Failed to upload ${category.displayName}',
          isError: true,
        );
      }
    } catch (e) {
      _showSnackBar(
        'Error uploading ${category.displayName}: $e',
        isError: true,
      );
    }
  }

  void _handleFileAction(String action, UserFileDTO file) async {
    switch (action) {
      case 'download':
        try {
          _showSnackBar('Downloading ${file.originalFilename}...');
          final fileData = await EnhancedFileService.downloadFile(file.id);
          if (fileData != null) {
            _showSnackBar('Downloaded ${file.originalFilename}');
          } else {
            _showSnackBar('Failed to download file', isError: true);
          }
        } catch (e) {
          _showSnackBar('Download error: $e', isError: true);
        }
        break;
      case 'delete':
        _showDeleteConfirmation(file);
        break;
    }
  }

  void _showDeleteConfirmation(UserFileDTO file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${file.originalFilename}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();

              final success = await EnhancedFileService.deleteFile(file.id);
              if (success) {
                _showSnackBar('Deleted ${file.originalFilename}');
                _loadFiles(); // Refresh the list
              } else {
                _showSnackBar(
                  'Failed to delete ${file.originalFilename}',
                  isError: true,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
