import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../widgets/role_based_drawer.dart';
import '../widgets/role_widgets.dart';

class RBACTestScreen extends StatelessWidget {
  const RBACTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.userSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RBAC Test'),
        actions: [
          if (user != null)
            Chip(
              label: Text(user.role),
              backgroundColor: Colors.white,
            ),
          const SizedBox(width: 16),
        ],
      ),
      drawer: const RoleBasedDrawer(),
      body: user == null
          ? _buildLoginButtons(context, userProvider)
          : _buildTestContent(context, user),
    );
  }

  Widget _buildLoginButtons(BuildContext context, UserProvider userProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Select a role to test RBAC:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Admin Test
          ElevatedButton.icon(
            onPressed: () => _setMockUser(userProvider, 'ADMIN'),
            icon: const Icon(Icons.admin_panel_settings),
            label: const Text('Login as Admin'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size(200, 50),
            ),
          ),
          const SizedBox(height: 12),

          // Caregiver Test
          ElevatedButton.icon(
            onPressed: () => _setMockUser(userProvider, 'CAREGIVER'),
            icon: const Icon(Icons.people),
            label: const Text('Login as Caregiver'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              minimumSize: const Size(200, 50),
            ),
          ),
          const SizedBox(height: 12),

          // Patient Test
          ElevatedButton.icon(
            onPressed: () => _setMockUser(userProvider, 'PATIENT'),
            icon: const Icon(Icons.person),
            label: const Text('Login as Patient'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              minimumSize: const Size(200, 50),
            ),
          ),
          const SizedBox(height: 12),

          // Family Member Test
          ElevatedButton.icon(
            onPressed: () => _setMockUser(userProvider, 'FAMILY_MEMBER'),
            icon: const Icon(Icons.family_restroom),
            label: const Text('Login as Family Member'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              minimumSize: const Size(200, 50),
            ),
          ),
        ],
      ),
    );
  }

  void _setMockUser(UserProvider userProvider, String role) {
    final mockUser = UserSession(
      id: 1,
      name: 'Test ${role.toLowerCase()}',
      email: '${role.toLowerCase()}@test.com',
      role: role,
      token: 'mock-token-12345',
      patientId: role == 'PATIENT' ? 1 : null,
      caregiverId: role == 'CAREGIVER' ? 1 : null,
    );
    userProvider.setUser(mockUser);
  }

  Widget _buildTestContent(BuildContext context, UserSession user) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User Info Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current User: ${user.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Email: ${user.email}'),
                Text('Role: ${user.role}'),
                Text('User ID: ${user.id}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Test Admin-Only Content
        const Text(
          'Admin-Only Section:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        AdminOnly(
          fallback: Card(
            color: Colors.grey.shade200,
            child: const ListTile(
              leading: Icon(Icons.block),
              title: Text('Access Denied'),
              subtitle: Text('Admin only'),
            ),
          ),
          child: Card(
            color: Colors.red.shade50,
            child: const ListTile(
              leading: Icon(Icons.admin_panel_settings, color: Colors.red),
              title: Text('Admin Control Panel'),
              subtitle: Text('Only admins can see this'),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Test Caregiver/Admin Content
        const Text(
          'Caregiver or Admin Section:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        CaregiverOrAdmin(
          fallback: Card(
            color: Colors.grey.shade200,
            child: const ListTile(
              leading: Icon(Icons.block),
              title: Text('Access Denied'),
              subtitle: Text('Caregivers and admins only'),
            ),
          ),
          child: Card(
            color: Colors.blue.shade50,
            child: const ListTile(
              leading: Icon(Icons.people, color: Colors.blue),
              title: Text('Patient Management'),
              subtitle: Text('Caregivers and admins can see this'),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Test Permission Buttons
        const Text(
          'Permission-Based Buttons:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PermissionButton(
              permission: 'DELETE_PATIENTS',
              onPressed: () => _showMessage(context, 'Delete Patients'),
              child: const Text('Delete Patient (Admin Only)'),
            ),
            PermissionButton(
              permission: 'CREATE_TASKS',
              onPressed: () => _showMessage(context, 'Create Tasks'),
              child: const Text('Create Task'),
            ),
            PermissionButton(
              permission: 'VIEW_HEALTH_DATA',
              onPressed: () => _showMessage(context, 'View Health Data'),
              child: const Text('View Health'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Test Not Family Member
        const Text(
          'Not Family Member Section:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        NotFamilyMember(
          fallback: Card(
            color: Colors.grey.shade200,
            child: const ListTile(
              leading: Icon(Icons.block),
              title: Text('Read-Only Access'),
              subtitle: Text('Family members cannot edit'),
            ),
          ),
          child: Card(
            color: Colors.green.shade50,
            child: const ListTile(
              leading: Icon(Icons.edit, color: Colors.green),
              title: Text('Edit Data'),
              subtitle: Text('Everyone except family members'),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Logout Button
        Center(
          child: ElevatedButton.icon(
            onPressed: () {
              Provider.of<UserProvider>(context, listen: false).clearUser();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              minimumSize: const Size(200, 50),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Test Instructions
        Card(
          color: Colors.amber.shade50,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🧪 Test Instructions:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('1. Open the drawer (☰) - menu adapts to your role'),
                Text('2. Check which buttons are visible/hidden'),
                Text('3. Try clicking permission-based buttons'),
                Text('4. Logout and login as different roles to compare'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showMessage(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Action: $action - This would call the backend'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
