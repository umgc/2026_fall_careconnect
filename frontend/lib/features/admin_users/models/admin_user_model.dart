class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.emailVerified,
    this.lastLoginDate,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final bool emailVerified;
  final String? lastLoginDate;

  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? '',
      emailVerified: json['emailVerified'] as bool? ?? false,
      lastLoginDate: json['lastLoginDate'] as String?,
    );
  }
}
