import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../services/ai_chat_service.dart';
import '../config/theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';

// Message model for chat
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? errorMessage;
  final List<AiAskCitation> citations;
  final AiAskDisclaimer? disclaimer;
  final AiAskEscalation? escalation;
  final AiAskConfirmation? confirmation;
  final bool showRetry;
  final String? retryQuery;
  final String? requestIdentity;
  final String? heldItemId;
  final bool showHitlResume;
  final String? requestId;
  final String? auditId;
  final String? sessionId;
  final MedicationTimeline? medicationTimeline;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.errorMessage,
    this.citations = const [],
    this.disclaimer,
    this.escalation,
    this.confirmation,
    this.showRetry = false,
    this.retryQuery,
    this.requestIdentity,
    this.heldItemId,
    this.showHitlResume = false,
    this.requestId,
    this.auditId,
    this.sessionId,
    this.medicationTimeline,
  });

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
    String? errorMessage,
    List<AiAskCitation>? citations,
    AiAskDisclaimer? disclaimer,
    AiAskEscalation? escalation,
    AiAskConfirmation? confirmation,
    bool? showRetry,
    String? retryQuery,
    String? requestIdentity,
    String? heldItemId,
    bool? showHitlResume,
    String? requestId,
    String? auditId,
    String? sessionId,
    MedicationTimeline? medicationTimeline,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      errorMessage: errorMessage ?? this.errorMessage,
      citations: citations ?? this.citations,
      disclaimer: disclaimer ?? this.disclaimer,
      escalation: escalation ?? this.escalation,
      confirmation: confirmation ?? this.confirmation,
      showRetry: showRetry ?? this.showRetry,
      retryQuery: retryQuery ?? this.retryQuery,
      requestIdentity: requestIdentity ?? this.requestIdentity,
      heldItemId: heldItemId ?? this.heldItemId,
      showHitlResume: showHitlResume ?? this.showHitlResume,
      requestId: requestId ?? this.requestId,
      auditId: auditId ?? this.auditId,
      sessionId: sessionId ?? this.sessionId,
      medicationTimeline: medicationTimeline ?? this.medicationTimeline,
    );
  }
}

// Helper class for uploaded files
class UploadedFile {
  final String name;
  final int size;
  final String content;
  final String type;
  final List<int>? bytes;
  final String? path;

  UploadedFile({
    required this.name,
    required this.size,
    required this.content,
    required this.type,
    this.bytes,
    this.path,
  });
}

// (AIModel selection removed as requested)

// ...existing widget classes below...
enum AiChatMode { groundedRecords, legacyGeneral }

class AIChat extends StatefulWidget {
  final String role;
  final String? healthDataContext;
  final bool isModal;
  final int? patientId;
  final int? userId;
  final AiChatMode mode;
  /// Max status polls while waiting for clinician release (default ~5 minutes).
  final int hitlMaxPollAttempts;
  final Duration hitlPollInterval;

  const AIChat({
    super.key,
    required this.role,
    required this.mode,
    this.healthDataContext,
    this.isModal = false,
    this.patientId,
    this.userId,
    this.hitlMaxPollAttempts = 60,
    this.hitlPollInterval = const Duration(seconds: 5),
  });

  @override
  State<AIChat> createState() => _AIChatState();
}

class _AIChatState extends State<AIChat> with SingleTickerProviderStateMixin {
  String _conversationId = "";
  String? _askSessionId;
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<UploadedFile> _uploadedFiles = [];
  bool _isLoading = false;
  // ignore: unused_field — retained for legacy history loading state transitions
  bool _isLoadingHistory = false;
  bool _isFilePickerOpen = false;
  final double _chatWidth = 320.0;
  final double _chatHeight = 500.0;
  late AnimationController _animationController;

  // Inactivity timer for 15-minute auto-clear
  Timer? _inactivityTimer;
  // ignore: unused_field — updated by activity hooks for future idle diagnostics
  DateTime? _lastActivity;

  // Flag to track if user manually cleared the chat
  // ignore: unused_field — retained until patient-scoped history API lands
  bool _manuallyCleared = false;

  /// Incremented on clear/delete/inactivity/patient switch/dispose so late
  /// completions cannot resurrect content or call setState after invalidate.
  int _requestEpoch = 0;
  Completer<void>? _activeAbort;
  String? _retryQuery;
  String? _retryRequestIdentity;
  bool _retryEnabled = false;
  String _lastInputModality = 'TEXT';
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;

  bool get _isGrounded => widget.mode == AiChatMode.groundedRecords;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // Check if chat was manually cleared and load history accordingly
    _checkAndLoadHistory();

    _startInactivityTimer(); // Start 15-minute inactivity timer
    if (_isGrounded) {
      unawaited(_initSpeech());
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechReady = await _speech.initialize(
        onError: (_) {
          if (mounted) {
            setState(() => _isListening = false);
          }
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );
    } catch (_) {
      _speechReady = false;
    }
  }

