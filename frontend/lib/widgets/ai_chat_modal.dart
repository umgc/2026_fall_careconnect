import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ai_chat_improved.dart';
import '../providers/user_provider.dart';

/// A modal dialog wrapper for the AI chat component
class AIChatModal extends StatelessWidget {
  final String role;

  const AIChatModal({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

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
          role: role,
          isModal: true,
          patientId: user?.patientId,
          userId: user?.id,
          mode: AiChatMode.groundedRecords,
        ),
      ),
    );
  }
}
