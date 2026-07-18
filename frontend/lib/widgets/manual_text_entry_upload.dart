import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../config/theme/app_theme.dart';
import '../providers/user_provider.dart';
import '../services/comprehensive_file_service.dart';
import '../services/enhanced_file_service.dart';

class ManualTextEntryCard extends StatefulWidget {
  final List<FileCategory>? allowedCategories;
  final int? patientId;
  final Function(FileUploadResponse)? onUploadSuccess;
  final Function(String)? onUploadError;

  const ManualTextEntryCard({super.key, this.allowedCategories, this.patientId, this.onUploadSuccess, this.onUploadError});

  @override
  State<ManualTextEntryCard> createState() => _ManualTextEntryCardState();
}

class _ManualTextEntryCardState extends State<ManualTextEntryCard> {
  final _fileNameController = TextEditingController();
  late final _fileContentController = TextEditingController();
  FileCategory? _selectedCategory;

  List<FileCategory> get _availableCategories {
    if (widget.allowedCategories != null && widget.allowedCategories!.isNotEmpty) {
      return widget.allowedCategories!;
    } else {
      return FileCategory.values;
    }
  }

  Widget _buildHeader() {
    final t = AppLocalizations.of(context)!;
    return Row(
      children: [
        Icon(Icons.text_fields, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t.manualentrywidget_manualTextEntry,
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
    final t = AppLocalizations.of(context)!;
    final categories = _availableCategories;

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

  Future<void> _selectCategory() async {
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
  }

  Future<void> _uploadManualTextFileToWeb(String fileName, List<int> fileBytes) async {
    if (_selectedCategory == null || fileBytes.isEmpty || fileName.isEmpty) {
      print('Selected category was null..');
      return;
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      final t = AppLocalizations.of(context)!;
      if (user == null) {
        throw Exception(t.manualentrywidget_userNotLogged);
      }

      FileUploadResponse? response;

      // Use the existing enhanced file service for other categories
      response = await EnhancedFileService.uploadFileWeb(
        fileBytes: Uint8List.fromList(fileBytes),
        fileName: '$fileName.txt',
        category: _selectedCategory!.value,
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
          _selectedCategory = null;
          _fileNameController.clear();
          _fileContentController.clear();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildCategorySelector(),
        const SizedBox(height: 16),
        TextFormField(
          controller: _fileNameController,
          decoration: InputDecoration(
            labelText: t.manualentrywidget_fileName,
            hintText: t.manualentrywidget_enterFileName,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return t.manualentrywidget_fileNameEmpty;
            }
            if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(value.trim())) {
              return t.manualentrywidget_invalidCharacters;
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        Column(
          children: [
            const SizedBox(height: 16),
            TextFormField(
              controller: _fileContentController,
              decoration: InputDecoration(
                labelText: t.manualentrywidget_fileContent,
                hintText: '${t.manualentrywidget_fileContentDescr}...',
              ),
              maxLines: 6,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return t.manualentrywidget_fileContentEmpty;
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            Align(
              alignment: Alignment.center,
              child: ElevatedButton(
                onPressed: () async {
                  if (_selectedCategory == null) {
                    _selectCategory();
                  }

                  String fileName = _fileNameController.text.trim();
                  String content = _fileContentController.text.trim();

                  final fileBytes = utf8.encode(content);
                  // Call your upload function (adjust as needed)
                  await _uploadManualTextFileToWeb(fileName, fileBytes);
                },

                child: Text(t.manualentrywidget_saveToFile),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
