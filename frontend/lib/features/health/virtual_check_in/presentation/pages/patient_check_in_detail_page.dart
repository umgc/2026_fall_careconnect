import 'package:flutter/material.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_backend_question_model.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/answer_dto.dart';
import 'package:care_connect_app/features/health/virtual_check_in/widgets/check_in_answer_form.dart';
import 'package:care_connect_app/services/checkin_service.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';

/// Patient check-in detail page that displays questions and allows answering.
/// Shows check-in status, instructions, and the answer form.
class PatientCheckInDetailPage extends StatefulWidget {
  final int checkInId;
  final List<BackendQuestionDto> questions;

  const PatientCheckInDetailPage({
    super.key,
    required this.checkInId,
    required this.questions,
  });

  @override
  State<PatientCheckInDetailPage> createState() =>
      _PatientCheckInDetailPageState();
}

class _PatientCheckInDetailPageState extends State<PatientCheckInDetailPage> {
  late List<AnswerUpsertRequestDTO> _answers = [];
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _submitted = false;

  /// Handle submission of check-in answers
  Future<void> _handleSubmitAnswers() async {
    if (_answers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please answer at least one question'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final request = SubmitAnswersRequestDTO(answers: _answers);
      final response = await CheckinService.submitAnswers(
        checkInId: widget.checkInId,
        request: request,
      );

      if (!mounted) return;

      setState(() {
        _submitted = true;
        _isSubmitting = false;
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Successfully submitted ${response.acceptedAnswerCount} answer(s)'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back after a short delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Check-In Questions',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _submitted
          ? _buildSubmissionSuccessWidget()
          : _buildAnswerFormWidget(),
    );
  }

  /// Build the answer form UI
  Widget _buildAnswerFormWidget() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Please answer the following questions:',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                border: Border.all(color: Colors.red.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),
          const SizedBox(height: 20),
          CheckInAnswerForm(
            questions: widget.questions,
            isLoading: _isSubmitting,
            onAnswersChanged: (answers) {
              setState(() {
                _answers = answers;
              });
            },
            onSubmit: _handleSubmitAnswers,
          ),
        ],
      ),
    );
  }

  /// Build success message UI
  Widget _buildSubmissionSuccessWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.green.shade600,
            ),
            const SizedBox(height: 24),
            Text(
              'Check-In Complete!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your answers have been successfully submitted.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Return to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
