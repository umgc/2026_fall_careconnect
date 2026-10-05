import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/medicare_connect_service.dart';
import '../widgets/medicare_connect_tile.dart';

/// Route /medicare-connect. Hosts the tile and is where the browser lands
/// after the Medicare sign-in. Unlike the old bare Scaffold, it has an app bar
/// so a patient arriving here from the redirect always has a way back.
class MedicareConnectPage extends StatelessWidget {
  const MedicareConnectPage({super.key, this.result});

  final MedicareConnectResult? result;

  /// Lets the "/" route forward a base-URL return here exactly once per page
  /// load, so visiting the welcome page later doesn't bounce back.
  static bool returnHandled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text('Connect Medicare'),
        leading: IconButton(
          tooltip: 'Back to Health Data',
          icon: const Icon(Icons.arrow_back),
          // After a full-page redirect there's nothing to pop, so go
          // somewhere sensible instead of leaving the patient stuck.
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/health-data'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Connect your Medicare account to see your Medicare claims '
                  'with the rest of your health information.',
                  style: TextStyle(
                      fontSize: 16, height: 1.45, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 16),
                MedicareConnectTile(result: result),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
