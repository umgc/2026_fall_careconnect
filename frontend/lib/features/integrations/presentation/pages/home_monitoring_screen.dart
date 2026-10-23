import 'package:flutter/material.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';

class HomeMonitoringScreen extends StatefulWidget {
  const HomeMonitoringScreen({super.key});

  @override
  State<HomeMonitoringScreen> createState() => _HomeMonitoringScreenState();
}

class _HomeMonitoringScreenState extends State<HomeMonitoringScreen> {
  // Empty list - no cameras connected yet
  List<Map<String, dynamic>> connectedCameras = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CommonDrawer(currentRoute: '/home-monitoring'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Home Monitoring',
        centerTitle: true,
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _navigateToAddCamera,
          ),
        ],
      ),
      body: connectedCameras.isEmpty ? _buildEmptyState() : _buildCameraList(),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large camera icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.videocam,
              size: 60,
              color: Theme.of(context).primaryColor,
            ),
          ),

          const SizedBox(height: 32),

          // Title
          Text(
            'No Cameras Connected',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),

          const SizedBox(height: 16),

          // Description
          const Text(
            'Connect Nest cameras to monitor your patient\'s home environment and ensure their safety.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.4),
          ),

          const SizedBox(height: 40),

          // Add Camera Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                _navigateToAddCamera();
              },
              icon: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              label: Text(
                'Add Your First Camera',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Supported Cameras
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Supported Cameras',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSupportedCamera(
                        icon: Icons.videocam,
                        name: 'Nest Cam Indoor',
                        color: Colors.green,
                      ),
                      _buildSupportedCamera(
                        icon: Icons.camera_outdoor,
                        name: 'Nest Cam Outdoor',
                        color: Colors.blue,
                      ),
                      _buildSupportedCamera(
                        icon: Icons.doorbell,
                        name: 'Nest Doorbell',
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedCamera({
    required IconData icon,
    required String name,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCameraList() {
    // This will be used later when cameras are added
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          const Text(
            'Connected Cameras',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${connectedCameras.length} cameras monitoring',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 20),

          // Camera List (will be populated later)
          Expanded(
            child: ListView.builder(
              itemCount: connectedCameras.length,
              itemBuilder: (context, index) {
                return const Card(child: ListTile(title: Text('Camera')));
              },
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToAddCamera() {
    // For now, show a simple dialog
    // Later, this will navigate to AddCameraScreen
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Camera'),
          content: const Text(
            'This will open the Nest camera setup screen.\n\n(Navigation to camera setup will be implemented here)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Nest camera setup coming soon!'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
              ),
              child: Text(
                'OK',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
