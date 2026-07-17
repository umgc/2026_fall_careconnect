import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/ask_ai_service.dart';

/// A single question/answer turn shown in the Ask AI transcript.
class _AskAiTurn {
  final String question;
  String? answer;
  int? chunksUsed;
  String? error;
  bool isLoading = true;

  _AskAiTurn({required this.question});
}

/// AI-Assisted Retrieval screen (SRS §3 / FR-AI-1 through FR-AI-11).
///
/// Lets the user ask a natural-language question and see an answer grounded
/// strictly in their own indexed records, with a persistent non-medical-
/// advice disclaimer (REQ-SC-1, FR-AI-3). There is no citations array from
/// the backend yet (see AiAskResponse) — this screen shows the number of
/// record chunks the answer was grounded in instead, and is structured so
/// per-item citations can be added later without a layout change.
class AskAiPage extends StatefulWidget {
  const AskAiPage({super.key});

  @override
  State<AskAiPage> createState() => _AskAiPageState();
}

class _AskAiPageState extends State<AskAiPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AskAiTurn> _turns = [];
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitQuestion() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _isSending) {
      return;
    }

    final patientId = context.read<UserProvider>().user?.patientId;
    if (patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No patient is selected for this account.'),
        ),
      );
      return;
    }

    final turn = _AskAiTurn(question: question);
    setState(() {
      _turns.add(turn);
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final result = await AskAiService.ask(
        patientId: patientId,
        question: question,
      );
      setState(() {
        turn.answer = result.answer;
        turn.chunksUsed = result.chunksUsed;
        turn.isLoading = false;
      });
    } on AskAiException catch (e) {
      setState(() {
        turn.error = e.message;
        turn.isLoading = false;
      });
    } finally {
      setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundSecondary,
      appBar: AppBar(
        title: const Text('Ask AI'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
      ),
      body: Column(
        children: [
          _DisclaimerBanner(),
          Expanded(
            child: _turns.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _turns.length,
                    itemBuilder: (context, index) =>
                        _AskAiTurnCard(turn: _turns[index]),
                  ),
          ),
          _QuestionInput(
            controller: _controller,
            isSending: _isSending,
            onSubmit: _submitQuestion,
          ),
        ],
      ),
    );
  }
}

/// Persistent, non-dismissible notice per REQ-SC-1 / FR-AI-3: every
/// records-grounded response is framed as based on stored records, never
/// as professional medical advice.
class _DisclaimerBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.info.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: AppTheme.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Answers are based on your stored records only and are not '
              'medical advice. Always confirm care decisions with your '
              'provider.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Ask a question about your records — appointments, '
              'medications, or what was discussed in a recent call or visit.',
              textAlign: TextAlign.center,
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AskAiTurnCard extends StatelessWidget {
  final _AskAiTurn turn;

  const _AskAiTurnCard({required this.turn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                turn.question,
                style: const TextStyle(color: AppTheme.textLight, fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _AnswerBubble(turn: turn),
        ],
      ),
    );
  }
}

class _AnswerBubble extends StatelessWidget {
  final _AskAiTurn turn;

  const _AnswerBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: turn.isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : turn.error != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 18, color: AppTheme.error),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          turn.error!,
                          style: const TextStyle(color: AppTheme.error, fontSize: 16),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        turn.answer ?? '',
                        style: const TextStyle(fontSize: 18, height: 1.35),
                      ),
                      if ((turn.chunksUsed ?? 0) > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Based on ${turn.chunksUsed} record'
                          '${turn.chunksUsed == 1 ? '' : 's'} from your account.',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _QuestionInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSubmit;

  const _QuestionInput({
    required this.controller,
    required this.isSending,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundPrimary,
          border: Border(top: BorderSide(color: AppTheme.borderColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  hintText: 'Ask about your appointments, medications…',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                enabled: !isSending,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: isSending ? null : onSubmit,
              icon: isSending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textLight,
                      ),
                    )
                  : const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
