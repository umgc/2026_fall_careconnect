import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/notetaker/models/patient_note_model.dart';
import 'package:care_connect_app/services/notetaker_config_service.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/providers/user_provider.dart';

class NotetakerDetailView extends StatefulWidget {
  const NotetakerDetailView({super.key});

  @override
  State<NotetakerDetailView> createState() => _NotetakerDetailViewState();
}

class _NotetakerDetailViewState extends State<NotetakerDetailView> {
  PatientNote? _note;
  final TextEditingController _aiSummaryController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  bool _isEditing = false;
  bool _hasChanges = false;
  String? _patientName;
  bool _isLoadingName = false;
  bool _isLoadingNote = false;
  String? _loadError;
  bool _resolvedInitialNote = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedInitialNote) return;
    _resolvedInitialNote = true;

    final extra = GoRouterState.of(context).extra;
    if (extra is PatientNote) {
      _applyNote(extra);
      return;
    }

    final noteId = GoRouterState.of(context).pathParameters['noteId'];
    final patientIdParam =
        GoRouterState.of(context).uri.queryParameters['patientId'];
    final patientId = int.tryParse(patientIdParam ?? '');
    if (noteId == null || noteId.isEmpty || patientId == null) {
      _loadError = 'Invalid note ID or missing patient context';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_loadError!)),
        );
      });
      return;
    }
    _fetchNoteById(patientId, noteId);
  }

  void _applyNote(PatientNote note) {
    _note = note;
    _noteController.text = note.note;
    _aiSummaryController.text = note.aiSummary;
    _isEditing = true;
    _fetchPatientName();
  }

  Future<void> _fetchNoteById(int patientId, String noteId) async {
    setState(() {
      _isLoadingNote = true;
      _loadError = null;
    });
    final note = await NotetakerConfigService.getPatientNote(patientId, noteId);
    if (!mounted) return;
    if (note == null) {
      setState(() {
        _isLoadingNote = false;
        _loadError = 'Could not load note $noteId';
      });
      return;
    }
    setState(() {
      _isLoadingNote = false;
      _applyNote(note);
    });
  }

  Future<void> _fetchPatientName() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;
    if (user.role.toUpperCase() == 'PATIENT') {
      _patientName = 'Your Note';
    } else {
      setState(() => _isLoadingName = true);
      try {
        http.Response patientResponse = await ApiService.getCaregiverPatients(
          user.caregiverId!,
        );
        final patients = (jsonDecode(patientResponse.body) as List<dynamic>)
            .map(
              (patientWLink) => {
                'id': patientWLink['patient']['id'].toString(),
                'name':
                    '${patientWLink['patient']['firstName']} ${patientWLink['patient']['lastName']}',
              },
            )
            .toList();
        final patient = patients.firstWhere(
          (p) => p['id'] == _note!.patientId,
          orElse: () => <String, String>{},
        );
        _patientName = patient['name'] ?? 'Unknown Patient';
      } catch (e) {
        _patientName = 'Unknown Patient';
      } finally {
        if (mounted) setState(() => _isLoadingName = false);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _noteController.dispose();
    _aiSummaryController.dispose();
    super.dispose();
  }

  void _onNoteChanged(String value) {
    _checkForChanges();
  }

  void _onAiSummaryChanged(String value) {
    _checkForChanges();
  }

  void _checkForChanges() {
    setState(() {
      _hasChanges =
          _noteController.text != (_note?.note ?? '') ||
          _aiSummaryController.text != (_note?.aiSummary ?? '');
    });
  }

  Future<void> _saveNote() async {
    if (_note == null) return;
    final updatedNote = PatientNote(
      id: _note!.id,
      patientId: _note!.patientId,
      note: _noteController.text,
      aiSummary: _aiSummaryController.text,
      createdAt: _note!.createdAt,
      updatedAt: DateTime.now(),
    );
    try {
      final saved = await NotetakerConfigService.updatePatientNote(updatedNote);
      setState(() {
        _note = saved;
        _hasChanges = false;
        _isEditing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save note: $e')));
      }
    }
  }

  Future<void> _deleteNote() async {
    if (_note == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await NotetakerConfigService.deletePatientNote(
          _note!.id,
          int.parse(_note!.patientId),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note deleted successfully')),
          );
          context.pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete note: $e')));
        }
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'You have unsaved changes. Do you want to save them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await _saveNote();
      return true;
    } else if (result == 'discard') {
      return true;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingNote) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_note == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Note Detail')),
        body: Center(
          child: Text(_loadError ?? 'Note not available'),
        ),
      );
    }

    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _onWillPop()) {
          context.pop(true);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Note Detail'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _onWillPop()) {
                context.pop(true);
              }
            },
          ),
          actions: [
            if (_isEditing)
              IconButton(icon: const Icon(Icons.save), onPressed: () async { await _saveNote(); context.pop(true); })
            else
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  setState(() {
                    _isEditing = true;
                  });
                },
              ),
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteNote),
          ],
        ),
        body: _isLoadingName
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(
                      theme,
                      'View and edit the details of this note.',
                    ),
                    const SizedBox(height: 24),
                    _buildSection(theme, 'Note Information', Icons.note, [
                      if (_patientName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Patient: $_patientName',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Created On: ${DateFormat('MMM dd, yyyy hh:mm a').format(_note!.createdAt)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Last Updated: ${DateFormat('MMM dd, yyyy hh:mm a').format(_note!.updatedAt)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _buildSection(theme, 'AI Summary', Icons.smart_toy, [
                      _isEditing
                          ? TextField(
                              controller: _aiSummaryController,
                              onChanged: _onAiSummaryChanged,
                              maxLines: null,
                              decoration: InputDecoration(
                                hintText: '',
                                border: OutlineInputBorder(),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _note!.aiSummary,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                    ]),
                    const SizedBox(height: 24),
                    _buildSection(theme, 'Note Content', Icons.edit, [
                      _isEditing
                          ? TextField(
                              controller: _noteController,
                              maxLines: null,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Enter note content',
                              ),
                              onChanged: _onNoteChanged,
                            )
                          : Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withOpacity(
                                    0.3,
                                  ),
                                ),
                              ),
                              child: Text(
                                _note!.note,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                    ]),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primaryContainer, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
