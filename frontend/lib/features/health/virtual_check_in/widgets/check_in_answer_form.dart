import 'package:flutter/material.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/question_type.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/answer_dto.dart';

/// Widget that displays a form for answering check-in questions.
/// Supports TEXT, YES_NO, TRUE_FALSE, and NUMBER question types.
class CheckInAnswerForm extends StatefulWidget {
  final List<BackendQuestionDto> questions;
  final VoidCallback onSubmit;
  final Function(List<AnswerUpsertRequestDTO>) onAnswersChanged;
  final bool isLoading;

  const CheckInAnswerForm({
    super.key,
    required this.questions,
    required this.onSubmit,
    required this.onAnswersChanged,
    this.isLoading = false,
  });

  @override
  State<CheckInAnswerForm> createState() => _CheckInAnswerFormState();
}

class _CheckInAnswerFormState extends State<CheckInAnswerForm> {
  late Map<int, dynamic> _answers; // question ID -> answer value
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _answers = {};
  }

  /// Build the appropriate input widget based on question type
  Widget _buildQuestionInput(BackendQuestionDto question) {
    final questionId = question.id;
    if (questionId == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Invalid question data',
          style: TextStyle(
            color: Colors.red.shade600,
            fontSize: 12,
          ),
        ),
      );
    }

    switch (question.type) {
      case BackendQuestionType.text:
        return _buildTextInput(question);
      case BackendQuestionType.yesNo:
        return _buildYesNoInput(question);
      case BackendQuestionType.trueFalse:
        return _buildTrueFalseInput(question);
      case BackendQuestionType.number:
        return _buildNumberInput(question);
    }
  }

  Widget _buildTextInput(BackendQuestionDto question) {
    final questionId = question.id;
    if (questionId == null) {
      return const SizedBox.shrink();
    }

    return TextFormField(
      decoration: InputDecoration(
        hintText: 'Enter your answer',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      maxLines: null,
      validator: question.required
          ? (value) => (value?.isEmpty ?? true) ? 'This field is required' : null
          : null,
      onChanged: (value) {
        _answers[questionId] = value;
        _notifyAnswersChanged();
      },
    );
  }

  Widget _buildYesNoInput(BackendQuestionDto question) {
    final questionId = question.id;
    if (questionId == null) {
      return const SizedBox.shrink();
    }

    return FormField<bool>(
      validator: question.required
          ? (value) => value == null ? 'Please select Yes or No' : null
          : null,
      builder: (state) {
        final selected = _answers[questionId] as bool?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Yes'),
                    selected: selected == true,
                    onSelected: (value) {
                      setState(() {
                        _answers[questionId] = value ? true : null;
                        state.didChange(value ? true : null);
                        _notifyAnswersChanged();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('No'),
                    selected: selected == false,
                    onSelected: (value) {
                      setState(() {
                        _answers[questionId] = value ? false : null;
                        state.didChange(value ? false : null);
                        _notifyAnswersChanged();
                      });
                    },
                  ),
                ),
              ],
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.errorText ?? '',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTrueFalseInput(BackendQuestionDto question) {
    final questionId = question.id;
    if (questionId == null) {
      return const SizedBox.shrink();
    }

    return FormField<bool>(
      validator: question.required
          ? (value) => value == null ? 'Please select True or False' : null
          : null,
      builder: (state) {
        final selected = _answers[questionId] as bool?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('True'),
                    selected: selected == true,
                    onSelected: (value) {
                      setState(() {
                        _answers[questionId] = value ? true : null;
                        state.didChange(value ? true : null);
                        _notifyAnswersChanged();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('False'),
                    selected: selected == false,
                    onSelected: (value) {
                      setState(() {
                        _answers[questionId] = value ? false : null;
                        state.didChange(value ? false : null);
                        _notifyAnswersChanged();
                      });
                    },
                  ),
                ),
              ],
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.errorText ?? '',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNumberInput(BackendQuestionDto question) {
    final questionId = question.id;
    if (questionId == null) {
      return const SizedBox.shrink();
    }

    return TextFormField(
      decoration: InputDecoration(
        hintText: 'Enter a number',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: question.required
          ? (value) {
              if (value?.isEmpty ?? true) return 'This field is required';
              if (num.tryParse(value!) == null) return 'Please enter a valid number';
              return null;
            }
          : (value) {
              if (value?.isNotEmpty ?? false) {
                if (num.tryParse(value!) == null) return 'Please enter a valid number';
              }
              return null;
            },
      onChanged: (value) {
        _answers[questionId] = value.isEmpty ? null : num.tryParse(value);
        _notifyAnswersChanged();
      },
    );
  }

  void _notifyAnswersChanged() {
    final answerList = widget.questions
        .where((q) {
          if (q.id == null || !_answers.containsKey(q.id)) return false;
          final value = _answers[q.id];
          if (value == null) return false;
          if (value is String && value.isEmpty) return false;
          return true;
        })
        .map((q) => AnswerUpsertRequestDTO.fromInput(
              questionId: q.id!,
              type: q.type,
              value: _answers[q.id],
            ))
        .toList();
    widget.onAnswersChanged(answerList);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          ...widget.questions.map((question) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: question.prompt,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        if (question.required)
                          TextSpan(
                            text: ' *',
                            style: TextStyle(color: Colors.red.shade600),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildQuestionInput(question),
                ],
              ),
            );
          }),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.isLoading
                  ? null
                  : () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSubmit();
                      }
                    },
              child: widget.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Answers'),
            ),
          ),
        ],
      ),
    );
  }
}
