import 'package:flutter/material.dart';

import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_question.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart'
    show BackendQuestionDto;
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_mapper.dart'
as vmap;

import 'package:care_connect_app/features/health/virtual_check_in/services/checkin_api.dart';
import 'package:care_connect_app/features/health/virtual_check_in/services/questions_api.dart';
import 'package:care_connect_app/config/env_constant.dart';

/// Bottom sheet that edits the patient's Virtual Check-In questions.
class VirtualCheckInConfigSheet extends StatefulWidget {
  final int? checkInId;
  final List<VirtualCheckInQuestion> initial;

  const VirtualCheckInConfigSheet({
    super.key,
    this.checkInId,
    required this.initial,
  });

  @override
  State<VirtualCheckInConfigSheet> createState() =>
      _VirtualCheckInConfigSheetState();
}

class _VirtualCheckInConfigSheetState extends State<VirtualCheckInConfigSheet> {
  // Backend clients
  late final CheckInApi _api;
  late final QuestionsApi _qApi;

  bool _loading = true;
  String? _error;

  // Working list we render/edit
  late List<VirtualCheckInQuestion> _items;

  // Prevent duplicates by prompt (lowercased, trimmed)
  final Set<String> _promptsLower = <String>{};

  // “Add New Question” form state
  CheckInQuestionType _newType = CheckInQuestionType.numerical;
  bool _newRequired = false;
  final TextEditingController _newTextCtrl = TextEditingController();

  // Catalog (select existing questions)
  List<BackendQuestionDto> _catalog = [];
  final Set<String> _selectedToAdd = {}; // dto.id as string
  final TextEditingController _catalogFilterCtrl = TextEditingController();
  final ScrollController _catalogScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final base = getBackendBaseUrl();
    _api = CheckInApi(base);
    _qApi = QuestionsApi(base);

    // seed from initial → dedupe by prompt
    _items = _dedupeByPrompt(widget.initial);
    _rebuildPromptIndex();

