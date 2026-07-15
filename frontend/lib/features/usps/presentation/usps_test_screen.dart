import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/config/env_constant.dart';

class UspsTestScreen extends StatefulWidget {
  const UspsTestScreen({super.key});
  @override
  State<UspsTestScreen> createState() => _UspsTestScreenState();
}

class _UspsTestScreenState extends State<UspsTestScreen> {
  Map<String, dynamic>? digest;
  bool loading = false;
  String? error;
  bool isGoogleConnected = false;
  bool needsGoogleReconnect = false;
  String? reconnectMessage;
  DateTime selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  bool searchLoading = false;
  String? searchError;
  bool _isSearchActive = false;

  Future<void> _fetchDigest() async {
    setState(() {
      loading = true;
      error = null;
      _isSearchActive = false;
    });
    final base = getBackendBaseUrl();

    // Get user ID to pass as parameter
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    final dynamic userIdRaw = user?.id;
    final userId = userIdRaw?.toString() ?? 'demo-user';

    // Format date as YYYY-MM-DD
    final dateString =
        '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
    final encodedUser = Uri.encodeComponent(userId);
    final url = '$base/api/usps/latest?userId=$encodedUser&date=$dateString';

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ));

      final resp = await dio.get(url);
      if (resp.statusCode == 200) {
        setState(() {
          digest = resp.data is Map<String, dynamic>
              ? (resp.data as Map<String, dynamic>)
              : json.decode(json.encode(resp.data)) as Map<String, dynamic>;
          searchResults = [];
          searchError = null;
          needsGoogleReconnect = false;
          reconnectMessage = null;
          _searchController.clear();
        });
      } else if (resp.statusCode == 204) {
        setState(() {
          digest = null;
          error = 'No USPS digest found for $dateString.';
        });
      } else if (resp.statusCode == 409) {
        _handleNeedsReauth(resp.data);
      } else {
        setState(() => error = 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 409) {
        _handleNeedsReauth(e.response?.data);
      } else {
        setState(() => error = e.toString());
      }
    } finally {
      setState(() => loading = false);
    }
  }

  void _handleNeedsReauth(dynamic data) {
    String message =
        'Gmail access was revoked or expired. Reconnect to resume USPS mail sync.';
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final apiMessage = map['message']?.toString();
      if (apiMessage != null && apiMessage.isNotEmpty) {
        message = apiMessage;
      }
    }
    setState(() {
      needsGoogleReconnect = true;
      isGoogleConnected = false;
      reconnectMessage = message;
      error = message;
      digest = null;
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020), // USPS Informed Delivery started around 2017
      lastDate: DateTime.now(),
      helpText: 'Select digest date',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        digest = null; // Clear previous digest when date changes
        error = null;
        _isSearchActive = false;
        searchResults = [];
        searchError = null;
        _searchController.clear();
      });

      // Automatically fetch digest for the new date
      _fetchDigest();
    }
  }

  Future<void> _searchMail() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _isSearchActive = false;
        searchResults = [];
        searchError = null;
      });
      return;
    }

    setState(() {
      _isSearchActive = true;
      searchLoading = true;
      searchError = null;
    });

    final base = getBackendBaseUrl();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    final dynamic userIdRaw = user?.id;
    final userId = userIdRaw?.toString() ?? 'demo-user';
    final encodedUser = Uri.encodeComponent(userId);

    final url =
        '$base/api/usps/search?userId=$encodedUser&keyword=${Uri.encodeComponent(keyword)}';

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));

      final resp = await dio.get(url);
      if (resp.statusCode == 200) {
        setState(() {
          searchResults = List<Map<String, dynamic>>.from(resp.data ?? []);
        });
      } else {
        setState(() => searchError = 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => searchError = e.toString());
    } finally {
      setState(() => searchLoading = false);
    }
  }

  Future<void> _openUri(String? u) async {
    if (u == null || u.isEmpty) return;
    final uri = Uri.parse(u);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  Future<void> _checkGoogleConnection() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;
    final encodedUser = Uri.encodeComponent(user.id.toString());

    final base = getBackendBaseUrl();
    try {
      final dio = Dio();
      // Prefer rich connection status so revoked tokens surface as reconnect.
      try {
        final details = await dio.get(
            '$base/api/email-credentials/connection?userId=$encodedUser');
        if (details.statusCode == 200 && details.data is Map) {
          final map = Map<String, dynamic>.from(details.data as Map);
          final connected = map['connected'] == true;
          final needsReconnect = map['needsReconnect'] == true;
          setState(() {
            isGoogleConnected = connected;
            needsGoogleReconnect = needsReconnect;
            reconnectMessage = needsReconnect
                ? ((map['lastError'] as String?)?.trim().isNotEmpty == true
                    ? map['lastError'] as String
                    : 'Gmail access was revoked or expired. Reconnect to resume USPS mail sync.')
                : null;
          });
          return;
        }
      } catch (_) {
        // Fall back to legacy boolean status endpoint.
      }

      final resp = await dio
          .get('$base/api/email-credentials/status?userId=$encodedUser');
      if (resp.statusCode == 200 && resp.data == true) {
        setState(() {
          isGoogleConnected = true;
          needsGoogleReconnect = false;
          reconnectMessage = null;
        });
      } else {
        setState(() {
          isGoogleConnected = false;
        });
      }
    } catch (e) {
      // Connection check failed, assume not connected
      setState(() {
        isGoogleConnected = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _checkGoogleConnection().then((_) {
      // Auto-fetch today's digest after checking connection
      if (isGoogleConnected) {
        _fetchDigest();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh connection status when coming back from OAuth
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkGoogleConnection();
    });
  }

  Future<void> _clearCache() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    final dynamic userIdRaw = user?.id;
    final userId = userIdRaw?.toString() ?? 'demo-user';

    final base = getBackendBaseUrl();
    try {
      final dio = Dio();
      await dio.post(
          '$base/api/usps/clear-cache?userId=${Uri.encodeComponent(userId)}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cache cleared! Try fetching digest again.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to clear cache')),
      );
    }
  }

  Future<void> _resetSearchToToday() async {
    _searchController.clear();
    setState(() {
      _isSearchActive = false;
      searchResults = [];
      searchError = null;
      selectedDate = DateTime.now();
      digest = null;
      error = null;
    });
    await _fetchDigest();
  }

  Future<void> _connectGoogleAccount() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first')),
      );
      return;
    }

    final base = getBackendBaseUrl();

    // Use a platform-safe return URL; Uri.base works on web and mobile.
    final currentUrl = kIsWeb ? Uri.base.toString() : getWebBaseUrl();
    final authUrl =
        '$base/oauth/google/start?userId=${Uri.encodeComponent(user.id.toString())}&returnUrl=${Uri.encodeComponent(currentUrl)}';

    final uri = Uri.parse(authUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google authentication')),
        );
      }
    }
  }

  Widget _buildMailImage(
    String? imageDataUrl, {
    double width = 48,
    double height = 32,
    BoxFit fit = BoxFit.cover,
  }) {
    final iconSize = height.clamp(16, 48).toDouble();
    Widget placeholder(IconData icon) => SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Icon(
                icon,
                color: Colors.grey.shade600,
                size: iconSize,
              ),
            ),
          ),
        );

    if (imageDataUrl == null || imageDataUrl.isEmpty) {
      return placeholder(Icons.mail_outline);
    }

    if (imageDataUrl.startsWith('cid:')) {
      return placeholder(Icons.mail_outline);
    }

    if (imageDataUrl.startsWith('data:')) {
      try {
        final uri = Uri.parse(imageDataUrl);
        final data = uri.data;
        if (data != null) {
          final bytes = data.contentAsBytes();
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => placeholder(Icons.mail_outline),
          );
        }
      } catch (_) {
        // fall through to manual base64 decode
      }

      try {
        final base64Data = imageDataUrl.split(',').last;
        final bytes = const Base64Decoder().convert(base64Data);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => placeholder(Icons.mail_outline),
        );
      } catch (_) {
        return placeholder(Icons.mail_outline);
      }
    }

    if (imageDataUrl.startsWith('http')) {
      return Image.network(
        imageDataUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => placeholder(Icons.mail_outline),
      );
    }

    return placeholder(Icons.mail_outline);
  }

  bool _hasAttachment(String? imageDataUrl) {
    if (imageDataUrl == null || imageDataUrl.isEmpty) {
      return false;
    }
    if (imageDataUrl.startsWith('cid:')) {
      return false;
    }
    return true;
  }

  void _showMailItemDetails(Map<String, dynamic> item) {
    final type = ((item['type'] as String?) ?? 'mail').toLowerCase();
    final bool isPackage = type == 'package';

    final imageSource =
        (item['imageDataUrl'] as String?) ?? (item['thumbnailUrl'] as String?);
    final hasAttachment = !isPackage && _hasAttachment(imageSource);
    final actions = item['actions'];
    final Map<String, dynamic> actionsMap = actions is Map<String, dynamic>
        ? Map<String, dynamic>.from(actions as Map)
        : <String, dynamic>{};
    final trackUrl = actionsMap['track'] as String?;
    final dashboardUrl = actionsMap['dashboard'] as String?;
    final rawSender = (item['sender'] as String?)?.trim();
    final sender = (rawSender != null && rawSender.isNotEmpty)
        ? rawSender
        : (isPackage ? 'USPS Package' : 'Unknown sender');
    final subject = (item['summary'] as String?) ??
        (item['subject'] as String?) ??
        (isPackage && item['trackingNumber'] != null
            ? 'Tracking ${item['trackingNumber']}'
            : 'No subject available');
    final trackingNumber = item['trackingNumber'] as String?;
    final delivered =
        (item['deliveryDate'] as String?) ?? (item['receivedAt'] as String?);
    final expectedIso = item['expectedDateIso'] as String?;
    final expectedDisplay = (item['expectedDate'] as String?) ??
        (expectedIso != null ? _formatDateLabel(expectedIso) : null);

    final typeLabel = isPackage ? 'Package' : 'Mail Piece';
    final primaryActionUrl =
        isPackage ? (trackUrl ?? dashboardUrl) : (dashboardUrl ?? trackUrl);
    final primaryActionLabel =
        isPackage ? 'Track Package' : 'View in USPS Dashboard';
    final String? dateLabel = isPackage ? expectedDisplay : delivered;
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sender,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(typeLabel),
                        backgroundColor: isPackage
                            ? Colors.orange.shade100
                            : Colors.blue.shade100,
                        labelStyle: TextStyle(
                          color: isPackage
                              ? Colors.orange.shade800
                              : Colors.blue.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildMailImage(
                        imageSource,
                        width: 260,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isPackage ? 'Details' : 'Subject',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subject,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      if (hasAttachment) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.attachment, size: 18),
                      ],
                    ],
                  ),
                  if (rawSender != null && rawSender.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'From: $sender',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (isPackage &&
                      trackingNumber != null &&
                      trackingNumber.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Tracking Number',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            trackingNumber,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (trackUrl != null && trackUrl.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _openUri(trackUrl);
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Track'),
                          ),
                      ],
                    ),
                  ],
                  if (dateLabel != null && dateLabel.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      isPackage ? 'Expected Delivery' : 'Delivered',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (primaryActionUrl != null &&
                      primaryActionUrl.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openUri(primaryActionUrl);
                        },
                        icon: Icon(isPackage
                            ? Icons.local_shipping
                            : Icons.open_in_new),
                        label: Text(primaryActionLabel),
                      ),
                    ),
                  ],
                  if (!isPackage &&
                      trackUrl != null &&
                      trackUrl.isNotEmpty &&
                      trackUrl != primaryActionUrl) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openUri(trackUrl);
                        },
                        icon: const Icon(Icons.local_shipping),
                        label: const Text('Track Package'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDateLabel(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return iso;
    }

    return '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final mail = (digest?['mailpieces'] as List?) ?? const [];
    final pkgs = (digest?['packages'] as List?) ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('USPS Mail Digest')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Google Authentication Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mail, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Gmail Integration',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      needsGoogleReconnect
                          ? (reconnectMessage ??
                              'Gmail access was revoked or expired. Reconnect to resume USPS mail sync.')
                          : isGoogleConnected
                              ? '✅ Google account connected! You can now fetch USPS digests automatically.'
                              : 'Connect your Google account to automatically fetch USPS digests from Gmail.',
                      style: TextStyle(
                        color: needsGoogleReconnect
                            ? Colors.orange.shade800
                            : isGoogleConnected
                                ? Colors.green
                                : Colors.grey,
                      ),
                    ),
                    if (needsGoogleReconnect) ...[
                      const SizedBox(height: 12),
                      Container(
                        key: const Key('gmailReauthBanner'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mail sync paused',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Reconnect Gmail to restore Informed Delivery sync.',
                              style: TextStyle(color: Colors.orange.shade900),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                key: const Key('gmailReconnectButton'),
                                onPressed: _connectGoogleAccount,
                                icon: const Icon(Icons.link),
                                label: const Text('Reconnect Gmail'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade800,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (!isGoogleConnected && !needsGoogleReconnect)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _connectGoogleAccount,
                          icon: const Icon(Icons.link),
                          label: const Text('Connect Google Account'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      )
                    else if (isGoogleConnected)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              isGoogleConnected = false;
                              needsGoogleReconnect = false;
                            });
                            _connectGoogleAccount();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reconnect Google Account'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date Selection and Search Section
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Selection Section (Half Screen)
                Expanded(
                  flex: 1,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  color: Theme.of(context).primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Select Digest Date',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose any date to view historical USPS digest data.',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _selectDate,
                              icon: const Icon(Icons.calendar_today),
                              label: Text(
                                '${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.year}',
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context).primaryColor,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  selectedDate = DateTime.now();
                                  digest = null;
                                  error = null;
                                });
                                _fetchDigest();
                              },
                              icon: const Icon(Icons.today, size: 16),
                              label: const Text('Go to Today'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey[600],
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Search Section (Half Screen)
                Expanded(
                  flex: 1,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.search,
                                  color: Theme.of(context).primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Search Mail History',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Search for mail by sender, subject, or any keyword.',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Enter keyword to search...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      onPressed: () => _resetSearchToToday(),
                                      icon: const Icon(Icons.clear),
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                            ),
                            onChanged: (value) {
                              setState(
                                  () {}); // Trigger rebuild to show/hide clear button
                            },
                            onSubmitted: (value) => _searchMail(),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: searchLoading ? null : _searchMail,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: searchLoading
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Text('Search'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Existing controls
            Row(children: [
              ElevatedButton(
                onPressed: loading ? null : _fetchDigest,
                child: const Text('Fetch Digest'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: loading ? null : _clearCache,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Clear Cache'),
              ),
              const SizedBox(width: 12),
              if (loading) const CircularProgressIndicator(),
            ]),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  // Show search results if available
                  if (_isSearchActive && searchResults.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Found ${searchResults.length} mail items matching "${_searchController.text}"',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _resetSearchToToday(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.green,
                            ),
                            child: const Text('Clear Search'),
                          ),
                        ],
                      ),
                    ),
                    const Text('Search Results',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final result in searchResults)
                      Builder(
                        builder: (context) {
                          final type = ((result['type'] as String?) ?? 'mail')
                              .toLowerCase();
                          final isPackage = type == 'package';
                          final actions = result['actions'];
                          final actionsMap = actions is Map<String, dynamic>
                              ? Map<String, dynamic>.from(actions as Map)
                              : <String, dynamic>{};
                          final trackUrl = actionsMap['track'] as String?;
                          final dashboardUrl =
                              actionsMap['dashboard'] as String?;
                          final trailingUrl = isPackage
                              ? (trackUrl ?? dashboardUrl)
                              : (dashboardUrl ?? trackUrl);
                          final trailingIcon = isPackage
                              ? Icons.local_shipping
                              : Icons.open_in_new;
                          final summary = result['summary'] ??
                              result['subject'] ??
                              'No summary';
                          final from = result['sender'] as String?;
                          final attachmentSource =
                              (result['imageDataUrl'] as String?) ??
                                  (result['thumbnailUrl'] as String?);
                          final hasAttachment =
                              !isPackage && _hasAttachment(attachmentSource);
                          final deliveryLabel = isPackage
                              ? (result['expectedDate'] as String?) ??
                                  (result['deliveryDate'] as String?)
                              : result['deliveryDate'] as String?;
                          final deliveryPrefix =
                              isPackage ? 'Expected: ' : 'Delivered: ';

                          return Card(
                            child: ListTile(
                              onTap: () => _showMailItemDetails(
                                  Map<String, dynamic>.from(result)),
                              leading: _buildMailImage(
                                (result['imageDataUrl'] as String?) ??
                                    (result['thumbnailUrl'] as String?),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        result['sender'] ?? 'Unknown Sender'),
                                  ),
                                  if (hasAttachment) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.attachment, size: 16),
                                  ],
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isPackage
                                          ? Colors.orange.withOpacity(0.15)
                                          : Colors.blue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isPackage ? 'Package' : 'Mail',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isPackage
                                            ? Colors.orange[800]
                                            : Colors.blue[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (from != null && from.isNotEmpty)
                                    Text('From: $from'),
                                  Text(summary),
                                  if (deliveryLabel != null &&
                                      deliveryLabel.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .primaryColor
                                            .withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$deliveryPrefix$deliveryLabel',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).primaryColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(trailingIcon),
                                onPressed:
                                    trailingUrl == null || trailingUrl.isEmpty
                                        ? null
                                        : () => _openUri(trailingUrl),
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                  ],

                  // Show search error if any
                  if (_isSearchActive && searchError != null) ...[
                    Card(
                      color: Colors.red.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Search failed: $searchError',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_isSearchActive &&
                      !searchLoading &&
                      searchError == null &&
                      searchResults.isEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.info, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No mail items matched "${_searchController.text.trim()}".',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _resetSearchToToday(),
                              child: const Text('Show Today\'s Mail'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Show selected date info
                  if (digest != null && !_isSearchActive) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Theme.of(context)
                                .primaryColor
                                .withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event,
                              color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Showing digest for ${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if (pkgs.isNotEmpty || mail.isNotEmpty) ...[
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${pkgs.length + mail.length} items',
                              style: const TextStyle(
                                  color: Colors.green, fontSize: 12),
                            ),
                          ] else ...[
                            Icon(
                              Icons.info,
                              color: Colors.grey,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'No items',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (!_isSearchActive && pkgs.isNotEmpty) ...[
                    const Text('Packages',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final p in pkgs)
                      Builder(
                        builder: (context) {
                          if (p is! Map) {
                            return const SizedBox.shrink();
                          }

                          final pkg = Map<String, dynamic>.from(p);
                          final expectedIso = pkg['expectedDateIso'] as String?;
                          final expectedLabel =
                              expectedIso != null && expectedIso.isNotEmpty
                                  ? _formatDateLabel(expectedIso)
                                  : '—';
                          final sender = (pkg['sender'] as String?)?.trim();
                          final trackingNumber =
                              pkg['trackingNumber'] as String?;
                          final actions = pkg['actions'];
                          final actionsMap = actions is Map<String, dynamic>
                              ? Map<String, dynamic>.from(actions as Map)
                              : <String, dynamic>{};
                          final trackUrl = actionsMap['track'] as String?;
                          final dashboardUrl =
                              actionsMap['dashboard'] as String?;
                          final trailingUrl = trackUrl ?? dashboardUrl;

                          final detailPayload = {
                            ...pkg,
                            'type': 'package',
                            'sender': sender ?? 'USPS Package',
                            'expectedDate': expectedLabel,
                            'expectedDateIso': expectedIso,
                            'trackingNumber': trackingNumber,
                          };

                          return Card(
                            child: ListTile(
                              onTap: () => _showMailItemDetails(detailPayload),
                              leading: CircleAvatar(
                                backgroundColor:
                                    Colors.orange.withOpacity(0.15),
                                child: Icon(Icons.local_shipping,
                                    color: Colors.orange[700]),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        sender ?? trackingNumber ?? 'Package'),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Package',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (sender != null && sender.isNotEmpty)
                                    Text('From: $sender'),
                                  if (trackingNumber != null &&
                                      trackingNumber.isNotEmpty)
                                    Text('Tracking: $trackingNumber'),
                                  Text('Expected: $expectedLabel'),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.local_shipping),
                                onPressed:
                                    trailingUrl == null || trailingUrl.isEmpty
                                        ? null
                                        : () => _openUri(trailingUrl),
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (!_isSearchActive && mail.isNotEmpty) ...[
                    const Text('Mail Pieces',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final m in mail)
                      Builder(
                        builder: (context) {
                          if (m is! Map) {
                            return const SizedBox.shrink();
                          }
                          final mailPiece = Map<String, dynamic>.from(m);
                          final imageSource =
                              (mailPiece['imageDataUrl'] as String?) ??
                                  (mailPiece['thumbnailUrl'] as String?);
                          final hasAttachment = _hasAttachment(imageSource);
                          final summary = ((mailPiece['summary'] as String?) ??
                                  (mailPiece['subject'] as String?) ??
                                  '')
                              .trim();
                          final senderName =
                              (mailPiece['sender'] as String?)?.trim();
                          final displayTitle =
                              (senderName != null && senderName.isNotEmpty)
                                  ? senderName
                                  : (summary.isNotEmpty ? summary : 'Mail');
                          mailPiece['type'] ??= 'mail';
                          final actions = mailPiece['actions'];
                          final actionsMap = actions is Map<String, dynamic>
                              ? Map<String, dynamic>.from(actions as Map)
                              : <String, dynamic>{};
                          final dashboardUrl =
                              actionsMap['dashboard'] as String?;
                          final trackUrl = actionsMap['track'] as String?;
                          final trailingUrl = dashboardUrl ?? trackUrl;

                          return Card(
                            child: ListTile(
                              onTap: () => _showMailItemDetails(
                                  Map<String, dynamic>.from(mailPiece)),
                              leading: _buildMailImage(imageSource),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(displayTitle),
                                  ),
                                  if (hasAttachment) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.attachment, size: 16),
                                  ],
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Mail',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle:
                                  summary.isNotEmpty && summary != displayTitle
                                      ? Text(summary)
                                      : const SizedBox.shrink(),
                              trailing: IconButton(
                                icon: const Icon(Icons.open_in_new),
                                onPressed:
                                    trailingUrl == null || trailingUrl.isEmpty
                                        ? null
                                        : () => _openUri(trailingUrl),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                  if ((mail.isEmpty && pkgs.isEmpty) &&
                      digest != null &&
                      !_isSearchActive)
                    const Center(child: Text('No items in digest')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
