import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/features/analytics/web_utils.dart'
    if (dart.library.html) 'package:care_connect_app/features/analytics/web_utils_web.dart'
    as download_utils;
import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../providers/user_provider.dart';
import '../model/chat_pending_queue_manager.dart';
import '../model/message_dto.dart';

class ChatRoomScreen extends StatefulWidget {
  final int peerUserId;
  final String peerName;
  final Future<List<dynamic>> Function(
      {required int user1, required int user2})? conversationLoader;
  final Future<void> Function({
    required int senderId,
    required int receiverId,
    required String content,
  })? messageSender;
  final bool enableAutoSync;

  const ChatRoomScreen({
    super.key,
    required this.peerUserId,
    required this.peerName,
    this.conversationLoader,
    this.messageSender,
    this.enableAutoSync = true,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

enum _WsStatus { connecting, connected, disconnected }

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatPendingQueueManager _pendingQueueManager =
      ChatPendingQueueManager();

  int? _currentUserId;
  List<MessageDto> messages = [];
  bool isLoading = true;
  bool _initialLoading = true;
  bool _initialized = false;

  // Messaging permission
  bool _messagingAllowed = true;
  String? _messagingBlockedReason;

  // Video call permission
  bool _videoCallAllowed = true;
  String? _videoCallBlockedReason;

  // Typing and receipts
  bool _peerTyping = false;
  bool _isTyping = false;
  Timer? _typingStopTimer;
  Timer? _peerTypingTimer;
  final Set<int> _readMessageIds = <int>{};
  final Set<int> _deliveredMessageIds = <int>{};
  final Set<int> _receiptSentMessageIds = <int>{};

  // WebSocket
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  _WsStatus _wsStatus = _WsStatus.disconnected;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // Fallback polling
  Timer? _pollingTimer;
  Timer? _permissionRefreshTimer;

  // Failed-send retry
  String? _failedMessage;
  final List<MessageDto> _pendingMessages = <MessageDto>[];
  final Set<int> _pendingInFlightIds = <int>{};

  // Attachment state
  bool _isUploading = false;
  final _audioRecorder = AudioRecorder();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in')),
        );
        return;
      }
      _currentUserId = user.id;
      _restorePendingMessagesFromCache();
      _restorePendingMessagesFromDisk();
      if (widget.enableAutoSync) {
        fetchConversation();
        _refreshMessagingPermission();
        _refreshVideoCallPermission();
        _startPolling();
        _connectWebSocket();
        _startPermissionRefresh();
      } else {
        isLoading = false;
        _initialLoading = false;
      }
      _controller.addListener(_handleComposerChanged);
      _initialized = true;
      unawaited(
        Telemetry.event('feature_use', {'feature': 'chat_room'}),
      );
    }
  }

  String? _conversationCacheKey() {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return null;
    return _pendingQueueManager.conversationKey(
      currentUserId: currentUserId,
      peerUserId: widget.peerUserId,
    );
  }

  void _persistPendingMessagesToCache() {
    final key = _conversationCacheKey();
    if (key == null) return;
    _pendingQueueManager.persistToCache(key, _pendingMessages);
  }

  Future<void> _persistPendingMessagesToDisk() async {
    final key = _conversationCacheKey();
    if (key == null) return;
    await _pendingQueueManager.persistToDisk(key, _pendingMessages);
  }

  Future<void> _restorePendingMessagesFromDisk() async {
    final key = _conversationCacheKey();
    if (key == null) return;
    final restored = await _pendingQueueManager.restoreFromDisk(key);
    if (restored.isEmpty) return;

    if (!mounted) return;
    setState(() {
      final existingPendingIds = _pendingMessages.map((m) => m.id).toSet();
      for (final pending in restored) {
        if (!existingPendingIds.contains(pending.id)) {
          _pendingMessages.add(pending);
          existingPendingIds.add(pending.id);
        }
      }

      final visibleIds = messages.map((m) => m.id).toSet();
      for (final pending in _pendingMessages) {
        if (!visibleIds.contains(pending.id)) {
          messages.add(pending);
        }
      }
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });

    _persistPendingMessagesToCache();
    _retryPendingMessages();
  }

  void _restorePendingMessagesFromCache() {
    final key = _conversationCacheKey();
    if (key == null) return;
    final cached = _pendingQueueManager.restoreFromCache(key);
    if (cached.isEmpty) return;

    _pendingMessages
      ..clear()
      ..addAll(cached);

    final existingIds = messages.map((m) => m.id).toSet();
    for (final pending in cached) {
      if (!existingIds.contains(pending.id)) {
        messages.add(pending);
      }
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  // ── WebSocket ──────────────────────────────────────────────────────────────

  Future<void> _connectWebSocket() async {
    if (_wsStatus == _WsStatus.connecting) return;
    setState(() => _wsStatus = _WsStatus.connecting);

    try {
      final token = await AuthTokenManager.getJwtToken();
      if (token == null || !mounted) return;

      final uri = Uri.parse(getChatWebSocketUrl());
      _wsChannel = WebSocketChannel.connect(uri);

      _wsSubscription = _wsChannel!.stream.listen(
        _onWsMessage,
        onError: _onWsError,
        onDone: _onWsDone,
        cancelOnError: false,
      );

      _wsSend({
        'type': 'authenticate',
        'userId': _currentUserId.toString(),
      });

      if (mounted) {
        setState(() => _wsStatus = _WsStatus.connected);
        _markVisibleIncomingMessagesRead(messages);
      }
      _reconnectAttempts = 0;
      _retryPendingMessages();
    } catch (e) {
      debugPrint('ChatWS connect error: $e');
      if (mounted) setState(() => _wsStatus = _WsStatus.disconnected);
      _startPolling();
      _scheduleReconnect();
    }
  }

  void _wsSend(Map<String, dynamic> payload) {
    try {
      _wsChannel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _onWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'message-received') {
        final senderIdRaw = data['senderId'];
        final senderId = senderIdRaw is int
            ? senderIdRaw
            : int.tryParse(senderIdRaw?.toString() ?? '');
        final content = data['content'] as String? ?? '';
        final tsStr = data['timestamp'] as String?;
        final ts = tsStr != null
            ? DateTime.tryParse(tsStr) ?? DateTime.now()
            : DateTime.now();
        final msgId = (data['messageId'] as num?)?.toInt() ?? 0;

        if (senderId == null) return;

        final msg = MessageDto(
          id: msgId,
          senderId: senderId,
          receiverId: _currentUserId ?? 0,
          content: content,
          timestamp: ts,
        );

        if (!messages.any((m) => m.id == msgId)) {
          if (mounted) {
            setState(() => messages.add(msg));
            _scrollToBottom();
          }
        }
        _sendReadReceipt(msgId);
        fetchConversation(silent: true);
      } else if (type == 'message-sent') {
        final messageId = (data['messageId'] as num?)?.toInt();
        if (messageId != null && data['delivered'] == true && mounted) {
          setState(() => _deliveredMessageIds.add(messageId));
        }
        fetchConversation(silent: true);
      } else if (type == 'message-read') {
        final messageId = (data['messageId'] as num?)?.toInt();
        if (messageId != null && mounted) {
          setState(() => _readMessageIds.add(messageId));
        }
      } else if (type == 'user-typing') {
        final senderIdRaw = data['senderId'];
        final senderId = senderIdRaw is int
            ? senderIdRaw
            : int.tryParse(senderIdRaw?.toString() ?? '');
        if (senderId == widget.peerUserId && mounted) {
          setState(() => _peerTyping = data['isTyping'] == true);
          _peerTypingTimer?.cancel();
          if (data['isTyping'] == true) {
            _peerTypingTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() => _peerTyping = false);
              }
            });
          }
        }
      } else if (type == 'error') {
        debugPrint('ChatWS error: ${data['message']}');
      }
    } catch (e) {
      debugPrint('ChatWS parse error: $e');
    }
  }

  void _onWsError(Object error) {
    if (mounted) setState(() => _wsStatus = _WsStatus.disconnected);
    _startPolling();
    _scheduleReconnect();
  }

  void _onWsDone() {
    if (mounted) setState(() => _wsStatus = _WsStatus.disconnected);
    _startPolling();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    final delay = Duration(seconds: 2 * (_reconnectAttempts + 1));
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () {
      if (mounted && _wsStatus == _WsStatus.disconnected) _connectWebSocket();
    });
  }

  void _startPolling() {
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_currentUserId != null && mounted) {
        fetchConversation(silent: true);
        _retryPendingMessages();
      }
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _startPermissionRefresh() {
    _permissionRefreshTimer?.cancel();
    _permissionRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _currentUserId != null) {
        _refreshMessagingPermission();
      }
    });
  }

  // ── Conversation fetch ─────────────────────────────────────────────────────

  Future<void> fetchConversation({bool silent = false}) async {
    if (_currentUserId == null) return;
    if (!silent && _initialLoading) setState(() => isLoading = true);

    try {
      final data = await (widget.conversationLoader?.call(
            user1: _currentUserId!,
            user2: widget.peerUserId,
          ) ??
          ApiService.getConversation(
            user1: _currentUserId!,
            user2: widget.peerUserId,
          ));
      final updated = data.map((json) => MessageDto.fromJson(json)).toList();
      _reconcilePendingWithServerMessages(updated);
      final merged = <MessageDto>[...updated, ..._pendingMessages]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (!listEquals(messages, updated)) {
        if (mounted) {
          setState(() {
            messages = merged;
            isLoading = false;
            _initialLoading = false;
          });
          _markVisibleIncomingMessagesRead(merged);
          _scrollToBottom();
        }
      } else if (_initialLoading) {
        if (mounted) {
          setState(() {
            isLoading = false;
            _initialLoading = false;
          });
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load conversation: $e')),
        );
      }
      if (mounted) {
        setState(() {
          isLoading = false;
          _initialLoading = false;
        });
      }
    }
  }

  // ── Send text ──────────────────────────────────────────────────────────────

  Future<void> sendMessage({String? retryContent}) async {
    final content = retryContent ?? _controller.text.trim();
    if (content.isEmpty || _currentUserId == null || !_messagingAllowed) return;

    if (retryContent == null) {
      _controller.clear();
    }
    if (mounted) {
      setState(() {
        _failedMessage = null;
      });
    }
    _sendTyping(false);

    final pendingMessage = MessageDto(
      id: -DateTime.now().millisecondsSinceEpoch,
      senderId: _currentUserId!,
      receiverId: widget.peerUserId,
      content: content,
      timestamp: DateTime.now(),
    );

    if (mounted) {
      setState(() {
        messages.add(pendingMessage);
        _pendingMessages.add(pendingMessage);
      });
      _scrollToBottom();
    }
    _persistPendingMessagesToCache();
    await _persistPendingMessagesToDisk();

    await _trySendPendingMessage(pendingMessage);
  }

  Future<void> _trySendPendingMessage(MessageDto pendingMessage) async {
    if (_currentUserId == null ||
        _pendingInFlightIds.contains(pendingMessage.id)) {
      return;
    }

    _pendingInFlightIds.add(pendingMessage.id);

    bool sent = false;
    bool queuedOffline = false;
    try {
      if (widget.messageSender != null) {
        await widget.messageSender!.call(
          senderId: _currentUserId!,
          receiverId: widget.peerUserId,
          content: pendingMessage.content,
        );
        sent = true;
      } else {
        final response = await ApiService.sendMessage(
          senderId: _currentUserId!,
          receiverId: widget.peerUserId,
          content: pendingMessage.content,
        );
        queuedOffline = response.headers['x-offline-queued'] == 'true';
        sent = !queuedOffline &&
            response.statusCode >= 200 &&
            response.statusCode < 300;
      }
    } catch (_) {}

    if (!sent) {
      if (queuedOffline) {
        _markPendingMessageAsQueuedOffline(pendingMessage.id);
      }
      _pendingInFlightIds.remove(pendingMessage.id);
      _persistPendingMessagesToCache();
      await _persistPendingMessagesToDisk();
      if (queuedOffline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message queued for sync when internet is restored'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _pendingMessages.removeWhere((m) => m.id == pendingMessage.id);
        messages.removeWhere((m) => m.id == pendingMessage.id);
      });
    }
    _persistPendingMessagesToCache();
    await _persistPendingMessagesToDisk();
    _pendingInFlightIds.remove(pendingMessage.id);

    await fetchConversation(silent: true);
  }

  Future<void> _retryPendingMessages() async {
    if (_pendingMessages.isEmpty) return;

    final queueSnapshot = List<MessageDto>.from(_pendingMessages);
    for (final pending in queueSnapshot) {
      if (pending.queuedOffline) {
        continue;
      }
      await _trySendPendingMessage(pending);
    }
  }

  void _markPendingMessageAsQueuedOffline(int pendingId) {
    for (var i = 0; i < _pendingMessages.length; i++) {
      final pending = _pendingMessages[i];
      if (pending.id != pendingId || pending.queuedOffline) {
        continue;
      }

      final updated = MessageDto(
        id: pending.id,
        senderId: pending.senderId,
        receiverId: pending.receiverId,
        content: pending.content,
        timestamp: pending.timestamp,
        queuedOffline: true,
        attachmentId: pending.attachmentId,
        attachmentName: pending.attachmentName,
        attachmentContentType: pending.attachmentContentType,
        attachmentSize: pending.attachmentSize,
      );
      _pendingMessages[i] = updated;

      final visibleIndex = messages.indexWhere((m) => m.id == pendingId);
      if (visibleIndex != -1) {
        messages[visibleIndex] = updated;
      }
      break;
    }
  }

  void _reconcilePendingWithServerMessages(List<MessageDto> serverMessages) async {
    if (_pendingMessages.isEmpty) {
      return;
    }

    final remainingServer = List<MessageDto>.from(serverMessages);
    final pendingToRemove = <int>{};

    for (final pending in _pendingMessages) {
      final matchIndex = remainingServer.indexWhere((serverMsg) {
        if (serverMsg.senderId != pending.senderId ||
            serverMsg.receiverId != pending.receiverId ||
            serverMsg.content != pending.content) {
          return false;
        }

        return !serverMsg.timestamp
            .isBefore(pending.timestamp.subtract(const Duration(seconds: 5)));
      });

      if (matchIndex != -1) {
        pendingToRemove.add(pending.id);
        remainingServer.removeAt(matchIndex);
      }
    }

    if (pendingToRemove.isEmpty) {
      return;
    }

    _pendingMessages.removeWhere((m) => pendingToRemove.contains(m.id));
    messages.removeWhere((m) => pendingToRemove.contains(m.id));
    _persistPendingMessagesToCache();
    await _persistPendingMessagesToDisk();
  }

  // ── Attachments ────────────────────────────────────────────────────────────

  void _showAttachmentSheet() {
    if (!_messagingAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messagingBlockedReason ??
                'Messaging is disabled for this contact.',
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Camera / Photo Library'),
                subtitle: const Text('Take a photo or choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.red,
                  child: Icon(Icons.mic, color: Colors.white),
                ),
                title: const Text('Audio Recording'),
                subtitle: const Text('Record a voice message'),
                onTap: () {
                  Navigator.pop(context);
                  _startAudioRecording();
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.attach_file, color: Colors.white),
                ),
                title: const Text('File'),
                subtitle: const Text('PDF, document, or any file'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    if (!kIsWeb) {
      final status = await Permission.photos.request();
      if (!mounted) return;
      // On newer Android/iOS, photos permission or camera permission
      if (status.isPermanentlyDenied) {
        _showPermissionDenied('Photo library');
        return;
      }
    }

    final picker = ImagePicker();
    final action = await showDialog<ImageSource>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Choose source'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const ListTile(
              leading: Icon(Icons.camera_alt),
              title: Text('Camera'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Photo Library'),
            ),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;

    if (action == ImageSource.camera) {
      final camStatus = await Permission.camera.request();
      if (camStatus.isPermanentlyDenied) {
        _showPermissionDenied('Camera');
        return;
      }
    }

    final XFile? picked =
        await picker.pickImage(source: action, imageQuality: 85);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    final mime = lookupMimeType(picked.name) ?? 'image/jpeg';
    await _uploadAttachment(
        bytes: bytes, fileName: picked.name, mimeType: mime);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final mime = lookupMimeType(file.name) ?? 'application/octet-stream';
    await _uploadAttachment(bytes: bytes, fileName: file.name, mimeType: mime);
  }

  Future<void> _startAudioRecording() async {
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied) {
      _showPermissionDenied('Microphone');
      return;
    }
    if (status.isDenied) return;

    if (!mounted) return;

    // Show recording dialog — "Send" pops with true, "Cancel" pops with false
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RecordingDialog(recorder: _audioRecorder),
    );

    if (result != true) return; // cancelled

    // Stop recorder and get the file path
    final path = await _audioRecorder.stop();
    if (path == null || !mounted) return;

    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final mime = 'audio/m4a';
    final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _uploadAttachment(bytes: bytes, fileName: name, mimeType: mime);

    // Clean up temp file
    try {
      file.deleteSync();
    } catch (_) {}
  }

  Future<void> _uploadAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (_currentUserId == null) return;

    setState(() => _isUploading = true);

    try {
      final token = await AuthTokenManager.getJwtToken();
      if (token == null) throw Exception('Not authenticated');

      final uri =
          Uri.parse('${getBackendBaseUrl()}/v1/api/messages/send-attachment');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['senderId'] = _currentUserId.toString();
      request.fields['receiverId'] = widget.peerUserId.toString();
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ));

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        await fetchConversation(silent: true);
      } else if (response.statusCode == 403) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Messaging is not enabled for this contact.')),
          );
        }
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send attachment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _downloadAndOpenAttachment(MessageDto msg) async {
    if (msg.attachmentId == null) return;
    try {
      final token = await AuthTokenManager.getJwtToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please sign in again to download attachments.')),
          );
        }
        return;
      }

      final uri = Uri.parse(
        '${getBackendBaseUrl()}/v1/api/files/${msg.attachmentId}/download',
      );
      final response =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode != 200) {
        if (mounted) {
          final status = response.statusCode;
          final message = switch (status) {
            401 => 'Session expired. Please sign in again.',
            403 => 'You do not have permission to download this attachment.',
            404 => 'Attachment not found.',
            _ => 'Download failed (HTTP $status).',
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
        return;
      }

      if (!mounted) return;

      if (kIsWeb) {
        download_utils.downloadFile(
          msg.attachmentName ?? 'attachment',
          response.bodyBytes,
          msg.attachmentContentType,
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${msg.attachmentName ?? 'attachment'}');
      await file.writeAsBytes(response.bodyBytes);

      final result = await OpenFilex.open(file.path);
      if (!mounted) return;

      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isNotEmpty
                  ? 'Could not open attachment: ${result.message}'
                  : 'Could not open attachment.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open attachment: $e')),
        );
      }
    }
  }

  void _showPermissionDenied(String feature) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature permission denied. Enable it in Settings.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
  }

  // ── Video call ─────────────────────────────────────────────────────────────

  Future<void> _refreshMessagingPermission() async {
    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser == null || _currentUserId == null) return;

    bool allowed = _messagingAllowed;

    try {
      if (currentUser.role == 'PATIENT') {
        final links =
            await ApiService.getPatientLinkedCaregiverLinks(_currentUserId!);
        if (links.isEmpty) {
          debugPrint(
            'Messaging permission refresh inconclusive (no caregiver links returned); keeping current state.',
          );
          return;
        }
        Map<String, dynamic>? matching;
        for (final item in links) {
          final caregiverRaw = item['caregiverUserId'];
          final caregiverUserId = caregiverRaw is int
              ? caregiverRaw
              : int.tryParse('$caregiverRaw');
          if (caregiverUserId == widget.peerUserId) {
            matching = item;
            break;
          }
        }
        if (matching == null) {
          debugPrint(
            'Messaging permission refresh inconclusive (no matching caregiver link); keeping current state.',
          );
          return;
        } else {
          final enabledRaw = matching['patientMessagingEnabled'];
          allowed = enabledRaw is bool
              ? enabledRaw
              : '$enabledRaw'.toLowerCase() != 'false';
        }
      } else if (currentUser.role == 'CAREGIVER') {
        final caregiverId = currentUser.caregiverId;
        if (caregiverId == null) {
          allowed = false;
        } else {
          final response = await ApiService.getCaregiverPatients(caregiverId);
          if (response.statusCode != 200) {
            throw Exception(
              'Failed caregiver-patient link lookup: ${response.statusCode}',
            );
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! List) {
            throw Exception('Invalid caregiver-patient response payload');
          }
          if (decoded.isEmpty) {
            debugPrint(
              'Messaging permission refresh inconclusive (no patient links returned); keeping current state.',
            );
            return;
          }

          Map<String, dynamic>? matchingLink;
          for (final item in decoded) {
            if (item is! Map) continue;
            final row = Map<String, dynamic>.from(item);
            final link = row['link'];
            if (link is! Map) continue;
            final linkMap = Map<String, dynamic>.from(link);
            final patientUserIdRaw = linkMap['patientUserId'];
            final patientUserId = patientUserIdRaw is int
                ? patientUserIdRaw
                : int.tryParse('$patientUserIdRaw');
            if (patientUserId == widget.peerUserId) {
              matchingLink = linkMap;
              break;
            }
          }

          if (matchingLink == null) {
            debugPrint(
              'Messaging permission refresh inconclusive (no matching patient link); keeping current state.',
            );
            return;
          } else {
            final enabledRaw = matchingLink['patientMessagingEnabled'];
            allowed = enabledRaw is bool
                ? enabledRaw
                : '$enabledRaw'.toLowerCase() != 'false';
          }
        }
      }
    } catch (e) {
      debugPrint(
        'Messaging permission refresh failed. Keeping current state: $e',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _messagingAllowed = allowed;
      _messagingBlockedReason = allowed
          ? null
          : (currentUser.role == 'PATIENT'
              ? 'Messaging is disabled by your caregiver for this conversation.'
              : 'Messaging is disabled for this patient link.');
    });
  }

  void _handleComposerChanged() {
    if (!_messagingAllowed || _currentUserId == null) return;
    _sendTyping(_controller.text.trim().isNotEmpty);
  }

  void _sendTyping(bool isTyping) {
    if (_wsStatus != _WsStatus.connected || _wsChannel == null) return;

    if (_isTyping == isTyping) {
      if (isTyping) {
        _typingStopTimer?.cancel();
        _typingStopTimer = Timer(
          const Duration(seconds: 2),
          () => _sendTyping(false),
        );
      }
      return;
    }

    _isTyping = isTyping;
    _wsSend({
      'type': 'typing',
      'recipientId': widget.peerUserId.toString(),
      'isTyping': isTyping,
    });

    _typingStopTimer?.cancel();
    if (isTyping) {
      _typingStopTimer = Timer(
        const Duration(seconds: 2),
        () => _sendTyping(false),
      );
    }
  }

  void _markVisibleIncomingMessagesRead(List<MessageDto> source) {
    for (final msg in source) {
      if (msg.senderId == widget.peerUserId &&
          msg.receiverId == _currentUserId) {
        _sendReadReceipt(msg.id);
      }
    }
  }

  void _sendReadReceipt(int messageId) {
    if (messageId <= 0 || _receiptSentMessageIds.contains(messageId)) return;
    if (_wsStatus != _WsStatus.connected || _wsChannel == null) return;
    _receiptSentMessageIds.add(messageId);
    _wsSend({
      'type': 'read-receipt',
      'messageId': messageId.toString(),
    });
  }

  Future<void> _refreshVideoCallPermission() async {
    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser == null || _currentUserId == null) return;
    final canCall = await ApiService.canInitiateVideoCall(
      currentUserId: _currentUserId!,
      currentUserRole: currentUser.role,
      caregiverId: currentUser.caregiverId,
      targetUserId: widget.peerUserId,
    );
    if (!mounted) return;
    setState(() {
      _videoCallAllowed = canCall;
      _videoCallBlockedReason = canCall
          ? null
          : (currentUser.role == 'PATIENT'
              ? 'Video calling is disabled by your caregiver or no active link exists.'
              : 'You can only call assigned patients/caregivers in your care circle.');
    });
  }

  Future<void> _handleVideoCallTap() async {
    final currentUser = Provider.of<UserProvider>(context, listen: false).user;
    if (currentUser == null || _currentUserId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }
    await _refreshVideoCallPermission();
    if (!mounted) return;
    if (!_videoCallAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(_videoCallBlockedReason ?? 'Video calling unavailable.')),
      );
      return;
    }
    final callId = 'chime_call_${DateTime.now().millisecondsSinceEpoch}';
    context.push(
      '/video-call-chime'
      '?userId=$_currentUserId'
      '&recipientId=${widget.peerUserId}'
      '&userRole=${Uri.encodeComponent(currentUser.role)}'
      '&userName=${Uri.encodeComponent(currentUser.name ?? 'User')}'
      '&recipientName=${Uri.encodeComponent(widget.peerName)}'
      '&initiator=true&video=true&audio=true&callId=$callId',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _pollingTimer?.cancel();
    _permissionRefreshTimer?.cancel();
    _typingStopTimer?.cancel();
    _peerTypingTimer?.cancel();
    _sendTyping(false);
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _audioRecorder.dispose();
    _controller.removeListener(_handleComposerChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Message bubble ─────────────────────────────────────────────────────────

  // Bubble palette — meets WCAG AA (≥4.5:1) against their own background
  static const Color _bubbleMeBg =
      Color(0xFF1565C0); // Blue 800  — white text: ~5.9:1
  static const Color _bubblePeerBg =
      Color(0xFF37474F); // BlueGrey 800 — white text: ~7.5:1
  static const Color _bubbleMeText = Colors.white;
  static const Color _bubblePeerText = Colors.white;
  static const Color _bubbleSubText =
      Color(0xCCFFFFFF); // white 80% — ~4.7:1 on above bg

  Widget _buildMessageBubble(MessageDto msg) {
    final isMe = msg.senderId == _currentUserId;
    final bg = isMe ? _bubbleMeBg : _bubblePeerBg;
    final textColor = isMe ? _bubbleMeText : _bubblePeerText;

    final timeStr = '${msg.timestamp.toLocal().hour.toString().padLeft(2, '0')}'
        ':${msg.timestamp.toLocal().minute.toString().padLeft(2, '0')}';
    final receiptLabel = isMe
        ? (msg.id < 0
            ? 'Pending'
            : _readMessageIds.contains(msg.id)
                ? 'Read'
                : (_deliveredMessageIds.contains(msg.id)
                    ? 'Delivered'
                    : 'Sent'))
        : null;
    final receiptIcon = msg.id < 0
        ? Icons.schedule
        : _readMessageIds.contains(msg.id)
            ? Icons.done_all
            : (_deliveredMessageIds.contains(msg.id)
                ? Icons.done_all
                : Icons.done);

    Widget bodyContent;
    if (msg.hasAttachment) {
      bodyContent = _buildAttachmentBubble(msg, textColor);
    } else {
      bodyContent = Text(
        msg.content,
        style: TextStyle(color: textColor, fontSize: 15),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            bodyContent,
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: const TextStyle(fontSize: 10, color: _bubbleSubText),
            ),
            if (receiptLabel != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    receiptIcon,
                    size: 12,
                    color: msg.id < 0
                        ? _bubbleSubText
                        : _readMessageIds.contains(msg.id)
                            ? Colors.lightBlueAccent
                            : _bubbleSubText,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    receiptLabel,
                    style: const TextStyle(fontSize: 10, color: _bubbleSubText),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentBubble(MessageDto msg, Color textColor) {
    final sizeLabel = _formatFileSize(msg.attachmentSize);

    if (msg.isImage) {
      return GestureDetector(
        onTap: () => _downloadAndOpenAttachment(msg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image, size: 18, color: textColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    msg.attachmentName ?? 'Image',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (sizeLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sizeLabel,
                  style: const TextStyle(fontSize: 11, color: _bubbleSubText)),
            ],
          ],
        ),
      );
    } else if (msg.isAudio) {
      return GestureDetector(
        onTap: () => _downloadAndOpenAttachment(msg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_filled, size: 30, color: textColor),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.attachmentName ?? 'Voice message',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeLabel.isNotEmpty)
                    Text(sizeLabel,
                        style: const TextStyle(
                            fontSize: 11, color: _bubbleSubText)),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: () => _downloadAndOpenAttachment(msg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, size: 30, color: textColor),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.attachmentName ?? 'File',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeLabel.isNotEmpty)
                    Text(sizeLabel,
                        style: const TextStyle(
                            fontSize: 11, color: _bubbleSubText)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.download, size: 18, color: textColor),
          ],
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Start video call',
            onPressed: _handleVideoCallTap,
          ),
        ],
      ),
      body: Column(
        children: [
          // Reconnecting banner
          if (_wsStatus == _WsStatus.disconnected)
            Material(
              color: Colors.orange.shade700,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Reconnecting...',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: _connectWebSocket,
                      child: const Text('Retry',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),

          // Failed send banner
          if (_failedMessage != null)
            Material(
              color: Colors.red.shade700,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Message failed to send.',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () =>
                          sendMessage(retryContent: _failedMessage),
                      child: const Text('Retry',
                          style: TextStyle(color: Colors.white)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 16),
                      onPressed: () => setState(() => _failedMessage = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),

          // Upload progress
          if (_isUploading) const LinearProgressIndicator(),

          if (_peerTyping)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.peerName} is typing...',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),

          // Message list
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageBubble(messages[index]),
                  ),
          ),

          const Divider(height: 1),

          if (!_messagingAllowed)
            Material(
              color: Colors.grey.shade300,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.block, size: 16, color: Colors.grey.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _messagingBlockedReason ??
                            'Messaging is disabled for this conversation.',
                        style: TextStyle(
                            color: Colors.grey.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Input row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Attachment button
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Attach',
                  onPressed: (_isUploading || !_messagingAllowed)
                      ? null
                      : _showAttachmentSheet,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: _messagingAllowed && !_isUploading,
                    readOnly: !_messagingAllowed || _isUploading,
                    decoration: InputDecoration(
                      hintText: _messagingAllowed
                          ? 'Type a message...'
                          : 'Messaging disabled',
                      border: OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: _messagingAllowed ? null : Colors.grey,
                  onPressed: _messagingAllowed ? sendMessage : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Audio recording dialog ────────────────────────────────────────────────────

class _RecordingDialog extends StatefulWidget {
  final AudioRecorder recorder;
  const _RecordingDialog({required this.recorder});

  @override
  State<_RecordingDialog> createState() => _RecordingDialogState();
}

class _RecordingDialogState extends State<_RecordingDialog> {
  int _seconds = 0;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await widget.recorder.start(const RecordConfig(), path: path);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
      if (mounted) setState(() => _started = true);
    } catch (e) {
      if (mounted) Navigator.pop(context, false);
    }
  }

  String get _timeLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recording'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text(_timeLabel,
              style:
                  const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _started ? 'Recording...' : 'Starting...',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            _timer?.cancel();
            await widget.recorder.cancel();
            if (mounted) Navigator.pop(context, false);
          },
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('Send'),
          onPressed: _started
              ? () {
                  _timer?.cancel();
                  Navigator.pop(context, true);
                }
              : null,
        ),
      ],
    );
  }
}
