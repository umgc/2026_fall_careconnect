import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/enhanced_patient_notes_widget.dart';
import 'package:care_connect_app/widgets/structured_entry_form.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/compliance/presentation/pages/compliance_checklist_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/services/structured_entry_service.dart';

class PatientFilesPage extends StatefulWidget {
  final int patientId;
  final String patientName;

  const PatientFilesPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientFilesPage> createState() => _PatientFilesPageState();
}

class _PatientFilesPageState extends State<PatientFilesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<UserFileDTO> _allFiles = [];
  List<UserFileDTO> _filteredFiles = [];
  bool _isLoading = false;
  String _selectedCategory = 'ALL';

  final Map<String, String> _categoryFilters = {
    'ALL': 'All Files',
    'MEDICAL_NOTE': 'Medical Notes',
    'MEDICAL_RECORD': 'Medical Records',
    'PRESCRIPTION': 'Prescriptions',
    'LAB_RESULT': 'Lab Results',
    'INSURANCE': 'Insurance',
    'REPORT': 'Reports',
    'OTHER_DOCUMENT': 'Other Documents',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final files = await EnhancedFileService.listPatientFiles(
        widget.patientId,
      );
      setState(() {
        _allFiles = files;
        _filterFiles();
      });
    } catch (e) {
      _showErrorSnackBar('Error loading files: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterFiles() {
    if (_selectedCategory == 'ALL') {
      _filteredFiles = List.from(_allFiles);
    } else {
      _filteredFiles = _allFiles
          .where((file) => file.fileCategory == _selectedCategory)
          .toList();
    }
  }

  void _onCategoryChanged(String? category) {
    if (category != null) {
      setState(() {
        _selectedCategory = category;
        _filterFiles();
      });
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  String _translateCategory(String value){
    final t = AppLocalizations.of(context)!;
    switch(value){
      case('All Files'):
        return t.ptfiles_allFilesItem;
      case('Medical Notes'):
        return t.ptfiles_medNotesItem;
      case('Medical Records'):
        return t.ptfiles_MedRecordItem;
      case('Prescriptions'):
        return t.ptfiles_prescripItem;
      case('Lab Results'):
        return t.ptfiles_labResItem;
      case('Insurance'):
        return t.ptfiles_insuranceItem;
      case('Reports'):
        return t.ptfiles_reprotItem;
      case('Other Documents'):
        return t.ptfiles_otherDocItem;
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: '${widget.patientName} - ${t.shortcut_files}',
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.fact_check),
            tooltip: 'Required documents checklist',
            onPressed: () {
              // Only coordinators may transition statuses (mirrors the
              // backend's requireAdminOrCaregiver); everyone else gets a
              // read-only checklist.
              final role = Provider.of<UserProvider>(context, listen: false)
                  .user
                  ?.role
                  .toUpperCase();
              final canEdit = role == 'CAREGIVER' || role == 'ADMIN';
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (routeContext) => ComplianceChecklistPage(
                    subjectType: 'CARE_CIRCLE',
                    subjectId: widget.patientId,
                    subjectName: widget.patientName,
                    canEdit: canEdit,
                  ),
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles),
        ],
      ),
      body: Column(
        children: [
          // Tab Bar
          Container(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: [
                Tab(icon: Icon(Icons.folder), text: t.ptfiles_allFilesItem),
                Tab(icon: Icon(Icons.note_add), text: t.ptfiles_quickUploadItem),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // All Files Tab
                _buildAllFilesTab(),

                // Quick Upload Tab
                _buildQuickUploadTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllFilesTab() {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        // Category Filter
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '${t.ptfiles_filtersCate}:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  items: _categoryFilters.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(_translateCategory(entry.value)),
                    );
                  }).toList(),
                  onChanged: _onCategoryChanged,
                ),
              ),
            ],
          ),
        ),

        // Files List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredFiles.isEmpty
              ? _buildEmptyState()
              : _buildFilesList(),
        ),
      ],
    );
  }

  Widget _buildQuickUploadTab() {
    final t = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.ptfiles_uploadPtFiles,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${t.ptfiles_uploadFileDescr} ${widget.patientName}.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),

            // Enhanced Patient Notes Widget for upload
            EnhancedPatientNotesWidget(
              patientId: widget.patientId,
              showCompactView: true,
              initialItemCount: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _selectedCategory == 'ALL'
                ? t.ptfiles_noFilesUploaded
                : '${t.ptfiles_noFilesIn} ${_categoryFilters[_selectedCategory]} ${t.ptfiles_category}',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            t.ptfiles_quickUploadDescrip,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _tabController.animateTo(1),
            icon: const Icon(Icons.add),
            label: Text(t.ptfiles_uploadFilesButton),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        return _buildFileCard(file);
      },
    );
  }

  Widget _buildFileCard(UserFileDTO file) {
    final t = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'structured':
                _openStructuredEntry(file);
                break;
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
            if (DocumentFieldTemplates.isSupported(file.fileCategory))
              const PopupMenuItem(
                value: 'structured',
                child: ListTile(
                  leading: Icon(Icons.edit_note),
                  title: Text('Structured entry'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              value: 'preview',
              child: ListTile(
                leading: Icon(Icons.visibility),
                title: Text(t.ptfiles_previewButton),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'download',
              child: ListTile(
                leading: Icon(Icons.download),
                title: Text(t.ptfiles_downloadButton),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text(t.ptfiles_deleteButton, style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: () => _previewFile(file),
      ),
    );
  }

  /// Opens the structured form-entry dialog for [file] in this patient's
  /// context — creating a new entry, or editing the one already captured
  /// from this document.
  Future<void> _openStructuredEntry(UserFileDTO file) async {
    StructuredEntryDTO? existing;
    try {
      existing = await StructuredEntryService.getEntryForFile(file.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load structured entry: $e')),
      );
      return;
    }
    if (!mounted) return;

    final saved = await StructuredEntryFormDialog.show(
      context,
      fileId: file.id,
      fileName: file.originalFilename.isNotEmpty
          ? file.originalFilename
          : file.fileName,
      fileCategory: file.fileCategory,
      patientId: file.patientId ?? widget.patientId,
      existingEntry: existing,
    );
    if (saved == true) {
      await _loadFiles();
    }
  }

  void _previewFile(UserFileDTO file) {
    final t = AppLocalizations.of(context)!;
    if (file.isPreviewable) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.9,
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
                        icon: const Icon(Icons.download, color: Colors.white),
                        onPressed: () => _downloadFile(file),
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
                                return InteractiveViewer(
                                  child: Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.contain,
                                  ),
                                );
                              }
                              return Center(
                                child: Text(t.ptfiles_failedToLoadImage),
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
                                  t.ptfiles_documentPreview,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${t.ptfiles_file}: ${file.originalFilename}',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${t.ptfiles_size}: ${_formatFileSize(file.fileSize)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if (file.description != null &&
                                    file.description!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${t.ptfiles_descrip}: ${file.description}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _downloadFile(file),
                                  icon: const Icon(Icons.download),
                                  label: Text(t.ptfiles_downloadViewButton),
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

  Future<void> _downloadFile(UserFileDTO file) async {
    final t = AppLocalizations.of(context)!;
    try {
      final fileBytes = await EnhancedFileService.downloadFile(file.id);
      if (fileBytes != null) {
        // Implementation depends on platform
        // For web, use the browser download
        // For mobile, save to device storage
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.ptfiles_fileDownloadSuccess),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _showErrorSnackBar(t.ptfiles_fileDownloadFailed);
      }
    } catch (e) {
      _showErrorSnackBar('${t.ptfiles_fileDownloadError}: $e');
    }
  }

  Future<void> _deleteFile(UserFileDTO file) async {
    final t = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.ptfiles_deleteFile),
        content: Text(
          '${t.ptfiles_deleteFileDialog} "${file.originalFilename}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(t.ptfiles_deleteButton),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await EnhancedFileService.deleteFile(file.id);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t.ptfiles_fileDeleteSuccess),
              backgroundColor: Colors.green,
            ),
          );
          await _loadFiles(); // Reload files
        } else {
          _showErrorSnackBar(t.ptfiles_fileDeleteFailed);
        }
      } catch (e) {
        _showErrorSnackBar('${t.ptfiles_fileDeleteError}: $e');
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    final t = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return t.ptfiles_today;
    } else if (difference.inDays == 1) {
      return t.ptfiles_yesterday;
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ${t.ptfiles_daysAgo}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
