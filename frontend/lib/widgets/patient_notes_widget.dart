import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/medical_notes_service.dart';
import '../config/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class PatientNotesWidget extends StatefulWidget {
  final int patientId;
  final bool isReadOnly;
  final String patientName;
  final String? defaultCategory; // Allow specifying default note category

  const PatientNotesWidget({
    super.key,
    required this.patientId,
    this.isReadOnly = false,
    required this.patientName,
    this.defaultCategory,
  });

  @override
  State<PatientNotesWidget> createState() => _PatientNotesWidgetState();
}

class _PatientNotesWidgetState extends State<PatientNotesWidget> {
  List<PatientNote> _patientNotes = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _error;
  String _selectedCategory = 'general';

  // Available note categories
  final Map<String, String> _categories = {
    'general': 'General Notes',
    'medical': 'Medical Information',
    'allergies': 'Allergies',
    'medications': 'Medications',
    'appointment': 'Appointments',
    'labResult': 'Lab Results',
    'insurance': 'Insurance',
  };

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.defaultCategory ?? 'general';
    _loadPatientNotes();
  }

  Future<void> _loadPatientNotes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final notes = await PatientNotesService.getPatientNotes(widget.patientId);
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;

      // Show dialog to get title and description
      final noteDetails = await _showNoteDetailsDialog(fileName);
      if (noteDetails != null) {
        setState(() {
          _isUploading = true;
        });

        try {
          final uploadedNote = await PatientNotesService.uploadPatientNote(
            patientId: widget.patientId,
            file: file,
            title: noteDetails['title']!,
            content: noteDetails['content'] ?? '',
            category: noteDetails['category']!,
          );

          if (uploadedNote != null) {
            setState(() {
              _patientNotes.insert(0, uploadedNote);
            });
            _showSuccessSnackBar('Patient note uploaded successfully');
          } else {
            _showErrorSnackBar('Failed to upload patient note');
          }
        } catch (e) {
          _showErrorSnackBar('Error uploading patient note: $e');
        } finally {
          setState(() {
            _isUploading = false;
          });
        }
      }
    }
  }

  Future<Map<String, String>?> _showNoteDetailsDialog(String fileName) async {
    final titleController = TextEditingController(text: fileName);
    final contentController = TextEditingController();
    String selectedCategory = _selectedCategory;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Patient Note Details'),
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
                items: _categories.entries.map((entry) {
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
                controller: contentController,
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

  List<PatientNote> get _filteredNotes {
    if (_selectedCategory == 'all') {
      return _patientNotes;
    }
    return _patientNotes
        .where((note) => note.category == _selectedCategory)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with category filter
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Patient Notes & Documents',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  // Category filter
                  DropdownButton<String>(
                    value: _selectedCategory,
                    hint: const Text('All Categories'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All Categories'),
                      ),
                      ..._categories.entries.map((entry) {
                        final count = _patientNotes
                            .where((note) => note.category == entry.key)
                            .length;
                        return DropdownMenuItem(
                          value: entry.key,
                          child: Text('${entry.value} ($count)'),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value ?? 'all';
                      });
                    },
                  ),
                ],
              ),
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
                label: Text(_isUploading ? 'Uploading...' : 'Add Note'),
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
        else if (_filteredNotes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    _getCategoryIcon(_selectedCategory),
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedCategory == 'all'
                        ? 'No notes found'
                        : 'No ${_categories[_selectedCategory]?.toLowerCase() ?? 'notes'} found',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isReadOnly
                        ? 'No ${_selectedCategory == 'all' ? 'notes' : _categories[_selectedCategory]?.toLowerCase()} have been uploaded for ${widget.patientName}'
                        : 'Upload your first ${_selectedCategory == 'all' ? 'note' : _categories[_selectedCategory]?.toLowerCase()} to get started',
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
            itemCount: _filteredNotes.length,
            itemBuilder: (context, index) {
              final note = _filteredNotes[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getCategoryColor(
                      note.category,
                    ).withOpacity(0.1),
                    child: Icon(
                      _getCategoryIcon(note.category),
                      color: _getCategoryColor(note.category),
                    ),
                  ),
                  title: Text(
                    note.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show category badge
                      Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(
                            note.category,
                          ).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          note.noteType,
                          style: TextStyle(
                            fontSize: 11,
                            color: _getCategoryColor(note.category),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (note.content.isNotEmpty) ...[
                        Text(
                          note.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'medical':
        return Icons.medical_information;
      case 'allergies':
        return Icons.error_outline;
      case 'medications':
        return Icons.medication;
      case 'appointment':
        return Icons.calendar_today;
      case 'labResult':
        return Icons.science;
      case 'insurance':
        return Icons.policy;
      case 'all':
        return Icons.folder_open;
      default:
        return Icons.note;
    }
  }

  Color _getCategoryColor(String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (category) {
      case 'medical':
        return isDark ? AppTheme.errorDarkTheme : AppTheme.error;
      case 'allergies':
        return isDark ? AppTheme.warningDarkTheme : AppTheme.warning;
      case 'medications':
        return isDark ? AppTheme.primaryDarkTheme : AppTheme.primary;
      case 'appointment':
        return isDark ? AppTheme.successDarkTheme : AppTheme.success;
      case 'labResult':
        return isDark ? AppTheme.primaryDarkThemeLight : AppTheme.primaryLight;
      case 'insurance':
        return isDark ? AppTheme.infoDarkTheme : AppTheme.info;
      default:
        return isDark ? AppTheme.primaryDarkTheme : AppTheme.primary;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
