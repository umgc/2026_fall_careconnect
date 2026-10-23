import 'package:flutter/material.dart';

class UserSession {
  final int id;
  final String role;
  final String token;
  final int? patientId;
  final int? caregiverId;

  UserSession({
    required this.id,
    required this.role,
    required this.token,
    this.patientId,
    this.caregiverId,
  });
}

class UserProvider extends ChangeNotifier {
  UserSession? _user;
  UserSession? get user => _user;

  void setUser(UserSession user) {
    _user = user;
    notifyListeners();
  }

  void clearUser() {
    _user = null;
    notifyListeners();
  }
}
