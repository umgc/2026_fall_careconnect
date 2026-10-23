import 'package:flutter/material.dart';
import '../services/comprehensive_file_service.dart';
import '../services/medical_notes_service.dart';
import '../config/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class PatientNotesWidget extends StatefulWidget {
  final int patientId;
  final bool isReadOnly;
  final String patientName;
  final String? filterCategory; // Optional filter for specific note types

  const PatientNotesWidget({
    super.key,
    required this.patientId,
    this.isReadOnly = false,
    required this.patientName,
    this.filterCategory,
  });

  @override
  State<PatientNotesWidget> createState() => _PatientNotesWidgetState();
}

class _PatientNotesWidgetState extends State<PatientNotesWidget> {
  List<PatientNote> _patientNotes = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _error;
  String _selectedCategory = 'generalNote';

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.filterCategory ?? 'generalNote';
    _loadPatientNotes();
  }

  Future<void> _loadPatientNotes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final notes = await PatientNotesService.getPatientNotes(
        widget.patientId,
        category: widget.filterCategory, // Use filter if provided
      );
      setState(() {
        _patientNotes = notes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load patient notes: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _uploadPatientNote() async {
    try {
      // Use the comprehensive file service to pick and upload medical documents
      final file = await ComprehensiveFileService.pickFileForCategory(
        FileCategory.medicalReport,
      );
      if (file == null) return;

      // Validate the file
      if (!ComprehensiveFileService.validateFileForCategory(
        file,
        FileCategory.medicalReport,
      )) {
        _showErrorSnackBar('Invalid file type for medical document');
        return;
      }

      final fileName = file.path.split('/').last;

      // Show dialog to get title, description, and category
      final noteDetails = await _showNoteDetailsDialog(fileName);
      if (noteDetails != null) {
        setState(() {
          _isUploading = true;
        });

        try {
          // Upload using the comprehensive file service
          final response = await ComprehensiveFileService.uploadMedicalDocument(
            patientId: widget.patientId,
            documentFile: file,
            category: FileCategory.medicalReport,
            description:
                '${noteDetails['title']}: ${noteDetails['content'] ?? ''}',
          );

          if (response != null) {
            _showSuccessSnackBar(
              'Medical document uploaded successfully: ${response.originalFilename}',
            );
            // Refresh the notes list if needed
            await _loadPatientNotes();
          } else {
            _showErrorSnackBar('Failed to upload medical document');
          }
        } catch (e) {
          _showErrorSnackBar('Error uploading document: $e');
        } finally {
          setState(() {
            _isUploading = false;
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error selecting file: $e');
    }
  }

  Future<Map<String, String>?> _showNoteDetailsDialog(String fileName) async {
    final titleController = TextEditingController(text: fileName);
    final contentController = TextEditingController();
    String selectedCategory = _selectedCategory;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Note Details'),
          content: SingleChildScrollView(
            child: Column(
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
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Note Type',
                    border: OutlineInputBorder(),
                  ),
                  items: PatientNotesService.getCategoryDisplayNames()
                      .entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedCategory = value;
                      });
                    }
                  },
                ),
              ],
            ),
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
                    'content': contentController.text,
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

  Future<void> _editPatientNote(PatientNote note) async {
    final titleController = TextEditingController(text: note.title);
    final contentController = TextEditingController(text: note.content);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Patient Note'),
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
            TextField(
              controller: contentController,
              decoration: const InputDecoration(
                labelText: 'Description',
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
                  'content': contentController.text,
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final updatedNote = await PatientNotesService.updatePatientNote(
          noteId: note.id,
          title: result['title']!,
          content: result['content'] ?? '',
        );

        if (updatedNote != null) {
          setState(() {
            final index = _patientNotes.indexWhere((n) => n.id == note.id);
            if (index != -1) {
              _patientNotes[index] = updatedNote;
            }
          });
          _showSuccessSnackBar('Patient note updated successfully');
        } else {
          _showErrorSnackBar('Failed to update patient note');
        }
      } catch (e) {
        _showErrorSnackBar('Error updating patient note: $e');
      }
    }
  }

  Future<void> _deletePatientNote(PatientNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Patient Note'),
        content: Text('Are you sure you want to delete "${note.title}"?'),
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
        final success = await PatientNotesService.deletePatientNote(note.id);
        if (success) {
          setState(() {
            _patientNotes.removeWhere((n) => n.id == note.id);
          });
          _showSuccessSnackBar('Patient note deleted successfully');
        } else {
          _showErrorSnackBar('Failed to delete patient note');
        }
      } catch (e) {
        _showErrorSnackBar('Error deleting patient note: $e');
      }
    }
  }

  Future<void> _downloadPatientNote(PatientNote note) async {
    try {
      final downloadUrl = await PatientNotesService.downloadPatientNote(
        note.id,
      );
      if (downloadUrl != null) {
        if (await canLaunchUrl(Uri.parse(downloadUrl))) {
          await launchUrl(Uri.parse(downloadUrl));
        } else {
          _showErrorSnackBar('Cannot open file');
        }
      } else {
        _showErrorSnackBar('Failed to get download link');
      }
    } catch (e) {
      _showErrorSnackBar('Error downloading patient note: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.success),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Patient Notes',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (!widget.isReadOnly)
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadPatientNote,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(_isUploading ? 'Uploading...' : 'Upload Note'),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Content
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Card(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.errorDarkTheme.withOpacity(0.1)
                : AppTheme.error.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.error,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.errorDarkTheme
                        : AppTheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.errorDarkTheme
                          : AppTheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadPatientNotes,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        else if (_patientNotes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.medical_information_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No patient notes found',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isReadOnly
                        ? 'No patient notes have been uploaded for ${widget.patientName}'
                        : 'Upload your first patient note to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _patientNotes.length,
            itemBuilder: (context, index) {
              final note = _patientNotes[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    child: Icon(
                      _getFileIcon(note.fileName),
                      color: AppTheme.primary,
                    ),
                  ),
                  title: Text(
                    note.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (note.content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          note.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Uploaded: ${_formatDate(note.uploadDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        'By: ${note.uploadedBy}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'download':
                          _downloadPatientNote(note);
                          break;
                        case 'edit':
                          _editPatientNote(note);
                          break;
                        case 'delete':
                          _deletePatientNote(note);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'download',
                        child: ListTile(
                          leading: Icon(Icons.download),
                          title: Text('Download'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (!widget.isReadOnly) ...[
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete, color: AppTheme.error),
                            title: Text(
                              'Delete',
                              style: TextStyle(color: AppTheme.error),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.attach_file;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
