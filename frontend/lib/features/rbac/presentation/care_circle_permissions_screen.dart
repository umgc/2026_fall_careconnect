import 'package:flutter/material.dart';
import '../models/permission_grant_request.dart';
import '../services/rbac_service.dart';

class CareCirclePermissionsScreen extends StatefulWidget {
  final String patientId;
  final String targetUserId;
  final RbacService rbacService;

  const CareCirclePermissionsScreen({
    Key? key,
    required this.patientId,
    required this.targetUserId,
    required this.rbacService,
  }) : super(key: key);

  @override
  _CareCirclePermissionsScreenState createState() => _CareCirclePermissionsScreenState();
}

class _CareCirclePermissionsScreenState extends State<CareCirclePermissionsScreen> {
  final Map<String, bool> _featuresState = {
    'MEDICATIONS': false,
    'INVOICES': false,
    'TRANSCRIPTS': false,
    'SUMMARIES': false,
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final data = await widget.rbacService.getCareCirclePermissions(widget.patientId);
      if (mounted && data['permissions'] != null) {
        final List dynamicPermissions = data['permissions'];
        setState(() {
          for (var feature in _featuresState.keys) {
            _featuresState[feature] = dynamicPermissions.contains(feature);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load permission states.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onToggleChanged(String feature, bool newValue) async {
    setState(() => _isLoading = true);
    final request = PermissionGrantRequest(targetUserId: widget.targetUserId, feature: feature);
    
    try {
      if (newValue) {
        await widget.rbacService.grantFeatureAccess(widget.patientId, request);
      } else {
        await widget.rbacService.revokeFeatureAccess(widget.patientId, request);
      }
      if (mounted) {
        setState(() {
          _featuresState[feature] = newValue;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update access control status for $feature')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Representative Access')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: _featuresState.keys.map((feature) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48.0), 
              child: SwitchListTile(
                title: Text(feature),
                subtitle: Text('Allow access to customer $feature modules'),
                value: _featuresState[feature]!,
                onChanged: (bool value) => _onToggleChanged(feature, value),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}