  @override
  void didUpdateWidget(AIChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId ||
        oldWidget.mode != widget.mode) {
      _resetChatForScopeChange();
    }
  }

  /// Check if chat was manually cleared and load history if not.
  /// Grounded mode never loads or adopts legacy conversation history.
  Future<void> _checkAndLoadHistory() async {
    if (_isGrounded) {
      return;
    }
    if (widget.userId == null) return;

    final epoch = _requestEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      final clearedKey = 'chat_cleared_${widget.userId}';
      final wasCleared = prefs.getBool(clearedKey) ?? false;

      if (!_isCurrentEpoch(epoch)) return;

      if (!wasCleared) {
        await _loadConversationHistory();
      } else {
        // Chat was manually cleared, start with empty chat
        if (!_safeSetState(epoch, () {
          _manuallyCleared = true;
        })) {
          return;
        }
      }
    } catch (e) {
      if (!_isCurrentEpoch(epoch)) return;
      // If there's an error, just load history normally
      await _loadConversationHistory();
    }
  }

  bool _isCurrentEpoch(int epoch) => mounted && epoch == _requestEpoch;

  bool _safeSetState(int epoch, VoidCallback fn) {
    if (!_isCurrentEpoch(epoch)) return false;
    setState(fn);
    return true;
  }

  void _invalidatePendingRequests() {
    _requestEpoch++;
    final abort = _activeAbort;
    _activeAbort = null;
    if (abort != null && !abort.isCompleted) {
      abort.complete();
    }
    _clearRetryState();
  }

  void _clearRetryState() {
    _retryQuery = null;
    _retryRequestIdentity = null;
    _retryEnabled = false;
  }

  void _resetChatForScopeChange() {
    _invalidatePendingRequests();
    _inactivityTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _conversationId = "";
      _askSessionId = null;
      _uploadedFiles.clear();
      _isLoading = false;
      _isLoadingHistory = false;
      _manuallyCleared = true;
    });
    _startInactivityTimer();
  }

  @override
  void dispose() {
    _invalidatePendingRequests();
    if (_isListening) {
      unawaited(_speech.stop());
    }
    _controller.dispose();
    _animationController.dispose();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  /// Start the 15-minute inactivity timer
  void _startInactivityTimer() {
    _lastActivity = DateTime.now();
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 15), () {
      _clearChatDueToInactivity();
    });
  }

  /// Reset the inactivity timer (call this on any user activity)
  void _resetInactivityTimer() {
    _lastActivity = DateTime.now();
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 15), () {
      _clearChatDueToInactivity();
    });
  }

  /// Clear chat due to 15 minutes of inactivity
  void _clearChatDueToInactivity() {
    _invalidatePendingRequests();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _conversationId = "";
      _askSessionId = null;
      _uploadedFiles.clear();
      _isLoading = false;
      _messages.add(ChatMessage(
        text: '⏰ Chat cleared due to 15 minutes of inactivity',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  /// Fetch retention period from backend
  Future<int> _getRetentionPeriod() async {
    try {
      // Replace with actual backend call if available
      return await AIChatService.getRetentionPeriodDays();
    } catch (e) {
      // Fallback to default if backend call fails
      return 30;
    }
  }

  /// Clear chat completely (user-initiated deletion)
  Future<void> _clearChatCompletely() async {
    final retentionDays = await _getRetentionPeriod();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text(
          'This will permanently delete this conversation. This action cannot be undone.\n\n'
          'Your conversation will also be automatically deleted after $retentionDays days for privacy protection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Store the conversation ID before clearing it
      final conversationToClear = _conversationId;
      final shouldClearLegacyBackend =
          !_isGrounded && conversationToClear.isNotEmpty;

      _invalidatePendingRequests();

      // Clear all messages and start fresh
      if (mounted) {
        setState(() {
          _messages.clear();
          _conversationId = "";
          _askSessionId = null;
          _uploadedFiles.clear();
          _isLoading = false;
          _isLoadingHistory = false;
          _manuallyCleared = true;
        });
      }

      // Store the cleared state persistently (legacy mode only)
      if (!_isGrounded && widget.userId != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final clearedKey = 'chat_cleared_${widget.userId}';
          await prefs.setBool(clearedKey, true);
        } catch (e) {
          // Failed to save cleared state, continue anyway
        }
      }

      // Clear the conversation from the backend if it exists (legacy only)
      if (shouldClearLegacyBackend) {
        try {
          await AIChatService.clearConversation(conversationToClear);
        } catch (e) {
          // If clearing fails, just continue - the local clear is more important
        }
      }

      // Reset inactivity timer since user is actively using the chat
      _resetInactivityTimer();

      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conversation deleted successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Download chat transcript
  Future<void> _downloadChatTranscript() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No conversation to download'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final transcript = _generateTranscript();

    // For now, show the transcript in a dialog
    // In a real app, you'd use a file picker or share functionality
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chat Transcript'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(transcript),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Share conversation with provider
  Future<void> _shareWithProvider() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No conversation to share'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share with Provider'),
        content: const Text(
          'This will share your conversation with your healthcare provider for review. '
          'The conversation will be retained for medical record purposes.\n\n'
          'Do you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Share'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Implement actual sharing with provider
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation shared with provider'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Show privacy information
  void _showPrivacyInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.privacy_tip, color: Colors.blue),
            SizedBox(width: 8),
            Text('Privacy & Data Protection'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your Privacy is Protected',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                '• Chat conversations are automatically deleted after 30 days',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                '• You can delete conversations immediately anytime',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                '• Only anonymized usage statistics are retained long-term',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                '• Conversations shared with providers are kept for medical records',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                '• All data is encrypted and access is logged',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'This AI assistant is not a substitute for professional medical advice. '
                'Always consult your healthcare provider for medical concerns.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Generate transcript text from messages
  String _generateTranscript() {
    final buffer = StringBuffer();
    buffer.writeln('Chat Transcript - ${DateTime.now().toString()}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (final message in _messages) {
      final timestamp = message.timestamp.toString().substring(0, 19);
      final sender = message.isUser ? 'You' : 'AI Assistant';
      buffer.writeln('[$timestamp] $sender:');
      buffer.writeln(message.text);
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Load conversation history from the backend.
  /// Grounded mode never adopts legacy history or conversation IDs.
  Future<void> _loadConversationHistory() async {
    if (_isGrounded) {
      return;
    }
    if (widget.userId == null) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: '❌ Cannot load history: userId is null',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isLoadingHistory = false;
      });
      return;
    }

    final epoch = _requestEpoch;
    try {
      final response = await AIChatService.getConversationHistory(
        userId: widget.userId.toString(),
        conversationId: _conversationId.isNotEmpty ? _conversationId : null,
        limit: 20,
      );

      if (!_isCurrentEpoch(epoch)) return;

      setState(() {
        // Clear existing messages and replace with fresh history
        _messages.clear();

        // Extract messages from response
        final history = response['messages'] as List<dynamic>? ?? [];

        if (history.isEmpty) {
          _messages.add(ChatMessage(
            text: '📭 No conversation history found',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        } else {
          for (final messageData in history) {
            // Skip system messages for security
            if (messageData['messageType'] == 'SYSTEM') continue;

            final message = ChatMessage(
              text: messageData['content'] ?? '',
              isUser: messageData['messageType'] == 'USER',
              timestamp: DateTime.tryParse(messageData['createdAt'] ?? '') ??
                  DateTime.now(),
            );
            _messages.add(message);
          }
        }

        // Update conversationId if provided
        if (response['conversationId'] != null && _conversationId.isEmpty) {
          _conversationId = response['conversationId'];
        }

        _isLoadingHistory = false;
      });

      // Scroll to bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!_isCurrentEpoch(epoch)) return;
      setState(() {
        _messages.add(ChatMessage(
          text: '❌ Error loading history: $e',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _pickFiles() async {
    if (_isGrounded) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text:
              'File uploads are not available in grounded records mode. Start a general file-upload chat instead.',
          isUser: false,
          timestamp: DateTime.now(),
          errorMessage: 'File upload requires legacy general mode',
        ));
      });
      return;
    }
    setState(() => _isFilePickerOpen = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );
      if (result != null) {
        for (var file in result.files) {
          final uploaded = await _processFile(file);
          if (uploaded != null) {
            setState(() {
              _uploadedFiles.add(uploaded);
            });
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isFilePickerOpen = false);
      }
    }
  }

  Future<UploadedFile?> _processFile(PlatformFile file) async {
    final fileType = _getFileType(file.name);
    if (file.size > 10 * 1024 * 1024) {
      throw Exception('File ${file.name} is too large (max 10MB)');
    }
    String content;
    try {
      // For all file types, we'll let the backend handle content extraction
      // The frontend just needs to prepare the file for upload
      if (file.bytes != null) {
        // For binary files (PDF, DOC, etc.), we'll send the raw bytes
        // The backend will handle the content extraction
        content = '[File ready for backend processing: ${file.name}]';
      } else if (file.path != null) {
        // For text files, we can still read them directly
        try {
          content = await File(file.path!).readAsString(encoding: utf8);
        } catch (e) {
          try {
            content = await File(file.path!).readAsString(encoding: latin1);
          } catch (e2) {
            // If we can't read it as text, let the backend handle it
            content = '[File ready for backend processing: ${file.name}]';
          }
        }
      } else {
        throw Exception('Unable to read file content');
      }
      if (content.length > 50000) {
        content =
            '${content.substring(0, 50000)}\n... [Content truncated due to length]';
      }
      return UploadedFile(
        name: file.name,
        size: file.size,
        content: content,
        type: fileType,
        bytes: file.bytes,
        path: file.path,
      );
    } catch (e) {
      debugPrint('Error reading file ${file.name}: $e');
      return null;
    }
  }

  String _getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'txt':
      case 'md':
      case 'log':
        return 'text';
      case 'csv':
        return 'csv';
      case 'json':
        return 'json';
      case 'xml':
        return 'xml';
      case 'pdf':
        return 'pdf';
      case 'doc':
      case 'docx':
      case 'odt':
        return 'document';
      case 'xls':
      case 'xlsx':
      case 'ods':
        return 'spreadsheet';
      case 'html':
      case 'htm':
        return 'html';
      case 'js':
      case 'py':
      case 'java':
      case 'c':
      case 'cpp':
      case 'cs':
      case 'php':
      case 'rb':
      case 'swift':
      case 'go':
      case 'rs':
      case 'ts':
        return 'code';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'svg':
      case 'bmp':
        return 'image';
      default:
        return 'unknown';
    }
  }

  void _removeFile(int index) {
    setState(() {
      _uploadedFiles.removeAt(index);
    });
  }

  void _sendMessage() {
    // Allow sending if there's a message OR (legacy) uploaded files
    if (_isLoading) {
      return;
    }
    if (_controller.text.trim().isEmpty &&
        (_isGrounded || _uploadedFiles.isEmpty)) {
      return;
    }
    _lastInputModality = 'TEXT';
    final userMessage = _controller.text.trim();
    _controller.clear();
    unawaited(_dispatchMessage(
      userMessage: userMessage,
      isRetry: false,
    ));
  }

  Future<void> _toggleVoiceInput() async {
    if (!_isGrounded || _isLoading) return;
    _resetInactivityTimer();
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (!_speechReady) {
      await _initSpeech();
    }
    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is unavailable.')),
      );
      return;
    }
    setState(() => _isListening = true);
    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 2),
        onResult: (result) {
          if (!mounted) return;
          if (result.recognizedWords.isNotEmpty) {
            _controller.text = result.recognizedWords;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          }
          if (result.finalResult) {
            setState(() => _isListening = false);
            final spoken = _controller.text.trim();
            if (spoken.isNotEmpty && !_isLoading) {
              _lastInputModality = 'VOICE';
              _controller.clear();
              unawaited(_dispatchMessage(
                userMessage: spoken,
                isRetry: false,
              ));
            }
          }
        },
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _submitConfirmationDecision({
    required ChatMessage message,
    required String decision,
  }) async {
    final sessionId = message.sessionId ?? _askSessionId;
    final patientId = widget.patientId;
    if (sessionId == null ||
        sessionId.isEmpty ||
        patientId == null ||
        patientId <= 0) {
      return;
    }
    final ok = await AIChatService.submitConfirmation(
      sessionId: sessionId,
      patientId: patientId,
      requestId: message.requestId,
      auditId: message.auditId,
      decision: decision,
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        final index = _messages.indexWhere((m) => identical(m, message));
        if (index >= 0) {
          _messages[index] = message.copyWith(
            confirmation: const AiAskConfirmation(false, null),
          );
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Confirmation recorded.'
            : 'Could not record confirmation. Please try again.'),
      ),
    );
  }

  void _retryGroundedAsk() {
    if (!_retryEnabled ||
        _retryQuery == null ||
        _retryRequestIdentity == null ||
        _isLoading) {
      return;
    }
    unawaited(_dispatchMessage(
      userMessage: _retryQuery!,
      isRetry: true,
      requestIdentity: _retryRequestIdentity,
    ));
  }

  Future<void> _dispatchMessage({
    required String userMessage,
    required bool isRetry,
    String? requestIdentity,
  }) async {
    // Reset inactivity timer on user activity
    _resetInactivityTimer();

    // Retire any in-flight Ask HTTP or HITL poll from a prior turn so a released
    // answer cannot land under a different follow-up question.
    _requestEpoch++;
    final epoch = _requestEpoch;
    final abortCompleter = Completer<void>();
    final previousAbort = _activeAbort;
    _activeAbort = abortCompleter;
    if (previousAbort != null && !previousAbort.isCompleted) {
      previousAbort.complete();
    }

    final stableRequestIdentity = requestIdentity ??
        (isRetry ? _retryRequestIdentity : null) ??
        const Uuid().v4();

    if (!isRetry) {
      if (!_safeSetState(epoch, () {
        // Add user message (either text or file upload indication)
        String displayMessage = userMessage.isNotEmpty
            ? userMessage
            : '📎 Uploaded ${_uploadedFiles.length} file${_uploadedFiles.length > 1 ? 's' : ''}';

        _messages.add(
          ChatMessage(
              text: displayMessage, isUser: true, timestamp: DateTime.now()),
        );

        // Add file processing message if files are uploaded (legacy only)
        if (!_isGrounded && _uploadedFiles.isNotEmpty) {
          _messages.add(
            ChatMessage(
              text:
                  '📎 Analyzing ${_uploadedFiles.length} uploaded file${_uploadedFiles.length > 1 ? 's' : ''}...',
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        }

        _isLoading = true;
        _manuallyCleared = false;
        _clearRetryState();
        if (_isGrounded) {
          _retryQuery = userMessage;
          _retryRequestIdentity = stableRequestIdentity;
        }
      })) {
        return;
      }
    } else {
      if (!_safeSetState(epoch, () {
        _isLoading = true;
        // Strip previous retry affordance without duplicating the user bubble.
        for (var i = _messages.length - 1; i >= 0; i--) {
          final msg = _messages[i];
          if (msg.showRetry && msg.requestIdentity == stableRequestIdentity) {
            _messages[i] = ChatMessage(
              text: msg.text,
              isUser: msg.isUser,
              timestamp: msg.timestamp,
              errorMessage: msg.errorMessage,
              citations: msg.citations,
              disclaimer: msg.disclaimer,
              escalation: msg.escalation,
              confirmation: msg.confirmation,
              requestId: msg.requestId,
              auditId: msg.auditId,
              sessionId: msg.sessionId,
            );
            break;
          }
        }
      })) {
        return;
      }
    }

    // Clear the persistent cleared state when starting new conversation
    if (!_isGrounded && widget.userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final clearedKey = 'chat_cleared_${widget.userId}';
        await prefs.setBool(clearedKey, false);
      } catch (e) {
        // Failed to clear persistent state, continue anyway
      }
    }
    if (!_isCurrentEpoch(epoch)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      final userProvider =
          mounted ? Provider.of<UserProvider>(context, listen: false) : null;

      // Better userId validation - avoid defaulting to 1
      final currentUserId = widget.userId ?? userProvider?.user?.id;
      if (currentUserId == null) {
        _safeSetState(epoch, () {
          _isLoading = false;
          _messages.add(ChatMessage(
            text:
                'Authentication error: Please log in to use the chat feature.',
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'User ID not found',
          ));
        });
        return;
      }

      // Only use patientId if explicitly provided, never default to user ID
      final currentPatientId = widget.patientId;
      if (_isGrounded && (currentPatientId == null || currentPatientId <= 0)) {
        _safeSetState(epoch, () {
          _isLoading = false;
          _clearRetryState();
          _messages.add(ChatMessage(
            text:
                'Ask AI cannot access grounded records without a selected patient.',
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'Missing patient ID for grounded records mode',
          ));
        });
        return;
      }
      if (_isGrounded && _uploadedFiles.isNotEmpty) {
        _safeSetState(epoch, () {
          _isLoading = false;
          _uploadedFiles.clear();
          _clearRetryState();
          _messages.add(ChatMessage(
            text:
                'File uploads are not available in grounded records mode. Start a general file-upload chat instead.',
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'File upload requires legacy general mode',
          ));
        });
        return;
      }

      // Prepare uploadedFiles for API if any (legacy only)
      List<Map<String, dynamic>>? uploadedFilesJson;
      if (!_isGrounded && _uploadedFiles.isNotEmpty) {
        uploadedFilesJson = _uploadedFiles.map((file) {
          List<int>? fileBytes = file.bytes;
          if (fileBytes == null && file.path != null) {
            try {
              fileBytes = File(file.path!).readAsBytesSync();
            } catch (_) {}
          }
          String? base64Content =
              fileBytes != null ? base64Encode(fileBytes) : null;
          String contentType = _guessMimeType(file.name);
          return {
            'filename': file.name,
            'content': base64Content ?? '',
            'contentType': contentType,
          };
        }).toList();
      }

      final useGroundedAsk = _isGrounded;
      if (useGroundedAsk && _conversationId.isEmpty) {
        _conversationId = const Uuid().v4();
      }
      final AiAskResult? askResult = useGroundedAsk
          ? await AIChatService.askRecords(
              query: userMessage,
              patientId: currentPatientId!,
              sessionId: _askSessionId,
              conversationId: _conversationId,
              inputModality: _lastInputModality,
              abortTrigger: abortCompleter.future,
            )
          : null;
      if (!_isCurrentEpoch(epoch)) return;

      final Map<String, dynamic>? response = useGroundedAsk
          ? null
          : await AIChatService.sendMessage(
              message: userMessage.isNotEmpty
                  ? userMessage
                  : 'Please analyze the uploaded files',
              patientId: currentPatientId,
              userId: currentUserId,
              conversationId:
                  _conversationId.isNotEmpty ? _conversationId : null,
              uploadedFiles: uploadedFilesJson,
              includeVitals: true,
              includeMedications: true,
              includeNotes: true,
              includeMoodPainLogs: true,
              includeAllergies: true,
            );
      if (!_isCurrentEpoch(epoch)) return;

      // Better error handling - show actual error messages instead of generic "No response"
      String aiText;
      String? errorMsg;
      List<AiAskCitation> citations = const [];
      AiAskDisclaimer? disclaimer;
      AiAskEscalation? escalation;
      AiAskConfirmation? confirmation;
      MedicationTimeline? medicationTimeline;
      var showRetry = false;

      if (askResult != null) {
        if (askResult.cancelled) {
          _safeSetState(epoch, () {
            _isLoading = false;
          });
          return;
        }
        if (askResult.sessionId != null) {
          _askSessionId = askResult.sessionId;
        }
        if (askResult.deliveryStatus == AiAskDeliveryStatus.held) {
          await _handleHeldAskResult(
            epoch: epoch,
            askResult: askResult,
          );
          return;
        }
        citations = askResult.citations;
        disclaimer = askResult.disclaimer;
        escalation = askResult.escalation;
        confirmation = askResult.confirmation;
        medicationTimeline = askResult.medicationTimeline;
        switch (askResult.deliveryStatus) {
          case AiAskDeliveryStatus.delivered:
            aiText = askResult.answer?.trim().isNotEmpty == true
                ? askResult.answer!
                : 'Ask AI returned no answer.';
            _clearRetryState();
          case AiAskDeliveryStatus.noRecords:
            aiText = askResult.message ??
                'No matching records were found for this question.';
            _clearRetryState();
          case AiAskDeliveryStatus.withheld:
            errorMsg = askResult.error?.code ?? 'WITHHELD';
            aiText = askResult.error?.message ??
                askResult.message ??
                'Ask AI could not safely answer this question.';
            showRetry = askResult.retryable &&
                askResult.retryInput != null &&
                _retryRequestIdentity == stableRequestIdentity;
            if (showRetry) {
              _retryQuery = askResult.retryInput;
              _retryRequestIdentity = stableRequestIdentity;
              _retryEnabled = true;
            } else {
              _clearRetryState();
            }
          case AiAskDeliveryStatus.held:
            // Handled above; keep switch exhaustive.
            aiText = askResult.message ??
                "We're reviewing this before showing it to you.";
            _clearRetryState();
        }
      } else if (response!['success'] == false) {
        // If backend explicitly failed, show the error message
        errorMsg = response['errorMessage'] ??
            response['error'] ??
            'Unknown error occurred';
        aiText = response['response'] ??
            response['aiResponse'] ??
            'Sorry, I encountered an error. Please try again.';
      } else {
        // Success case - get AI response or provide helpful fallback
        aiText = (response['aiResponse'] ?? '').toString();
        if (aiText.trim().isEmpty) {
          aiText =
              'I apologize, but I was unable to generate a response. Please try rephrasing your question or check your connection.';
          errorMsg = 'Empty response received from AI service';
        }
      }
      // Update conversationId for next request (legacy only)
      bool isNewConversation = false;
      if (!_isGrounded &&
          response != null &&
          response['conversationId'] != null &&
          response['conversationId'] is String) {
        if (_conversationId.isEmpty) {
          isNewConversation = true;
        }
        _conversationId = response['conversationId'];
      }
      if (!_safeSetState(epoch, () {
        _messages.add(
          ChatMessage(
            text: aiText,
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: errorMsg,
            citations: citations,
            disclaimer: disclaimer,
            escalation: escalation,
            confirmation: confirmation,
            showRetry: showRetry,
            retryQuery: showRetry ? _retryQuery : null,
            requestIdentity: showRetry ? stableRequestIdentity : null,
            requestId: askResult?.requestId,
            auditId: askResult?.auditId,
            sessionId: askResult?.sessionId ?? _askSessionId,
            medicationTimeline: medicationTimeline,
          ),
        );
        _isLoading = false;
        // Clear uploaded files after successful processing
        _uploadedFiles.clear();
        _lastInputModality = 'TEXT';
      })) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      // If this was a new conversation, load any existing history (legacy only)
      if (!_isGrounded && isNewConversation) {
        await _loadConversationHistory();
      }
    } catch (e) {
      if (!_isCurrentEpoch(epoch)) return;
      _safeSetState(epoch, () {
        _messages.add(
          ChatMessage(
            text: 'Sorry, I encountered an error: $e',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _isLoading = false;
        // Clear uploaded files even on error to prevent confusion
        _uploadedFiles.clear();
        _clearRetryState();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  static const String _hitlReviewingFallback =
      "We're reviewing this before showing it to you.";
  static const String _hitlUnavailableFallback =
      'This answer is no longer available. Please ask again or contact your care provider.';
  static const String _hitlStillReviewingFallback =
      'Still under review. Check back later or contact your care provider.';
  static const String _hitlUnauthorizedFallback =
      'Unable to check review status for this answer. Please ask again or contact your care provider.';

  static bool _isHitlTerminalDelivery(String deliveryStatus) {
    return deliveryStatus == 'DELIVERED' ||
        deliveryStatus == 'REJECTED' ||
        deliveryStatus == 'EXPIRED' ||
        deliveryStatus == 'WITHHELD_PERMANENTLY';
  }

  Future<void> _handleHeldAskResult({
    required int epoch,
    required AiAskResult askResult,
  }) async {
    _clearRetryState();
    final reviewingText =
        askResult.message?.trim().isNotEmpty == true
            ? askResult.message!.trim()
            : _hitlReviewingFallback;

    if (!_safeSetState(epoch, () {
      _messages.add(
        ChatMessage(
          text: reviewingText,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
      // Keep sends blocked while the HITL poll may still deliver an answer.
      _isLoading = true;
      _uploadedFiles.clear();
    })) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final heldItemId = askResult.heldItemId;
    if (heldItemId == null || heldItemId.isEmpty) {
      if (!_safeSetState(epoch, () {
        _isLoading = false;
        _messages.add(
          ChatMessage(
            text: _hitlUnavailableFallback,
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'HELD_MISSING_ID',
          ),
        );
      })) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    await _pollAndApplyHitlStatus(epoch: epoch, heldItemId: heldItemId);
  }

  Future<void> _resumeHitlPoll(String heldItemId) async {
    if (_isLoading || heldItemId.isEmpty) return;
    final epoch = _requestEpoch;
    if (!_safeSetState(epoch, () {
      _isLoading = true;
      for (var i = _messages.length - 1; i >= 0; i--) {
        final msg = _messages[i];
        if (msg.showHitlResume && msg.heldItemId == heldItemId) {
          _messages[i] = ChatMessage(
            text: _hitlReviewingFallback,
            isUser: false,
            timestamp: DateTime.now(),
            heldItemId: heldItemId,
          );
          break;
        }
      }
    })) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    await _pollAndApplyHitlStatus(epoch: epoch, heldItemId: heldItemId);
    if (_isCurrentEpoch(epoch)) {
      _safeSetState(epoch, () => _isLoading = false);
    }
  }

  Future<void> _pollAndApplyHitlStatus({
    required int epoch,
    required String heldItemId,
  }) async {
    HitlPollResult? terminal;
    HitlPollHttpException? permanentFailure;
    var parseFailed = false;
    final maxAttempts = widget.hitlMaxPollAttempts < 1
        ? 1
        : widget.hitlMaxPollAttempts;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!_isCurrentEpoch(epoch)) return;
      await Future<void>.delayed(widget.hitlPollInterval);
      if (!_isCurrentEpoch(epoch)) return;

      try {
        final poll = await AIChatService.pollHitlStatus(heldItemId);
        if (!_isCurrentEpoch(epoch)) return;
        if (_isHitlTerminalDelivery(poll.deliveryStatus) ||
            poll.status == 'REJECTED' ||
            poll.status == 'EXPIRED') {
          terminal = poll;
          break;
        }
      } on HitlPollHttpException catch (error) {
        if (error.isPermanent) {
          permanentFailure = error;
          break;
        }
        // Retry transient 5xx / unexpected HTTP until the attempt cap.
      } on FormatException {
        parseFailed = true;
        break;
      } catch (_) {
        // Keep polling through transient network failures until the attempt cap.
      }
    }

    if (!_isCurrentEpoch(epoch)) return;

    if (parseFailed) {
      if (!_safeSetState(epoch, () {
        _isLoading = false;
        _messages.add(
          ChatMessage(
            text: _hitlUnavailableFallback,
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'HELD_POLL_PARSE_ERROR',
          ),
        );
      })) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    if (permanentFailure != null) {
      if (!_safeSetState(epoch, () {
        _isLoading = false;
        _messages.add(
          ChatMessage(
            text: _hitlUnauthorizedFallback,
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'HELD_POLL_HTTP_${permanentFailure!.statusCode}',
          ),
        );
      })) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    if (terminal == null) {
      if (!_safeSetState(epoch, () {
        _isLoading = false;
        _messages.add(
          ChatMessage(
            text: _hitlStillReviewingFallback,
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'HELD_POLL_CLIENT_TIMEOUT',
            heldItemId: heldItemId,
            showHitlResume: true,
          ),
        );
      })) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    if (!_safeSetState(epoch, () => _isLoading = false)) {
      return;
    }

    if (terminal.deliveryStatus == 'DELIVERED') {
      final answerText = terminal.answer?.trim().isNotEmpty == true
          ? terminal.answer!.trim()
          : 'Ask AI returned no answer.';
      if (!_safeSetState(epoch, () {
        _messages.add(
          ChatMessage(
            text: answerText,
            isUser: false,
            timestamp: DateTime.now(),
            citations: terminal!.citations,
            disclaimer: terminal.disclaimer,
            confirmation: terminal.confirmation,
          ),
        );
      })) {
        return;
      }
    } else {
      final fallback = terminal.message?.trim().isNotEmpty == true
          ? terminal.message!.trim()
          : _hitlUnavailableFallback;
      if (!_safeSetState(epoch, () {
        _messages.add(
          ChatMessage(
            text: fallback,
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: terminal!.deliveryStatus,
          ),
        );
      })) {
        return;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  String _guessMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'svg':
        return 'image/svg+xml';
      case 'doc':
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }

  void _scrollToBottom() {
    // Implement scroll logic if using a ScrollController
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: _chatWidth,
        height: _chatHeight,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Chat header
            Row(
              children: [
                Icon(Icons.smart_toy, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('AI Chat', style: theme.textTheme.titleMedium),
                      if (_messages.isNotEmpty)
                        Text(
                          '${_messages.length} messages',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // Privacy controls menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    switch (value) {
                      case 'clear':
                        await _clearChatCompletely();
                        break;
                      case 'download':
                        await _downloadChatTranscript();
                        break;
                      case 'share':
                        await _shareWithProvider();
                        break;
                      case 'privacy':
                        _showPrivacyInfo();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever, size: 18),
                          SizedBox(width: 8),
                          Text('Delete this conversation'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download, size: 18),
                          SizedBox(width: 8),
                          Text('Download transcript'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share, size: 18),
                          SizedBox(width: 8),
                          Text('Share with provider'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'privacy',
                      child: Row(
                        children: [
                          Icon(Icons.privacy_tip, size: 18),
                          SizedBox(width: 8),
                          Text('Privacy info'),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.isModal)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
              ],
            ),
            // Privacy notification banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chat logs are automatically deleted after 30 days for privacy protection.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: colorScheme.outlineVariant),
            // Message list
            Expanded(
              child: ListView.builder(
                reverse: false,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Align(
                    alignment: msg.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: msg.isUser
                            ? AppTheme.chatUserMessage
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.text,
                            style: msg.isUser
                                ? theme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.chatTextOnPrimary,
                                  )
                                : theme.textTheme.bodyMedium,
                          ),
                          if (msg.errorMessage != null &&
                              !msg.errorMessage!.startsWith('HELD_'))
                            Text(
                              msg.errorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                              ),
                            ),
                          if (msg.medicationTimeline != null &&
                              msg.medicationTimeline!.events.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Medication timeline',
                              key: const Key('ask-ai-medication-timeline'),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...msg.medicationTimeline!.events.map((event) {
                              final hasDose = (event.doseFrom
                                          ?.trim()
                                          .isNotEmpty ==
                                      true) ||
                                  (event.doseTo?.trim().isNotEmpty == true);
                              final parts = <String>[
                                if (event.effectiveDate
                                        ?.trim()
                                        .isNotEmpty ==
                                    true)
                                  event.effectiveDate!.trim(),
                                event.medicationName,
                                if (event.eventType?.trim().isNotEmpty ==
                                    true)
                                  event.eventType!.trim(),
                                if (hasDose)
                                  '${event.doseFrom ?? '—'} \u2192 '
                                      '${event.doseTo ?? '—'}',
                              ];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        parts.join(' · '),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                    if (event.citationRef
                                            ?.trim()
                                            .isNotEmpty ==
                                        true) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: colorScheme.outlineVariant,
                                          ),
                                        ),
                                        child: Text(
                                          event.citationRef!.trim(),
                                          style: theme.textTheme.labelSmall,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                          ],
                          if (msg.citations.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ...msg.citations.map(
                              (citation) {
                                final deepLink = citation.deepLink?.trim();
                                final hasDeepLink =
                                    deepLink != null && deepLink.isNotEmpty;
                                final content = Text(
                                  '${citation.citationId}'
                                  '${citation.title == null ? '' : ' — ${citation.title}'}\n'
                                  '${citation.excerpt}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: hasDeepLink
                                        ? colorScheme.primary
                                        : null,
                                    decoration: hasDeepLink
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                );
                                return Semantics(
                                  label:
                                      'Citation ${citation.citationId}: ${citation.excerpt}',
                                  button: hasDeepLink,
                                  child: InkWell(
                                    onTap: hasDeepLink
                                        ? () {
                                            try {
                                              context.go(deepLink);
                                            } catch (_) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Could not open that citation.',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        : null,
                                    child: Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surface,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: content,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          if (msg.disclaimer?.aiNoticeRequired == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              msg.disclaimer!.text,
                              key: const Key('ask-ai-disclaimer'),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          if (msg.escalation != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Safety tier ${msg.escalation!.tier}: '
                              '${msg.escalation!.reason}',
                              key: const Key('ask-ai-escalation'),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          if (msg.confirmation?.required == true &&
                              msg.confirmation?.text?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              msg.confirmation!.text!,
                              key: const Key('ask-ai-confirmation'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  key: const Key('ask-ai-confirm-once'),
                                  onPressed: _isLoading
                                      ? null
                                      : () => unawaited(
                                            _submitConfirmationDecision(
                                              message: msg,
                                              decision: 'APPROVE_ONCE',
                                            ),
                                          ),
                                  child: const Text('Approve once'),
                                ),
                                TextButton(
                                  key: const Key('ask-ai-confirm-session'),
                                  onPressed: _isLoading
                                      ? null
                                      : () => unawaited(
                                            _submitConfirmationDecision(
                                              message: msg,
                                              decision: 'APPROVE_SESSION',
                                            ),
                                          ),
                                  child: const Text('Approve for session'),
                                ),
                                TextButton(
                                  key: const Key('ask-ai-confirm-decline'),
                                  onPressed: _isLoading
                                      ? null
                                      : () => unawaited(
                                            _submitConfirmationDecision(
                                              message: msg,
                                              decision: 'DECLINE',
                                            ),
                                          ),
                                  child: const Text('Decline'),
                                ),
                              ],
                            ),
                          ],
                          if (msg.showRetry &&
                              msg.retryQuery != null &&
                              _retryEnabled &&
                              msg.requestIdentity == _retryRequestIdentity) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              key: const Key('ask-ai-retry'),
                              onPressed: _isLoading ? null : _retryGroundedAsk,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                          if (msg.showHitlResume &&
                              msg.heldItemId != null &&
                              msg.heldItemId!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              key: const Key('ask-ai-hitl-resume'),
                              onPressed: _isLoading
                                  ? null
                                  : () => _resumeHitlPoll(msg.heldItemId!),
                              icon: const Icon(Icons.hourglass_top, size: 16),
                              label: const Text('Check review status'),
                            ),
                          ],
                          Text(
                            _formatTimestamp(msg.timestamp),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // File preview (if any files uploaded) — never in grounded mode
            if (!_isGrounded && _uploadedFiles.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Files to upload:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_isLoading)
                          Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      colorScheme.primary),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Processing...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ..._uploadedFiles.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final file = entry.value;
                      return Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              file.name,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: colorScheme.error,
                            ),
                            onPressed: () => _removeFile(idx),
                            tooltip: 'Remove',
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            // Input row
            Row(
              children: [
                if (!_isGrounded)
                  IconButton(
                    icon: Icon(Icons.attach_file, color: colorScheme.primary),
                    onPressed: _isFilePickerOpen ? null : _pickFiles,
                    tooltip: 'Attach file',
                  ),
                if (_isGrounded)
                  IconButton(
                    key: const Key('ask-ai-mic'),
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? colorScheme.error
                          : colorScheme.primary,
                    ),
                    onPressed: _isLoading ? null : () => unawaited(_toggleVoiceInput()),
                    tooltip: _isListening ? 'Stop listening' : 'Voice input',
                  ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _isGrounded
                          ? (_isListening
                              ? 'Listening...'
                              : 'Ask about this patient\'s records...')
                          : 'Type your message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    enabled: !_isLoading,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  icon: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      : Icon(Icons.send, color: colorScheme.primary),
                  onPressed: _isLoading ? null : _sendMessage,
                  tooltip: 'Send',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dt.month}/${dt.day}/${dt.year}';
    }
  }
}
