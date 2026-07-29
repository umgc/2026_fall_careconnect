import 'package:flutter/material.dart';

import '../../../../widgets/app_bar_helper.dart';
import '../../../../widgets/role_based_drawer.dart';
import '../../data/admin_users_api.dart';
import '../../models/admin_user_model.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final AdminUsersApi _api = const AdminUsersApi();

  List<AdminUser>? _users;
  String? _error;
  bool _loading = true;
  int? _promotingUserId;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await _api.fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } on AdminUsersApiException catch (ex) {
      if (!mounted) return;
      setState(() {
        _error = ex.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load users';
        _loading = false;
      });
    }
  }

  Future<void> _confirmPromote(AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promote to Admin'),
        content: Text(
          'Grant admin access to ${user.name.isNotEmpty ? user.name : user.email}? '
          'They will be able to manage users and view product analytics.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Promote'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _promoteUser(user);
  }

  Future<void> _promoteUser(AdminUser user) async {
    setState(() => _promotingUserId = user.id);

    try {
      await _api.promoteToAdmin(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${user.name.isNotEmpty ? user.name : user.email} is now an admin',
          ),
        ),
      );
      await _loadUsers();
    } on AdminUsersApiException catch (ex) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ex.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to promote user')),
      );
    } finally {
      if (mounted) {
        setState(() => _promotingUserId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'User Management',
        additionalActions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadUsers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const RoleBasedDrawer(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _users == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && (_users == null || _users!.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadUsers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final users = _users ?? const <AdminUser>[];

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: users.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No users found')),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final user = users[index];
                return _AdminUserTile(
                  user: user,
                  promoting: _promotingUserId == user.id,
                  onPromote: user.isAdmin ? null : () => _confirmPromote(user),
                );
              },
            ),
    );
  }
}

class _AdminUserTile extends StatelessWidget {
  const _AdminUserTile({
    required this.user,
    required this.promoting,
    this.onPromote,
  });

  final AdminUser user;
  final bool promoting;
  final VoidCallback? onPromote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = user.name.isNotEmpty ? user.name : user.email;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(user.email, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                _RoleChip(role: user.role),
              ],
            ),
            if (onPromote != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: promoting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton.tonal(
                        onPressed: onPromote,
                        child: const Text('Promote to Admin'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAdmin = role.toUpperCase() == 'ADMIN';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.replaceAll('_', ' '),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
