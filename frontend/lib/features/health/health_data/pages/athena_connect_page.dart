import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/athena_connect_tile.dart';

/// Route /athena-connect. Hosts the athenahealth tile with its consent text,
/// like /medicare-connect does for Medicare. There is no browser return to
/// handle: athenahealth connects in place (2-legged OAuth).
class AthenaConnectPage extends StatelessWidget {
  const AthenaConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        // The dark theme's title style is light grey; this bar stays white.
        titleTextStyle: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.w600),
        title: const Text('Connect athenahealth'),
        leading: IconButton(
          tooltip: 'Back to Health Data',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/health-data'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Text(
                  'Connect your athenahealth provider to see your health '
                  'records with the rest of your health information.',
                  style: TextStyle(
                      fontSize: 16, height: 1.45, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 16),
                AthenaConnectTile(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
