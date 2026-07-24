import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ai_chat_improved.dart';
import '../providers/user_provider.dart';

/// A modal dialog wrapper for the AI chat component
class AIChatModal extends StatelessWidget {
  final String role;
  final AiChatMode mode;
  final int? patientId;

  const AIChatModal({
    super.key,
    required this.role,
    required this.mode,
    this.patientId,
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    // Grounded patient modals may use the logged-in patient session id.
    // Caregiver grounded chat must pass an explicit linked patientId — never
    // infer mutable UserSession.patientId.
    final resolvedPatientId = patientId ??
        (mode == AiChatMode.groundedRecords && role.toLowerCase() == 'patient'
            ? user?.patientId
            : null);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withOpacity(0.1),
              spreadRadius: 5,
              blurRadius: 15,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: AIChat(
          key: ValueKey(
            'ai-chat-${mode.name}-${resolvedPatientId ?? 'none'}',
          ),
          role: role,
          isModal: true,
          patientId: resolvedPatientId,
          userId: user?.id,
          mode: mode,
        ),
      ),
    );
  }
}
