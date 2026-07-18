import 'dart:io';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/comprehensive_file_service.dart';
import '../services/enhanced_file_service.dart';
import '../providers/user_provider.dart';
import '../config/theme/app_theme.dart';

/// Comprehensive file upload widget for CareConnect
class FileUploadWidget extends StatefulWidget {
  final FileCategory? defaultCategory;
  final int? patientId;
  final Function(FileUploadResponse)? onUploadSuccess;
  final Function(String)? onUploadError;
  final bool showCategorySelector;
  final String? customTitle;
  final List<FileCategory>? allowedCategories;

  const FileUploadWidget({
    super.key,
    this.defaultCategory,
    this.patientId,
    this.onUploadSuccess,
    this.onUploadError,
    this.showCategorySelector = true,
    this.customTitle,
    this.allowedCategories,
  });

  @override
  State<FileUploadWidget> createState() => _FileUploadWidgetState();
}

class _FileUploadWidgetState extends State<FileUploadWidget> {
  FileCategory? _selectedCategory;
  bool _isUploading = false;
  File? _selectedFile;
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final categories = _availableCategories;
  }


  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  List<FileCategory> get _availableCategories1 {
    if (widget.allowedCategories != null && widget.allowedCategories!.isNotEmpty) {
      return widget.allowedCategories!;
    }

    // Return an empty list instead of null to avoid crashing UI
    return [];
  }

  List<FileCategory> get _availableCategories {
    if (widget.allowedCategories != null && widget.allowedCategories!.isNotEmpty) {
      return widget.allowedCategories!;
    } else {
      return FileCategory.values;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            if (widget.showCategorySelector) ...[
              _buildCategorySelector(),
              const SizedBox(height: 16),
            ],
            _buildFileSelector(),
            if (_selectedFile != null) ...[
              const SizedBox(height: 16),
              /// Remove build file preview as it is not currently supported
              /// _buildFilePreview(),
              /// const SizedBox(height: 16),
              _buildDescriptionField(),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 16),
            _buildUploadButton(),
            if (_isUploading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final t = AppLocalizations.of(context)!;
    return Row(
      children: [
        Icon(Icons.cloud_upload, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.customTitle ?? t.fileuploadwidget_uploadFile,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
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
      case('Employment Application'):
        return t.filemanage_empApplication;
      case('Onboarding Form'):
        return t.filemanage_onboardForm;
      case('Background Check'):
        return t.filemanage_backgroundCheck;
      case('Certification/License'):
        return t.filemanage_cert;
      case('Reference'):
        return t.filemanage_ref;
      case('Employment Contract'):
        return t.filemanage_empContract;
      case('Tax Form (W-4)'):
        return t.filemanage_taxForm;
      case('Work Authorization (I-9)'):
      default:
        return name;
    }
  }

  Widget _buildCategorySelector() {
    final categories = _availableCategories;
    final t = AppLocalizations.of(context)!;

    if (categories.isEmpty) {
      return Text(t.manualentrywidget_noCateAvail);
    }

    return DropdownButtonFormField<FileCategory>(
      items: categories.map((category) {
        return DropdownMenuItem<FileCategory>(
          value: category,
          child: Text('${category.icon} ${_translateCategory(category.displayName)}'),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedCategory = value;
        });
      },
      validator: (value) {
        if (value == null) {
          return t.manualentrywidget_noCateSelected;
        }
        return null;
      },
      initialValue: _selectedCategory,  // Starts as null!
      hint: Text(t.manualentrywidget_selectCat),  // This shows when value is null
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildFileSelector() {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.fileuploadwidget_selectFile,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(
              color: _selectedFile != null
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: 2,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(8),
            color: _selectedFile != null
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: InkWell(
            onTap: _selectFile,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _selectedFile != null
                      ? Icons.check_circle
                      : Icons.add_circle_outline,
                  size: 48,
                  color: _selectedFile != null
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedFile != null
                      ? '${t.fileuploadwidget_fileSelected}: ${_selectedFile!.path}'
                      : _selectedFileName != null ? '${t.fileuploadwidget_fileSelected}: $_selectedFileName' :
                  _getFileInstructions(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _selectedFile != null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: _selectedFile != null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePreview() {
    if (_selectedFile == null) return const SizedBox.shrink();

    final filePath = _selectedFile!.path;
    final fileName = filePath.split('/').last;
    final fileSize = _selectedFile!.lengthSync();
    final fileSizeText = _formatFileSize(fileSize);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(fileName),
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  fileSizeText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedFile = null;
              });
            },
            icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionField() {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.fileuploadwidget_descriptionOpti,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: t.fileuploadwidget_descriptionDescr,
            hintText: '${t.fileuploadwidget_descriptionHint}...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          maxLines: 3,
          maxLength: 500,
        ),
      ],
    );
  }

  Widget _buildUploadButton() {
    final t = AppLocalizations.of(context)!;
    final canUpload =
        _selectedCategory != null &&
            (_selectedFile != null ||
                (_selectedFileBytes != null && _selectedFileName != null))
            && !_isUploading;

    return ElevatedButton.icon(
      onPressed: canUpload ? _uploadFileWeb : null,
      style: canUpload
          ? Theme.of(context).elevatedButtonTheme.style
          : ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).disabledColor,
        foregroundColor: Theme.of(
          context,
        ).colorScheme.onSurface.withOpacity(0.38),
      ),
      icon: _isUploading
          ? const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
          : const Icon(Icons.cloud_upload),
      label: Text(_isUploading ? '${t.fileuploadwidget_uploading}...' : t.fileuploadwidget_uploadFile),
    );
  }

  String _getFileInstructions() {
    final t = AppLocalizations.of(context)!;
    if (_selectedCategory == null) {
      return t.fileuploadwidget_selectCatFirst;
    }

    switch (_selectedCategory!) {
      case FileCategory.profilePicture:
        return t.fileuploadwidget_tapSelectPFP;
      case FileCategory.prescription:
        return t.fileuploadwidget_tapSelectPrescrip;
      case FileCategory.medicalReport:
      case FileCategory.labResult:
        return t.fileuploadwidget_tapSelectMedDoc;
      case FileCategory.insuranceDoc:
        return t.fileuploadwidget_tapSelectInsurance;
      default:
        return t.fileuploadwidget_tapSelectFile;
    }
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'mp4':
      case 'mov':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
        return Icons.audio_file;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _selectFile() async {
    final t = AppLocalizations.of(context)!;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.manualentrywidget_selectCatFirst),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    try {
      if (kIsWeb) {
        final (Uint8List, String)? webSelectedFile = await ComprehensiveFileService.pickFileForCategoryWeb(
          _selectedCategory!,
        );
        if (webSelectedFile != null) {
          setState(() {
            _selectedFileBytes = webSelectedFile.$1;
            _selectedFileName = webSelectedFile.$2;
          });
        }
      }
      else {
        final File? file = await ComprehensiveFileService.pickFileForCategory(
          _selectedCategory!,
        );
        if (file != null) {
          setState(() {
            _selectedFile = file;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t.fileuploadwidget_errorSelectingFile}: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedCategory == null || _selectedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      final t = AppLocalizations.of(context)!;
      if (user == null) {
        throw Exception(t.manualentrywidget_userNotLogged);
      }

      FileUploadResponse? response;
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();

      // Use the existing enhanced file service for other categories
      response = await EnhancedFileService.uploadFile(
        file: _selectedFile!,
        category: _selectedCategory!.value,
        description: description,
        patientId: widget.patientId,
      );

      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${t.manualentrywidget_fileUploadedSuccess}: ${response.originalFilename}',
            ),
            backgroundColor: AppTheme.success,
          ),
        );

        // Reset form
        setState(() {
          _selectedFile = null;
          _descriptionController.clear();
        });

        // Callback
        if (widget.onUploadSuccess != null) {
          widget.onUploadSuccess!(response);
        }
      } else {
        throw Exception(t.manualentrywidget_uploadFailedNoResp);
      }
    } catch (e) {
      final t = AppLocalizations.of(context)!;
      final errorMessage = '${t.manualentrywidget_uploadFailed}: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: AppTheme.error),
      );

      if (widget.onUploadError != null) {
        widget.onUploadError!(errorMessage);
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _uploadFileWeb() async {

    if (_selectedCategory == null ||
        _selectedFileBytes == null ||
        _selectedFileName == null) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      final t = AppLocalizations.of(context)!;
      if (user == null) {
        throw Exception(t.manualentrywidget_userNotLogged);
      }

      FileUploadResponse? response;
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();

      // Use the existing enhanced file service for other categories
      response = await EnhancedFileService.uploadFileWeb(
        fileBytes: _selectedFileBytes!,
        fileName: _selectedFileName!,
        category: _selectedCategory!.value,
        description: description,
        patientId: widget.patientId,
      );

      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${t.manualentrywidget_fileUploadedSuccess}: ${response.fileName}',
            ),
            backgroundColor: AppTheme.success,
          ),
        );

        // Reset form
        setState(() {
          _selectedFile = null;
          _selectedFileName = null;
          _selectedFileBytes = null;
          _descriptionController.clear();
        });

        // Callback
        if (widget.onUploadSuccess != null) {
          widget.onUploadSuccess!(response);
        }
      } else {
        throw Exception(t.manualentrywidget_uploadFailedNoResp);
      }
    } catch (e, stacktrace) {
      print('Upload Exception: $e');
      print('Stacktrace: $stacktrace');
      final t = AppLocalizations.of(context)!;
      final errorMessage = '${t.manualentrywidget_uploadFailed}: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: AppTheme.error),
      );

      if (widget.onUploadError != null) {
        widget.onUploadError!(errorMessage);
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }
}



