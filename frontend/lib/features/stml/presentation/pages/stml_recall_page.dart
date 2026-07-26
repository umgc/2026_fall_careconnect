import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/stml_service.dart';

/// A single recall question/answer turn.
class _RecallTurn {
  final String question;
  StmlRecallResult? result;
  String? error;
  bool isLoading = true;

  _RecallTurn({required this.question});
}

/// STML-1: "What did we discuss?" recall — answers plain-language recall
/// questions from existing summaries and indexed records, with source
/// citations (STML-5: first-time-clarity, 18pt+ text).
class StmlRecallPage extends StatefulWidget {
  const StmlRecallPage({super.key});

  @override
  State<StmlRecallPage> createState() => _StmlRecallPageState();
}

class _StmlRecallPageState extends State<StmlRecallPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_RecallTurn> _turns = [];
  bool _isSending = false;

  static const _suggestions = [
    'What did we discuss in my last call?',
    'What did we talk about at my last visit?',
    'What do I need to do next?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submit([String? presetQuestion]) async {
    final question = (presetQuestion ?? _controller.text).trim();
    if (question.isEmpty || _isSending) return;

    final patientId = context.read<UserProvider>().user?.patientId;
    if (patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No patient is selected for this account.')),
      );
      return;
    }

    final turn = _RecallTurn(question: question);
    setState(() {
      _turns.add(turn);
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final result = await StmlService.recall(patientId: patientId, question: question);
      setState(() => turn.result = result);
    } on StmlException catch (e) {
      setState(() => turn.error = e.message);
    } finally {
      setState(() {
        turn.isLoading = false;
        _isSending = false;
      });
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
        title: const Text('What did we discuss?'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
      ),
      body: Column(
        children: [
          Expanded(
            child: _turns.isEmpty
                ? _SuggestionList(suggestions: _suggestions, onTap: _submit)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _turns.length,
                    itemBuilder: (context, index) => _RecallTurnCard(turn: _turns[index]),
                  ),
          ),
          SafeArea(
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
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'Ask what we discussed…',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      enabled: !_isSending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : () => _submit(),
                    icon: _isSending
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
          ),
        ],
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const _SuggestionList({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Ask about a recent call or visit.',
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  onPressed: () => onTap(s),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  child: Text(s, textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecallTurnCard extends StatelessWidget {
  final _RecallTurn turn;

  const _RecallTurnCard({required this.turn});

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
          Align(
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
                              turn.result!.answer,
                              style: const TextStyle(fontSize: 18, height: 1.35),
                            ),
                            if (turn.result!.sources.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              for (final source in turn.result!.sources)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${source.sourceType} · ${source.date}: ${source.summary}',
                                    style: AppTheme.bodySmall.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                            if (turn.result!.disclaimer.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                turn.result!.disclaimer,
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
