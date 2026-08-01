import 'package:dio/dio.dart';
import '../models/permission_grant_request.dart';

class RbacService {
  final Dio _dio;

  RbacService(this._dio);

  // GET: Retrieve the current permission matrix for the care circle
  Future<Map<String, dynamic>> getCareCirclePermissions(String patientId) async {
    final response = await _dio.get('/v1/api/care-circle/$patientId/permissions');
    return response.data;
  }

  // POST: Grant feature access to a care-circle user
  Future<void> grantFeatureAccess(String patientId, PermissionGrantRequest request) async {
    await _dio.post(
      '/v1/api/care-circle/$patientId/permissions/grant',
      data: request.toJson(),
    );
  }

  // POST: Revoke feature access from a care-circle user
  Future<void> revokeFeatureAccess(String patientId, PermissionGrantRequest request) async {
    await _dio.post(
      '/v1/api/care-circle/$patientId/permissions/revoke',
      data: request.toJson(),
    );
  }
}