/// Quick upload buttons for common file types
class QuickUploadButtons extends StatelessWidget {
  final int? patientId;
  final Function(FileUploadResponse)? onUploadSuccess;

  const QuickUploadButtons({super.key, this.patientId, this.onUploadSuccess});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.fileuploadwidget_quickFileUpload, style: AppTheme.headingSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickButton(
              context,
              icon: Icons.person,
              label: t.fileuploadwidget_profilePhoto,
              category: FileCategory.profilePicture,
            ),
            _buildQuickButton(
              context,
              icon: Icons.medical_services,
              label: t.filemanage_medReport,
              category: FileCategory.medicalReport,
            ),
            _buildQuickButton(
              context,
              icon: Icons.medication,
              label: t.filemanage_prescription,
              category: FileCategory.prescription,
            ),
            _buildQuickButton(
              context,
              icon: Icons.science,
              label: t.filemanage_labResult,
              category: FileCategory.labResult,
            ),
            _buildQuickButton(
              context,
              icon: Icons.security,
              label: t.ptfiles_insuranceItem,
              category: FileCategory.insuranceDoc,
            ),
            _buildQuickButton(
              context,
              icon: Icons.smart_toy,
              label: t.filemanage_aiChatFile,
              category: FileCategory.aiChatUpload,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickButton(
      BuildContext context, {
        required IconData icon,
        required String label,
        required FileCategory category,
      }) {
    return ElevatedButton.icon(
      onPressed: () => _showUploadDialog(context, category),
      style: AppTheme.secondaryButtonStyle,
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }

  void _showUploadDialog(BuildContext context, FileCategory category) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${t.fileuploadwidget_upload} ${category.displayName}'),
          content: SizedBox(
            width: 400,
            child: FileUploadWidget(
              defaultCategory: category,
              patientId: patientId,
              showCategorySelector: false,
              onUploadSuccess: (response) {
                Navigator.of(context).pop();
                if (onUploadSuccess != null) {
                  onUploadSuccess!(response);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.cancel),
            ),
          ],
        );
      },
    );
  }
}