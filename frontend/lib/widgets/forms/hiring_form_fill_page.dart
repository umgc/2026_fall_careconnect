import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../config/theme/app_theme.dart';
import '../../models/hiring_form_models.dart';
import '../../services/hiring_form_submission_service.dart';

/// Fillable view of a single hiring/onboarding form. The user enters values for
/// each field, reviews a confirmation summary, and on confirmation the data is
/// submitted to the backend and stored in the database.
class HiringFormFillPage extends StatefulWidget {
  const HiringFormFillPage({super.key, required this.definition, this.patientId});

  final FormDefinition definition;
  final int? patientId;

  @override
  State<HiringFormFillPage> createState() => _HiringFormFillPageState();
}

class _HiringFormFillPageState extends State<HiringFormFillPage> {
  final _formKey = GlobalKey<FormState>();

  /// Captured values keyed by "sectionId.fieldId".
  final Map<String, dynamic> _values = {};

  bool _submitting = false;

  FormDefinition get d => widget.definition;

  String _key(FormSectionDef s, FormFieldDef f) => '${s.id}.${f.id}';

  // ---- visibility ---------------------------------------------------------

  bool _visible(FormFieldDef field) {
    final cond = field.visibleWhen;
    if (cond == null) return true;
    // Match the controlling field by id (any section).
    for (final entry in _values.entries) {
      if (entry.key.endsWith('.${cond.fieldId}')) {
        return entry.value?.toString() == cond.equalsValue?.toString();
      }
    }
    return false;
  }

  // ---- submit flow --------------------------------------------------------

