import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ai_chat_service.dart';
import '../config/theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// Message model for chat
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? errorMessage;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.errorMessage,
  });
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
class AIChat extends StatefulWidget {
  final String role;
  final String? healthDataContext;
  final bool isModal;
  final int? patientId;
  final int? userId;

  const AIChat({
    super.key,
    required this.role,
    this.healthDataContext,
    this.isModal = false,
    this.patientId,
    this.userId,
  });

  @override
  State<AIChat> createState() => _AIChatState();
}

class _AIChatState extends State<AIChat> with SingleTickerProviderStateMixin {
  String _conversationId = "";
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<UploadedFile> _uploadedFiles = [];
  bool _isLoading = false;
  bool _isLoadingHistory = false;
  bool _isFilePickerOpen = false;
  final double _chatWidth = 320.0;
  final double _chatHeight = 500.0;
  late AnimationController _animationController;
  
  // Inactivity timer for 15-minute auto-clear
  Timer? _inactivityTimer;
  DateTime? _lastActivity;
  
  // Flag to track if user manually cleared the chat
  bool _manuallyCleared = false;

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
  }

  /// Check if chat was manually cleared and load history if not
  Future<void> _checkAndLoadHistory() async {
    if (widget.userId == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final clearedKey = 'chat_cleared_${widget.userId}';
      final wasCleared = prefs.getBool(clearedKey) ?? false;
      
      if (!wasCleared) {
        await _loadConversationHistory();
      } else {
        // Chat was manually cleared, start with empty chat
        setState(() {
          _manuallyCleared = true;
        });
      }
    } catch (e) {
      // If there's an error, just load history normally
      await _loadConversationHistory();
    }
  }

  @override
  void dispose() {
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
    if (mounted) {
      setState(() {
        _messages.clear();
        _conversationId = "";
        _messages.add(ChatMessage(
          text: '⏰ Chat cleared due to 15 minutes of inactivity',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    }
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
      
      // Clear all messages and start fresh
      setState(() {
        _messages.clear();
        _conversationId = "";
        _isLoadingHistory = false;
        _manuallyCleared = true;
      });
      
      // Store the cleared state persistently
      if (widget.userId != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final clearedKey = 'chat_cleared_${widget.userId}';
          await prefs.setBool(clearedKey, true);
        } catch (e) {
          // Failed to save cleared state, continue anyway
        }
      }
      
      // Clear the conversation from the backend if it exists
      if (conversationToClear.isNotEmpty) {
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

  /// Load conversation history from the backend
  Future<void> _loadConversationHistory() async {
    if (widget.userId == null) {
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
    
    try {
      final response = await AIChatService.getConversationHistory(
        userId: widget.userId.toString(),
        conversationId: _conversationId.isNotEmpty ? _conversationId : null,
        limit: 20,
      );
      
      if (mounted) {
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
                timestamp: DateTime.tryParse(messageData['createdAt'] ?? '') ?? DateTime.now(),
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
      }
    } catch (e) {
      if (mounted) {
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
  }

  Future<void> _pickFiles() async {
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
      setState(() => _isFilePickerOpen = false);
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

  void _sendMessage() async {
    // Allow sending if there's a message OR uploaded files
    if (_controller.text.trim().isEmpty && _uploadedFiles.isEmpty) return;
    final userMessage = _controller.text.trim();
    _controller.clear();
    
    // Reset inactivity timer on user activity
    _resetInactivityTimer();
    
    setState(() {
      // Add user message (either text or file upload indication)
      String displayMessage = userMessage.isNotEmpty 
          ? userMessage 
          : '📎 Uploaded ${_uploadedFiles.length} file${_uploadedFiles.length > 1 ? 's' : ''}';
      
      _messages.add(
        ChatMessage(text: displayMessage, isUser: true, timestamp: DateTime.now()),
      );
      
      // Add file processing message if files are uploaded
      if (_uploadedFiles.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: '📎 Analyzing ${_uploadedFiles.length} uploaded file${_uploadedFiles.length > 1 ? 's' : ''}...',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      }
      
      _isLoading = true;
      _manuallyCleared = false; // Reset manual clear flag when user starts new conversation
    });
    
    // Clear the persistent cleared state when starting new conversation
    if (widget.userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final clearedKey = 'chat_cleared_${widget.userId}';
        await prefs.setBool(clearedKey, false);
      } catch (e) {
        // Failed to clear persistent state, continue anyway
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    try {
      final userProvider = mounted
          ? Provider.of<UserProvider>(context, listen: false)
          : null;

      // Better userId validation - avoid defaulting to 1
      final currentUserId = widget.userId ?? userProvider?.user?.id;
      if (currentUserId == null) {
        setState(() {
          _isLoading = false;
          _messages.add(ChatMessage(
            text: 'Authentication error: Please log in to use the chat feature.',
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: 'User ID not found',
          ));
        });
        return;
      }

      // Only use patientId if explicitly provided, never default to user ID
      final currentPatientId = widget.patientId;

      // Prepare uploadedFiles for API if any
      List<Map<String, dynamic>>? uploadedFilesJson;
      if (_uploadedFiles.isNotEmpty) {
        uploadedFilesJson = _uploadedFiles.map((file) {
          List<int>? fileBytes = file.bytes;
          if (fileBytes == null && file.path != null) {
            try {
              fileBytes = File(file.path!).readAsBytesSync();
            } catch (_) {}
          }
          String? base64Content = fileBytes != null
              ? base64Encode(fileBytes)
              : null;
          String contentType = _guessMimeType(file.name);
          return {
            'filename': file.name,
            'content': base64Content ?? '',
            'contentType': contentType,
          };
        }).toList();
      }

      // Only these fields are dynamic for the request
      final response = await AIChatService.sendMessage(
        message: userMessage.isNotEmpty ? userMessage : 'Please analyze the uploaded files',
        patientId: currentPatientId, // Pass only if explicitly provided
        userId: currentUserId,
        conversationId: _conversationId.isNotEmpty ? _conversationId : null,
        uploadedFiles: uploadedFilesJson,
        // Include all medical context data
        includeVitals: true,
        includeMedications: true,
        includeNotes: true,
        includeMoodPainLogs: true,
        includeAllergies: true,
      );
      // Better error handling - show actual error messages instead of generic "No response"
      String aiText;
      String? errorMsg;

      if (response['success'] == false) {
        // If backend explicitly failed, show the error message
        errorMsg = response['errorMessage'] ?? response['error'] ?? 'Unknown error occurred';
        aiText = response['response'] ?? response['aiResponse'] ?? 'Sorry, I encountered an error. Please try again.';
      } else {
        // Success case - get AI response or provide helpful fallback
        aiText = (response['aiResponse'] ?? '').toString();
        if (aiText.trim().isEmpty) {
          aiText = 'I apologize, but I was unable to generate a response. Please try rephrasing your question or check your connection.';
          errorMsg = 'Empty response received from AI service';
        }
      }
      // Update conversationId for next request
      bool isNewConversation = false;
      if (response['conversationId'] != null &&
          response['conversationId'] is String) {
        if (_conversationId.isEmpty) {
          isNewConversation = true;
        }
        _conversationId = response['conversationId'];
      }
      setState(() {
        _messages.add(
          ChatMessage(
            text: aiText,
            isUser: false,
            timestamp: DateTime.now(),
            errorMessage: errorMsg,
          ),
        );
        _isLoading = false;
        // Clear uploaded files after successful processing
        _uploadedFiles.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      
      // If this was a new conversation, load any existing history
      if (isNewConversation) {
        await _loadConversationHistory();
      }
    } catch (e) {
      setState(() {
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
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
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
                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
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
                          if (msg.errorMessage != null)
                            Text(
                              msg.errorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                              ),
                            ),
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
            // File preview (if any files uploaded)
            if (_uploadedFiles.isNotEmpty)
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
                                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
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
                IconButton(
                  icon: Icon(Icons.attach_file, color: colorScheme.primary),
                  onPressed: _isFilePickerOpen ? null : _pickFiles,
                  tooltip: 'Attach file',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
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
