import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class CancelScreen extends StatelessWidget {
  const CancelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: const Text("CareConnect"),
        centerTitle: true,
        backgroundColor: const Color(0xFF14366E),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel, color: Colors.red, size: 60),
            const SizedBox(height: 20),
            Text(
              t.cancelscreen_sosRequestCancel,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(t.cancelscreen_sosCancelConfirm),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF14366E),
                foregroundColor: Colors.white,
              ),
              child: Text(t.sosscreen_backButton),
            ),
          ],
        ),
      ),
    );
  }
}
