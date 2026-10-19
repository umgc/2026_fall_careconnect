import 'dart:io';
import 'dart:typed_data';

import 'package:care_connect_app/abstracts/file_handler.dart';
import 'package:care_connect_app/factories/file_handler_factory.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/theme/app_theme.dart';
import '../services/enhanced_file_service.dart';

class EnhancedPatientNotesWidget extends StatefulWidget {
  final int patientId;
  final bool showCompactView;
  final int initialItemCount;

  const EnhancedPatientNotesWidget({
    super.key,
    required this.patientId,
    this.showCompactView = false,
    this.initialItemCount = 3,
  });

  @override
  State<EnhancedPatientNotesWidget> createState() =>
      _EnhancedPatientNotesWidgetState();
}

class _EnhancedPatientNotesWidgetState
    extends State<EnhancedPatientNotesWidget> {
  List<UserFileDTO> _allFiles = [];
  List<UserFileDTO> _displayedFiles = [];
  bool _isLoading = false;
  bool _isUploading = false;
  bool _showingAll = false;
  final String _selectedCategory = 'MEDICAL_NOTE';
  late final FileHandler _fileHandler;

  // Categories for notes
  final Map<String, String> _noteCategories = {
    'MEDICAL_NOTE': 'Medical Note',
    'GENERAL_NOTE': 'General Note',
    'LAB_RESULT': 'Lab Result',
    'APPOINTMENT': 'Appointment',
    'PRESCRIPTION': 'Prescription',
    'CARE_NOTE': 'Care Note',
    'OTHER_DOCUMENT': 'Other Document',
  };

  @override
  void initState() {
    super.initState();
    _loadPatientFiles();
    _fileHandler = FileHandlerFactory.create();
  }

  @override
  void didUpdateWidget(EnhancedPatientNotesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId) {
      _loadPatientFiles();
    }
  }

  Future<void> _loadPatientFiles() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final files = await EnhancedFileService.listPatientFiles(
        widget.patientId,
      );

      setState(() {
        _allFiles = files;
        _updateDisplayedFiles();
      });
    } catch (e) {
      _showErrorSnackBar('Error loading patient files: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateDisplayedFiles() {
    if (_showingAll || widget.showCompactView) {
      _displayedFiles = List.from(_allFiles);
    } else {
      _displayedFiles = _allFiles.take(widget.initialItemCount).toList();
    }
  }

  void _toggleShowAll() {
    setState(() {
      _showingAll = !_showingAll;
      _updateDisplayedFiles();
    });
  }

  Future<void> _uploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'txt'],
      allowMultiple: false,
    );

    if (result != null) {
      final file = result.files.first;

      // Show note details dialog
      final noteDetails = await _showNoteDetailsDialog(file.name);
      if (noteDetails == null) return;

      setState(() {
        _isUploading = true;
      });

      try {
        // Use platform handler to process file
        final fileResult = await _fileHandler.processPickedFile(
          file.path,
          file.name,
          file.bytes,
        );

        final fileToUpload = File(fileResult.filePath);

        final response = await EnhancedFileService.uploadFile(
          file: fileToUpload,
          category: noteDetails['category']!,
          description: noteDetails['description'],
          patientId: widget.patientId,
        );

        // Clean up temporary file if needed
        if (fileResult.isTemporary) {
          try {
            await fileToUpload.delete();
          } catch (e) {
            // Ignore cleanup errors
          }
        }

        if (response != null) {
          _showSuccessSnackBar('File uploaded successfully');
          await _loadPatientFiles();
        } else {
          _showErrorSnackBar('Failed to upload file');
        }
      } catch (e) {
        _showErrorSnackBar('Error uploading file: $e');
      } finally {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<Map<String, String>?> _showNoteDetailsDialog(String fileName) async {
    final titleController = TextEditingController(text: fileName);
    final descriptionController = TextEditingController();
    String selectedCategory = _selectedCategory;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('File Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  border: OutlineInputBorder(),
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category *',
                  border: OutlineInputBorder(),
                ),
                items: _noteCategories.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedCategory = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  Navigator.of(context).pop({
                    'title': titleController.text,
                    'description': descriptionController.text,
                    'category': selectedCategory,
                  });
                }
              },
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFile(UserFileDTO file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${file.originalFilename}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.errorDarkTheme
                  : AppTheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await EnhancedFileService.deleteFile(file.id);
        if (success) {
          _showSuccessSnackBar('File deleted successfully');
          await _loadPatientFiles(); // Reload files
        } else {
          _showErrorSnackBar('Failed to delete file');
        }
      } catch (e) {
        _showErrorSnackBar('Error deleting file: $e');
      }
    }
  }

  Future<void> _downloadFile(UserFileDTO file) async {
    try {
      final fileBytes = await EnhancedFileService.downloadFile(file.id);
      if (fileBytes != null) {
        // Use platform handler for download
        await _fileHandler.downloadFile(
          file.originalFilename,
          fileBytes,
          file.contentType,
        );
        _showSuccessSnackBar('File downloaded successfully');
      } else {
        _showErrorSnackBar('Failed to download file');
      }
    } catch (e) {
      _showErrorSnackBar('Error downloading file: $e');
    }
  }

  void _previewFile(UserFileDTO file) {
    if (file.isPreviewable) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          file.originalFilename,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: file.isImage
                        ? FutureBuilder<Uint8List?>(
                            future: EnhancedFileService.downloadFile(file.id),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                );
                              }
                              return const Center(
                                child: Text('Failed to load image'),
                              );
                            },
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.description,
                                  size: 64,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Document Preview',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'File: ${file.originalFilename}',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Size: ${_formatFileSize(file.fileSize)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _downloadFile(file),
                                  icon: const Icon(Icons.download),
                                  label: const Text('Download to View'),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      _downloadFile(file);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.note_add, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Patient Notes & Documents',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (!_isUploading)
                  ElevatedButton.icon(
                    onPressed: _uploadFile,
                    icon: const Icon(Icons.add),
                    label: const Text('Add File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  )
                else
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Loading indicator
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_displayedFiles.isEmpty)
              // Empty state
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.note_add_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No files uploaded yet',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload documents, images, or notes for this patient',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              // Files list
              Column(
                children: [
                  ..._displayedFiles.map((file) => _buildFileItem(file)),

                  // Load more button
                  if (!widget.showCompactView &&
                      _allFiles.length > widget.initialItemCount)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: _toggleShowAll,
                          icon: Icon(
                            _showingAll ? Icons.expand_less : Icons.expand_more,
                          ),
                          label: Text(
                            _showingAll
                                ? 'Show Less'
                                : 'Show All (${_allFiles.length} files)',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem(UserFileDTO file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
          child: Text(file.fileIcon, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(
          file.originalFilename,
          style: const TextStyle(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.categoryDisplayName),
            if (file.description != null && file.description!.isNotEmpty)
              Text(
                file.description!,
                style: TextStyle(color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              '${_formatFileSize(file.fileSize)}}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'preview':
                _previewFile(file);
                break;
              case 'download':
                _downloadFile(file);
                break;
              case 'delete':
                _deleteFile(file);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'preview',
              child: ListTile(
                leading: Icon(Icons.visibility),
                title: Text('Preview'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'download',
              child: ListTile(
                leading: Icon(Icons.download),
                title: Text('Download'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Delete', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: () => _previewFile(file),
      ),
    );
  }
}