  Future<void> _onSubmitPressed() async {
    // 1. Client-side required check (mirrors the server's required rule).
    final missing = <String>[];
    for (final section in d.sections) {
      for (final field in section.fields) {
        if (!field.required || !_visible(field)) continue;
        final v = _values[_key(section, field)];
        final empty = v == null || (v is String && v.trim().isEmpty);
        if (empty) missing.add(field.label);
      }
    }
    if (missing.isNotEmpty) {
      _formKey.currentState?.validate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please complete required fields: ${missing.join(', ')}'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    // 2. Confirmation step before anything is submitted.
    final confirmed = await _showConfirmDialog();
    if (confirmed != true) return;

    // 3. Submit to the backend.
    setState(() => _submitting = true);
    final result = await HiringFormSubmissionService.submit(
      definition: d,
      fieldValues: _collectValues(),
      patientId: widget.patientId,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    final t = AppLocalizations.of(context)!;

    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t.hiringformfill_submitted} "${d.title}" — ${t.hiringformfill_copySaved}'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop(true);
    } else if (result.errors.isNotEmpty) {
      await _showErrorsDialog(result.message, result.errors);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: AppTheme.error),
      );
    }
  }

  /// Only include visible fields with a non-empty value.
  Map<String, dynamic> _collectValues() {
    final out = <String, dynamic>{};
    for (final section in d.sections) {
      for (final field in section.fields) {
        if (!_visible(field)) continue;
        final key = _key(section, field);
        final v = _values[key];
        if (v == null) continue;
        if (v is String && v.trim().isEmpty) continue;
        out[key] = v;
      }
    }
    return out;
  }

  Future<bool?> _showConfirmDialog() {
    final entries = <MapEntry<String, String>>[];
    final t = AppLocalizations.of(context)!;
    for (final section in d.sections) {
      for (final field in section.fields) {
        if (!_visible(field)) continue;
        final v = _values[_key(section, field)];
        if (v == null || (v is String && v.trim().isEmpty)) continue;
        entries.add(MapEntry(field.label, _displayValue(field, v)));
      }
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.hiringformfill_confirmSub),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t.hiringformfill_submit} "${d.title}" (v${d.version})? '
                '${t.hiringformfill_confirmInfo} — '
                '${t.hiringformfill_saveToRecord}',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: entries.isEmpty
                    ? Text(t.hiringformfill_noInfoEntered)
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final e in entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 4,
                                      child: Text(e.key,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary)),
                                    ),
                                    Expanded(
                                      flex: 5,
                                      child: Text(e.value,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.hiringformfill_confirmAndSub),
          ),
        ],
      ),
    );
  }

  Future<void> _showErrorsDialog(String title, List<String> errors) {
    final t = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in errors)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(e, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.hiringformfill_ok),
          ),
        ],
      ),
    );
  }

  String _displayValue(FormFieldDef field, dynamic v) {
    final t = AppLocalizations.of(context)!;
    if (v is bool) return v ? t.hiringformfill_yes : t.hiringformfill_no;
    if (field.options.isNotEmpty) {
      final match = field.options.where((o) => o.value == v.toString());
      if (match.isNotEmpty) return match.first.label;
    }
    return v.toString();
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text('${t.hiringformfill_fillOut}: ${d.title}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              color: AppTheme.primary.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${t.hiringformfill_completeFields} '
                        '${t.hiringformfill_completeFields2}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final section in d.sections) _sectionCard(section),
            const SizedBox(height: 90),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitting ? null : _onSubmitPressed,
        backgroundColor: AppTheme.primary,
        icon: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_circle_outline),
        label: Text(_submitting ? '${t.hiringformfill_submitting}…' : t.hiringformfill_reviewSub),
      ),
    );
  }


  Widget _sectionCard(FormSectionDef section) {
    final fields = [...section.fields]..sort((a, b) => a.order.compareTo(b.order));
    final visible = fields.where(_visible).toList();
    final t = AppLocalizations.of(context)!;
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (section.completedBy != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${t.hiringformfill_completedBy} ${section.completedBy!.toLowerCase()}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ),
            const SizedBox(height: 6),
            for (final field in visible) _fieldInput(section, field),
          ],
        ),
      ),
    );
  }

  Widget _fieldInput(FormSectionDef section, FormFieldDef field) {
    final key = _key(section, field);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: _control(key, field),
    );
  }

  Widget _control(String key, FormFieldDef field) {
    switch (field.fieldType) {
      case FormFieldType.checkbox:
      case FormFieldType.boolean:
        return _checkbox(key, field);
      case FormFieldType.radio:
      case FormFieldType.select:
        return _dropdown(key, field);
      case FormFieldType.date:
        return _dateField(key, field);
      case FormFieldType.fileRef:
        return _fileRefNote(field);
      case FormFieldType.multiselect:
        return _multiselect(key, field);
      default:
        return _textField(key, field);
    }
  }

  String _label(FormFieldDef field) => field.required ? '${field.label} *' : field.label;

  Widget _textField(String key, FormFieldDef field) {
    final t = AppLocalizations.of(context)!;
    final isNumber = field.fieldType == FormFieldType.number ||
        field.fieldType == FormFieldType.currency;
    return TextFormField(
      initialValue: _values[key]?.toString(),
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : (field.fieldType == FormFieldType.email
              ? TextInputType.emailAddress
              : (field.fieldType == FormFieldType.phone
                  ? TextInputType.phone
                  : TextInputType.text)),
      obscureText: field.sensitive &&
          field.fieldType != FormFieldType.text &&
          field.fieldType != FormFieldType.textarea,
      maxLines: field.fieldType == FormFieldType.textarea ? 3 : 1,
      decoration: _decoration(field),
      validator: (v) => field.required && (v == null || v.trim().isEmpty)
          ? t.hiringformfill_required
          : null,
      onChanged: (v) => _values[key] = v,
    );
  }

  Widget _dropdown(String key, FormFieldDef field) {
    final t = AppLocalizations.of(context)!;
    return DropdownButtonFormField<String>(
      initialValue: _values[key] as String?,
      isExpanded: true,
      decoration: _decoration(field),
      items: [
        for (final o in field.options)
          DropdownMenuItem(value: o.value, child: Text(o.label)),
      ],
      validator: (v) =>
          field.required && (v == null || v.isEmpty) ? t.hiringformfill_required : null,
      onChanged: (v) => setState(() => _values[key] = v),
    );
  }

  Widget _checkbox(String key, FormFieldDef field) {
    final val = _values[key] == true;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: val,
      title: Text(_label(field), style: const TextStyle(fontSize: 14)),
      subtitle: field.helpText != null
          ? Text(field.helpText!,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))
          : null,
      onChanged: (v) => setState(() => _values[key] = v ?? false),
    );
  }

  Widget _dateField(String key, FormFieldDef field) {
    final current = _values[key] as String?;
    final t = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(now.year - 100),
          lastDate: DateTime(now.year + 10),
        );
        if (picked != null) {
          setState(() => _values[key] =
              '${picked.year.toString().padLeft(4, '0')}-'
              '${picked.month.toString().padLeft(2, '0')}-'
              '${picked.day.toString().padLeft(2, '0')}');
        }
      },
      child: InputDecorator(
        decoration: _decoration(field),
        child: Text(
          current ?? t.hiringformfill_selectDate,
          style: TextStyle(
            fontSize: 14,
            color: current == null ? AppTheme.textSecondary : null,
          ),
        ),
      ),
    );
  }

  Widget _multiselect(String key, FormFieldDef field) {
    final selected =
        (_values[key] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_label(field), style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final o in field.options)
              FilterChip(
                label: Text(o.label),
                selected: selected.contains(o.value),
                onSelected: (on) => setState(() {
                  if (on) {
                    selected.add(o.value);
                  } else {
                    selected.remove(o.value);
                  }
                  _values[key] = selected.toList();
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _fileRefNote(FormFieldDef field) {
    final t = AppLocalizations.of(context)!;
    return InputDecorator(
      decoration: _decoration(field),
      child: Text(
        t.hiringformfill_attachDocument,
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
    );
  }

  InputDecoration _decoration(FormFieldDef field) {
    return InputDecoration(
      labelText: _label(field),
      helperText: field.helpText,
      helperMaxLines: 2,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: field.sensitive
          ? const Icon(Icons.lock_outline, size: 16, color: AppTheme.textSecondary)
          : null,
    );
  }
}