    _catalogFilterCtrl.addListener(() => setState(() {}));
    _newTextCtrl.addListener(() => setState(() {}));
    if (widget.checkInId != null) {
      _loadQuestions();
    } else {
      _loading = false;
    }
    _loadCatalog();
  }

  @override
  void dispose() {
    _newTextCtrl.dispose();
    _catalogFilterCtrl.dispose();
    _catalogScrollController.dispose();
    super.dispose();
  }

  // ---------- Dedupe helpers (by prompt) ----------

  List<VirtualCheckInQuestion> _dedupeByPrompt(
      List<VirtualCheckInQuestion> xs) {
    final seen = <String, VirtualCheckInQuestion>{};
    for (final q in xs) {
      final key = q.text.trim().toLowerCase();
      // keep first occurrence; change to assignment to keep last
      seen.putIfAbsent(key, () => q);
    }
    return seen.values.toList(growable: true);
  }

  void _rebuildPromptIndex() {
    _promptsLower
      ..clear()
      ..addAll(_items.map((q) => q.text.trim().toLowerCase()));
  }

  bool _containsPrompt(String text) =>
      _promptsLower.contains(text.trim().toLowerCase());

  // ---------- Data load ----------

  Future<void> _loadQuestions() async {
    final checkInId = widget.checkInId;
    if (checkInId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = await _api.getQuestions(checkInId.toString());
      // DTO → UI via mapper, dedupe by prompt, update state
      final mapped =
      backend.map<VirtualCheckInQuestion>(vmap.toUiQuestion).toList();
      setState(() {
        _items = _dedupeByPrompt(mapped);
        _rebuildPromptIndex();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final all = await _qApi.listQuestions(active: true); // /api/questions?active=true
      final existing = _promptsLower;
      setState(() {
        _catalog = all
            .where((q) => !existing.contains(q.prompt.trim().toLowerCase()))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load question catalog: $e')),
      );
    }
  }

  // ---------- Add / remove with duplicate-by-prompt guard ----------

  void _addQuestionFromForm() {
    final prompt = _newTextCtrl.text.trim();
    if (prompt.isEmpty) return;

    if (_containsPrompt(prompt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That question already exists.')),
      );
      return;
    }

    setState(() {
      _items.add(
        VirtualCheckInQuestion(
          id: DateTime.now().microsecondsSinceEpoch.toString(), // temp client id
          type: _newType,
          required: _newRequired,
          text: prompt,
        ),
      );
      _promptsLower.add(prompt.toLowerCase());
      _newTextCtrl.clear();
    });
  }

  void _addSelectedFromCatalog() {
    setState(() {
      for (final dto
      in _catalog.where((q) => _selectedToAdd.contains(q.id.toString()))) {
        final key = dto.prompt.trim().toLowerCase();
        if (!_promptsLower.contains(key)) {
          _items.add(vmap.toUiQuestion(dto));
          _promptsLower.add(key);
        }
      }
      // Remove added prompts from the catalog and clear selection
      _catalog
          .removeWhere((q) => _promptsLower.contains(q.prompt.trim().toLowerCase()));
      _selectedToAdd.clear();
    });
  }

  void _removeAt(int index) {
    final removed = _items.removeAt(index);
    _promptsLower.remove(removed.text.trim().toLowerCase());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final border = cs.outlineVariant.withOpacity(.35);

    return SafeArea(
      top: false,
      child: Padding(
        padding:
        EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.settings, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Configure Virtual Check-In Questions',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, null),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error: $_error',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current Questions
                        Text(
                          'Current Questions',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),

                        ..._items.asMap().entries.map((e) {
                          final i = e.key;
                          final q = e.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding:
                            const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _typeLeadingIcon(q.type, cs),
                                    const SizedBox(width: 8),
                                    _pillOutlined(
                                      context,
                                      label: _prettyTypeLabel(q.type),
                                      borderColor: cs.outlineVariant,
                                      textColor: cs.onSurface,
                                    ),
                                    const SizedBox(width: 8),
                                    if (q.required)
                                      _pillFilled(
                                        context,
                                        label: 'Required',
                                        bg: cs.error,
                                        fg: cs.onError,
                                      ),
                                    const SizedBox(width: 8),
                                    _pillOutlined(
                                      context,
                                      label: '#${i + 1}',
                                      borderColor: cs
                                          .surfaceContainerHighest
                                          .withOpacity(.25),
                                      textColor: cs.onSurfaceVariant,
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Delete question',
                                      onPressed: () => _removeAt(i),
                                      icon: Icon(Icons.delete_outline,
                                          color: cs.error),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  q.text,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _typeHelperText(q.type),
                                  style:
                                  theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.70),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const Divider(height: 24),

                        // ---------- Add from Catalog (selectable) ----------
                        Text(
                          'Add from Catalog',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),

                        TextField(
                          controller: _catalogFilterCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search questions…',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: border),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 8),

                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: Scrollbar(
                            controller: _catalogScrollController,
                            child: ListView.builder(
                              controller: _catalogScrollController,
                              shrinkWrap: true,
                              itemCount: _catalog.length,
                              itemBuilder: (context, i) {
                                final q = _catalog[i];
                                final term = _catalogFilterCtrl.text
                                    .trim()
                                    .toLowerCase();
                                if (term.isNotEmpty &&
                                    !q.prompt.toLowerCase().contains(term)) {
                                  return const SizedBox.shrink();
                                }
                                final idStr = q.id.toString();
                                final checked =
                                _selectedToAdd.contains(idStr);
                                return CheckboxListTile(
                                  value: checked,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedToAdd.add(idStr);
                                      } else {
                                        _selectedToAdd.remove(idStr);
                                      }
                                    });
                                  },
                                  dense: true,
                                  controlAffinity:
                                  ListTileControlAffinity.leading,
                                  title: Text(q.prompt),
                                  subtitle: Text(q.type.name),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _selectedToAdd.isEmpty
                                ? null
                                : _addSelectedFromCatalog,
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Add Selected'),
                          ),
                        ),

                        const Divider(height: 24),

                        // ---------- Add New Question (manual) ----------
                        Text(
                          'Add New Question',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Question Type',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color:
                                  cs.onSurface.withOpacity(.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'Options',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color:
                                  cs.onSurface.withOpacity(.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownMenu<CheckInQuestionType>(
                                initialSelection: _newType,
                                onSelected: (v) => setState(() =>
                                _newType = v ??
                                    CheckInQuestionType.numerical),
                                requestFocusOnTap: true,
                                enableFilter: false,
                                expandedInsets: EdgeInsets.zero,
                                textStyle: theme.textTheme.bodyLarge,
                                leadingIcon:
                                _typeLeadingIcon(_newType, cs),
                                menuStyle: MenuStyle(
                                  shape:
                                  WidgetStatePropertyAll<OutlinedBorder>(
                                    RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                inputDecorationTheme: InputDecorationTheme(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                    BorderSide(color: cs.primary),
                                  ),
                                  contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 16),
                                ),
                                dropdownMenuEntries: const [
                                  DropdownMenuEntry(
                                    value: CheckInQuestionType.numerical,
                                    label: 'Numerical (1–10 scale)',
                                    leadingIcon:
                                    Icon(Icons.onetwothree, size: 18),
                                  ),
                                  DropdownMenuEntry(
                                    value: CheckInQuestionType.textInput,
                                    label: 'Text Input',
                                    leadingIcon:
                                    Icon(Icons.edit, size: 18),
                                  ),
                                  DropdownMenuEntry(
                                    value: CheckInQuestionType.yesNo,
                                    label: 'Yes/No',
                                    leadingIcon:
                                    Icon(Icons.task_alt, size: 18),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: CheckboxListTile(
                                value: _newRequired,
                                onChanged: (v) => setState(
                                        () => _newRequired = v ?? false),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                ListTileControlAffinity.leading,
                                title: const Text('Required question'),
                                side: const BorderSide(color: Colors.grey),
                                fillColor:
                                WidgetStateProperty.all(Colors.white),
                                checkColor: Colors.black,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'Question Text',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurface.withOpacity(.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),

                        TextField(
                          controller: _newTextCtrl,
                          textInputAction: TextInputAction.done,
                          maxLines: null,
                          decoration: InputDecoration(
                            hintText:
                            'Enter your check-in question...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: cs.primary),
                            ),
                            contentPadding:
                            const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _addQuestionFromForm(),
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          height: 44,
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                            ),
                            onPressed: _newTextCtrl.text.trim().isEmpty
                                ? null
                                : _addQuestionFromForm,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Question'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const Divider(height: 1),

              // Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder()),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _items),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save Configuration'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- UI helpers ----------

  Widget _pillOutlined(
      BuildContext context, {
        required String label,
        required Color borderColor,
        required Color textColor,
      }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest.withOpacity(.18)
            : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
          isDark ? cs.outlineVariant.withOpacity(.45) : borderColor,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isDark ? cs.onSurface : textColor,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      ),
    );
  }

  Widget _pillFilled(
      BuildContext context, {
        required String label,
        required Color bg,
        required Color fg,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
      BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      ),
    );
  }

  Widget _typeLeadingIcon(CheckInQuestionType t, ColorScheme cs) {
    switch (t) {
      case CheckInQuestionType.numerical:
        return Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2666F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '123',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
            ),
          ),
        );
      case CheckInQuestionType.yesNo:
        return Icon(Icons.task_alt, color: Colors.green, size: 20);
      case CheckInQuestionType.textInput:
        return const Icon(Icons.edit, color: Color(0xFFFF7A00), size: 20);
    }
  }

  String _prettyTypeLabel(CheckInQuestionType t) {
    switch (t) {
      case CheckInQuestionType.numerical:
        return 'Numerical';
      case CheckInQuestionType.yesNo:
        return 'Yes/No';
      case CheckInQuestionType.textInput:
        return 'Input';
    }
  }

  String _typeHelperText(CheckInQuestionType t) {
    switch (t) {
      case CheckInQuestionType.numerical:
        return 'Expects a number input';
      case CheckInQuestionType.yesNo:
        return 'Yes/No selection';
      case CheckInQuestionType.textInput:
        return 'Free text input';
    }
  }
}
