import 'dart:io';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../services/comprehensive_file_service.dart';
import '../services/enhanced_file_service.dart';
import '../services/structured_entry_service.dart';
import '../providers/user_provider.dart';
import '../config/theme/app_theme.dart';
import '../features/compliance/presentation/pages/compliance_dashboard_page.dart';
import '../features/homecare_documents/widgets/home_care_digitization_card.dart';
import '../widgets/file_upload_widget.dart';
import '../widgets/manual_text_entry_upload.dart';
import '../widgets/speech_to_text_widget.dart';
import '../widgets/forms/hiring_forms_tab.dart';
import '../widgets/structured_entry_form.dart';

/// Comprehensive file management page
class FileManagementPage extends StatefulWidget {
  const FileManagementPage({super.key});

  @override
  State<FileManagementPage> createState() => _FileManagementPageState();
}

class _FileManagementPageState extends State<FileManagementPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<UserFileDTO> _allFiles = [];
  List<UserFileDTO> _filteredFiles = [];
  bool _isLoading = true;
  String _searchQuery = '';
  FileCategory? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  int? _userId;

  /// Hiring/onboarding forms are caregiver-only, so the tab is shown only for
  /// caregiver accounts.
  bool _isCaregiver = false;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<UserProvider>(context, listen: false).user;
    _isCaregiver = user?.role.toUpperCase() == 'CAREGIVER';
    // 4 tabs for caregivers (incl. Hiring Forms), 3 for everyone else.
    _tabController = TabController(length: _isCaregiver ? 4 : 3, vsync: this);
    _loadFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      if (user == null) return;

      final files = await ComprehensiveFileService.getAllUserFiles(
        user.id,
        params: FileQueryParams(size: 100, sort: 'createdAt,desc'),
      );

      setState(() {
        _allFiles = files;
        _filteredFiles = files;
        _userId = user.id;
        _isLoading = false;
        print(
          'DEBUG: Category set as: $_selectedCategory, Files set as: $files',
        );
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      final t = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t.filemanage_errorLoadingFiles}: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _filterFiles() {
    setState(() {
      _filteredFiles = _allFiles.where((file) {
        final matchesSearch =
            _searchQuery.isEmpty ||
            file.originalFilename.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ) ||
            (file.description?.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ??
                false);

        final matchesCategory =
            _selectedCategory == null ||
            file.fileCategory == _selectedCategory!.value;

        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;
    final t = AppLocalizations.of(context)!;
    if (user == null) {
      Future.microtask(() => Navigator.pushReplacementNamed(context, '/login'));
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isAdmin = user.role.toUpperCase() == 'ADMIN';
    return Scaffold(
      appBar: AppBar(
        title: Text(t.fileManagement),
        actions: [
          if (_isCaregiver || isAdmin)
            IconButton(
              icon: const Icon(Icons.fact_check),
              tooltip: 'Document compliance dashboard',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (routeContext) =>
                        const ComplianceDashboardPage(),
                  ),
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // Size each tab to its label and allow horizontal scrolling so the
          // longest label ("Hiring Forms") is shown in full on narrow screens
          // instead of being clipped at the edge.
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(icon: Icon(Icons.folder), text: t.filemanage_myFiles),
            Tab(icon: Icon(Icons.cloud_upload), text: t.filemanage_upload),
            Tab(icon: Icon(Icons.analytics), text: t.navAnalytics),
            // Hiring/onboarding forms are caregiver-only.
            if (_isCaregiver)
              Tab(icon: Icon(Icons.assignment), text: t.filemanage_hiringForms),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFilesTab(),
          _buildUploadTab(),
          _buildAnalyticsTab(),
          if (_isCaregiver) const HiringFormsTab(),
        ],
      ),
    );
  }

  Widget _buildFilesTab() {
    return Column(
      children: [
        _buildSearchAndFilter(),
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

  String _translateCategory(String name){
    final t = AppLocalizations.of(context)!;
    switch(name){
      case('Medical Report'):
        return t.filemanage_medReport;
      case('Lab Result'):
        return t.filemanage_labResult;
      case('Prescription'):
        return t.filemanage_prescription;
      case('Clinical Notes'): 
        return t.filemanage_clinicNotes;
      case('Profile Picture'): 
        return t.filemanage_profilePic;
      case('Emergency Contact'):
        return t.filemanage_emgContact;
      case('Insurance Document'):
        return t.filemanage_insurDocument;
      case('AI Chat File'):
        return t.filemanage_aiChatFile;
      case('General Document'):
        return t.filemanage_genDocument;
      case('Health Data Import'):
        return t.filemanage_hlthDataImport;
      case('Backup File'):
        return t.filemanage_backupFile;
      default:
        return name;
    }
  }

  Widget _buildSearchAndFilter() {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: '${t.filemanage_searchFiles}...',
              hintText: t.filemanage_searchByDescr,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                        _filterFiles();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
              _filterFiles();
            },
          ),
          const SizedBox(height: 12),

          // Category filter
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<FileCategory?>(
                  initialValue: _selectedCategory,
                  decoration: AppTheme.inputDecoration(t.filemanage_filterByCat),
                  items: [
                    DropdownMenuItem<FileCategory?>(
                      value: null,
                      child: Text(t.filemanage_allCats),
                    ),
                    ...FileCategory.values.map((category) {
                      return DropdownMenuItem<FileCategory?>(
                        value: category,
                        child: Row(
                          children: [
                            Text(category.icon),
                            const SizedBox(width: 8),
                            Text(_translateCategory(category.displayName)),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (FileCategory? newValue) {
                    setState(() {
                      _selectedCategory = newValue;
                    });
                    _filterFiles();
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _loadFiles,
                icon: const Icon(Icons.refresh),
                tooltip: t.filemanage_refreshFiles,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _selectedCategory != null
                ? t.filemanage_noFilesMatchFilter
                : t.ptfiles_noFilesUploaded,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedCategory != null
                ? t.filemanage_tryAdjustingCriteria
                : t.filemanage_uploadFirstFile,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isEmpty && _selectedCategory == null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(1),
              style: AppTheme.primaryButtonStyle,
              icon: const Icon(Icons.cloud_upload),
              label: Text(t.ptfiles_uploadFilesButton),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilesList() {
    return RefreshIndicator(
      onRefresh: _loadFiles,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredFiles.length,
        itemBuilder: (context, index) {
          final file = _filteredFiles[index];
          return _buildFileCard(file);
        },
      ),
    );
  }

  Widget _buildFileCard(UserFileDTO file) {
    // File Name Only
    // Get index of last dot
    int dotIndex = file.fileName.lastIndexOf('.');

    // Extract filename without extension
    String baseName = (dotIndex != -1)
        ? file.fileName.substring(0, dotIndex)
        : file.fileName; // If no dot found, return full filename

    // Extension Name Only
    String getFileExtension(String fileName) {
      int dotIndex = fileName.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex != fileName.length - 1) {
        return fileName.substring(dotIndex);
      }
      return ''; // No extension found
    }

    // Usage:
    String fileExtension = getFileExtension(file.fileName);
    String extensionWithoutDot = fileExtension.replaceFirst('.', ''); // txt

    final theme = Theme.of(context);
    final t = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
          child: Text(
            file.fileIcon,
            style:
                theme.textTheme.titleLarge?.copyWith(fontSize: 20) ??
                const TextStyle(fontSize: 20),
          ),
        ),
        title: Text(
          baseName,
          style:
              theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ) ??
              AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  file.categoryDisplayName,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(' • ', style: theme.textTheme.bodyMedium),
                Text(
                  _formatFileSize(file.fileSize),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(' • ', style: theme.textTheme.bodyMedium),
                Text(extensionWithoutDot, style: theme.textTheme.bodyMedium),
              ],
            ),
            if (file.description != null && file.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                file.description!,
                style: theme.textTheme.bodySmall ?? AppTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'structured':
                _openStructuredEntry(file);
                break;
              case 'download':
                // TODO: Implement download functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.filemanage_downloadFeatureComingSoon),
                    backgroundColor: AppTheme.info,
                  ),
                );
                break;
              case 'delete':
                // TODO: Implement delete functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.filemanage_deleteFeatureComingSoon),
                    backgroundColor: AppTheme.info,
                  ),
                );
                break;
            }
          },
          itemBuilder: (BuildContext context) => [
            if (DocumentFieldTemplates.isSupported(file.fileCategory))
              PopupMenuItem(
                value: 'structured',
                child: ListTile(
                  leading: Icon(Icons.edit_note, color: theme.iconTheme.color),
                  title: Text(
                    'Structured entry',
                    style: theme.textTheme.bodyMedium,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            PopupMenuItem(
              value: 'download',
              child: ListTile(
                leading: Icon(Icons.download, color: theme.iconTheme.color),
                title: Text(t.ptfiles_downloadButton, style: theme.textTheme.bodyMedium),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (file.isPreviewable)
              PopupMenuItem(
                value: 'preview',
                child: ListTile(
                  leading: Icon(Icons.visibility, color: theme.iconTheme.color),
                  title: Text(t.ptfiles_previewButton, style: theme.textTheme.bodyMedium),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: theme.colorScheme.error),
                title: Text(
                  t.ptfiles_deleteButton,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadTab() {
    final t = AppLocalizations.of(context)!;
    return Container(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.filemanage_fileUpload, style: AppTheme.headingMedium),
            const SizedBox(height: 24),
            // Upload Instructions Card
            Card(
              color: Theme.of(context).colorScheme.surface,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.filemanage_fileUploadDescr,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Home Care Document Digitization (OCR + LLM prefill for review)
            HomeCareDigitizationCard(
              patientId: _userId,
              onSaved: () {
                _loadFiles(); // Refresh the files list
              },
            ),
            const SizedBox(height: 24),
            // File Upload Section
            FileUploadWidget(
              patientId: _userId,
              allowedCategories: FileCategory.values,
              onUploadSuccess: (response) {
                _loadFiles(); // Refresh the files list
              },
              onUploadError: (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // Manual Text Entry Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ManualTextEntryCard(
                  patientId: _userId,
                  onUploadSuccess: (response) {
                    _loadFiles(); // Refresh the files list
                  },
                  onUploadError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SpeechToTextCard(
                  patientId: _userId,
                  onUploadSuccess: (response) {
                    _loadFiles(); // Refresh the files list
                  },
                  onUploadError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  },
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    final categories = <String, int>{};
    final totalSize = _allFiles.fold<int>(
      0,
      (sum, file) => sum + file.fileSize,
    );

    // Count files by category
    for (final file in _allFiles) {
      categories[file.categoryDisplayName] =
          (categories[file.categoryDisplayName] ?? 0) + 1;
    }

    final t = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.filemanage_fileAnalytics, style: AppTheme.headingMedium),
          const SizedBox(height: 24),

          // Overview cards
          Row(
            children: [
              Expanded(
                child: _buildAnalyticsCard(
                  title: t.filemanage_totalFiles,
                  value: '${_allFiles.length}',
                  icon: Icons.folder,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildAnalyticsCard(
                  title: t.filemanage_totalSize,
                  value: _formatFileSize(totalSize),
                  icon: Icons.storage,
                  color: AppTheme.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Category breakdown
          Text(t.filemanage_filtersByCat, style: AppTheme.headingSmall),
          const SizedBox(height: 12),
          ...categories.entries.map((entry) {
            return Card(
              child: ListTile(
                title: Text(_translateCategory(entry.key)),
                trailing: CircleAvatar(
                  backgroundColor: AppTheme.primary,
                  radius: 16,
                  child: Text(
                    '${entry.value}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(value, style: AppTheme.headingMedium.copyWith(color: color)),
            Text(title, style: AppTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// Opens the structured form-entry dialog for [file] — creating a new
  /// entry, or editing the one already captured from this document. The
  /// patient/employee context is derived from the current user's role so it
  /// is always present before saving.
  Future<void> _openStructuredEntry(UserFileDTO file) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

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

    final isPatient = user.role.toUpperCase() == 'PATIENT';
    final saved = await StructuredEntryFormDialog.show(
      context,
      fileId: file.id,
      fileName: file.originalFilename.isNotEmpty
          ? file.originalFilename
          : file.fileName,
      fileCategory: file.fileCategory,
      patientId: file.patientId ?? (isPatient ? user.patientId : null),
      employeeUserId: isPatient ? null : user.id,
      existingEntry: existing,
    );
    if (saved == true) {
      _loadFiles();
    }
  }

  void _handleFileAction(String action, UserFileDTO file) async {
    switch (action) {
      case 'download':
        await _downloadFile(file);
        break;
      case 'preview':
        _previewFile(file);
        break;
      case 'info':
        _showFileInfo(file);
        break;
      case 'delete':
        _deleteFile(file);
        break;
    }
  }

  Future<void> _downloadFile(UserFileDTO file) async {
    final t = AppLocalizations.of(context)!;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t.filemanage_downloading} ${file.fileName}...'),
          duration: const Duration(seconds: 2),
        ),
      );

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      if (user == null) return;

      final fileData = await EnhancedFileService.downloadFileLegacy(
        user.id,
        file.fileUrl!,
      );

      if (fileData != null) {
        // 1. Get device's Download directory
        Directory? directory;
        if (Platform.isAndroid || Platform.isIOS) {
          directory =
              await getApplicationDocumentsDirectory(); // App-local storage
        } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          directory = await getDownloadsDirectory(); // User's Downloads folder
        }

        if (directory != null) {
          final filePath = '${directory.path}/${file.fileName}';
          final newFile = File(filePath);

          // 2. Write bytes to file
          await newFile.writeAsBytes(fileData);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${t.filemanage_fileSavedTo} ${newFile.path}'),
              backgroundColor: AppTheme.success,
            ),
          );
        } else {
          throw Exception(t.filemanage_couldNotAccessStorage);
        }
      } else {
        throw Exception(t.ptfiles_fileDownloadFailed);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t.filemanage_downloadFailed}: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _previewFile(UserFileDTO file) {
    // In a real app, you'd implement file preview
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.originalFilename),
        content: Text(t.filemanage_previewFunction),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showFileInfo(UserFileDTO file) {
    String extensionWithoutDot = file.fileName.replaceFirst('.', ''); // txt
    final t = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.originalFilename),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(t.filemanage_category, file.categoryDisplayName),
              _buildInfoRow(t.ptfiles_size, _formatFileSize(file.fileSize)),
              _buildInfoRow(t.filemanage_type, extensionWithoutDot),
              // Comment out created and updated date as they are not passed in from the API for now.
              // _buildInfoRow('Created', _formatDate(file.createdAt)),
              // _buildInfoRow('Updated', _formatDate(file.updatedAt)),
              if (file.description != null && file.description!.isNotEmpty)
                _buildInfoRow(t.ptfiles_descrip, file.description!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.filemanage_close),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value, style: AppTheme.bodyMedium)),
        ],
      ),
    );
  }

  void _deleteFile(UserFileDTO file) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.ptfiles_deleteFile),
        content: Text(
          '${t.ptfiles_deleteFileDialog} "${file.originalFilename}"? ${t.filemanage_cannotBeUndone}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();

              final success = await EnhancedFileService.deleteFile(file.id);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${t.filemanage_deleted} ${file.originalFilename}'),
                    backgroundColor: AppTheme.success,
                  ),
                );
                _loadFiles(); // Refresh the list
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${t.filemanage_failedToDelete} ${file.originalFilename}'),
                    backgroundColor: AppTheme.error,
                  ),
                );
              }
            },
            style: AppTheme.dangerButtonStyle,
            child: Text(t.ptfiles_deleteButton),
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
