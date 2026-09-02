import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'dart:async';
import '../../../health/medication-tracker/models/medication-model.dart';
import '../../../../services/api_service.dart';

/// Patient Details → Health tab
class CurrentMedicationsSection extends StatelessWidget {
  final List<Medication> entries;
  final String title; // defaults to 'Current Medications'
  final Function()? onMedicationUpdated; // Callback to refresh medications
  final int? caregiverId; // Caregiver ID for hard delete

  const CurrentMedicationsSection({
    super.key,
    required this.entries,
    this.title = 'Current Medications',
    this.onMedicationUpdated,
    this.caregiverId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Active medications first, then alphabetical
    final meds = List<Medication>.from(entries)
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.medicationName.toLowerCase().compareTo(b.medicationName.toLowerCase());
      });

      unawaited(
        Telemetry.event('feature.medications.view_active', {'feature': 'CurrentMedicationsSection'})
      );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Icon(Icons.vaccines_outlined,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (meds.isEmpty)
            const _EmptyState(message: 'No current medications')
          else
            Column(
              children: List.generate(
                meds.length,
                (i) => _MedicationBlock(
                  med: meds[i],
                  onMedicationUpdated: onMedicationUpdated,
                  caregiverId: caregiverId,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MedicationBlock extends StatefulWidget {
  final Medication med;
  final Function()? onMedicationUpdated;
  final int? caregiverId;

  const _MedicationBlock({
    required this.med,
    this.onMedicationUpdated,
    this.caregiverId,
  });

  @override
  State<_MedicationBlock> createState() => _MedicationBlockState();
}

class _MedicationBlockState extends State<_MedicationBlock> {
  bool _isDeleting = false;
  bool _isApproving = false;

  Future<void> _handleDelete() async {
    if (widget.med.id == null || widget.med.patientId == null) {
      _showSnackBar('Unable to delete medication: Missing ID', isError: true);
      return;
    }

    if (widget.caregiverId == null) {
      _showSnackBar('Unable to delete medication: Missing caregiver ID', isError: true);
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Medication'),
        content: Text('Are you sure you want to delete ${widget.med.medicationName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      // Use caregiver hard delete endpoint
      final response = await ApiService.deleteMedicationByCaregiver(
        widget.med.patientId!,
        widget.med.id!,
        widget.caregiverId!,
      );

      unawaited(
        Telemetry.event('feature.medications.delete_hard', {'statusCode': response.statusCode})
      );

      if (response.statusCode == 200) {
        _showSnackBar('Medication deleted successfully');
        widget.onMedicationUpdated?.call();
      } else {
        try {
          final errorData = jsonDecode(response.body);
          _showSnackBar(
            errorData['message'] ?? 'Failed to delete medication',
            isError: true,
          );
        } catch (e) {
          _showSnackBar(
            'Failed to delete medication: ${response.statusCode}',
            isError: true,
          );
        }
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _handleApprove() async {
    if (widget.med.id == null || widget.med.patientId == null) {
      _showSnackBar('Unable to approve medication: Missing ID', isError: true);
      return;
    }

    setState(() => _isApproving = true);

    try {
      final response = await ApiService.approveMedication(
        widget.med.patientId!,
        widget.med.id!,
      );
      unawaited(
          Telemetry.event('feature.medications.approve', {'statusCode': response.statusCode})
        );


      if (response.statusCode == 200) {
        _showSnackBar('Medication approved successfully');
        widget.onMedicationUpdated?.call();
      } else {
        final errorData = jsonDecode(response.body);
        _showSnackBar(
          errorData['message'] ?? 'Failed to approve medication',
          isError: true,
        );
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
          unawaited(
          Telemetry.event('feature.medications.view_all', {'feature': 'MedicationBlock'})
        );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + status badge
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.med.medicationName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(isActive: widget.med.isActive),
            ],
          ),
          const SizedBox(height: 8),

          // Dosage / Frequency
          Row(
            children: [
              Expanded(child: _kv(context, 'Dosage', widget.med.dosage)),
              const SizedBox(width: 12),
              Expanded(child: _kv(context, 'Frequency', widget.med.frequency)),
            ],
          ),
          const SizedBox(height: 8),

          // Route / Type
          Row(
            children: [
              Expanded(child: _kv(context, 'Route', widget.med.route)),
              const SizedBox(width: 12),
              Expanded(
                child: _kv(
                  context,
                  'Type',
                  widget.med.medicationType?.name.toUpperCase() ?? 'N/A',
                ),
              ),
            ],
          ),

          if (widget.med.startDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _kv(
                    context,
                    'Started',
                    _formatDateString(widget.med.startDate!),
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.med.endDate != null)
                  Expanded(
                    child: _kv(
                      context,
                      'End Date',
                      _formatDateString(widget.med.endDate!),
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ],

          if (widget.med.prescribedBy != null) ...[
            const SizedBox(height: 8),
            _kv(context, 'Prescribed By', widget.med.prescribedBy!),
          ],

          if (widget.med.notes != null && widget.med.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _kv(context, 'Notes', widget.med.notes!),
          ],

          // Action buttons
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Approve button (only for inactive medications)
              if (!widget.med.isActive) ...[
                _isApproving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ElevatedButton.icon(
                        onPressed: _handleApprove,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                const SizedBox(width: 8),
              ],
              // Delete button
              _isDeleting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ElevatedButton.icon(
                      onPressed: _handleDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  String _formatDateString(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;

  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = isActive ? Colors.blue.shade900 : cs.surfaceContainerHighest.withValues(alpha: 0.6);
    final fg = isActive ? Colors.white : cs.onSurface;
    final text = isActive ? 'active' : 'inactive';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.local_pharmacy_outlined,
              size: 28, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
